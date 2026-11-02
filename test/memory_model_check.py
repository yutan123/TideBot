"""Read-only model contract checks and in-memory SQLite invalidation checks.

Run with Python packages onnxruntime, tokenizers, numpy installed, passing a
folder containing the pinned model_int8.onnx, vocab.txt and tokenizer.json.
This does not build or run the Android application.
"""
import hashlib
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check_storage():
    source = (ROOT / 'lib/memory_retrieval_service.dart').read_text()
    statements = re.findall(r'''db.execute\(\s*(['"])(CREATE [\s\S]*?)\1\s*\)''', source)
    assert len(statements) == 5, 'Read the actual cache table and all four triggers'
    db = sqlite3.connect(':memory:')
    db.executescript('''
      CREATE TABLE memories(id TEXT PRIMARY KEY, bot_id TEXT, content TEXT);
      CREATE TABLE world_book_entries(id TEXT PRIMARY KEY, content TEXT);
    ''')
    for _, sql in statements:
        db.execute(sql)
    db.execute("INSERT INTO memories VALUES ('a', 'bot1', 'old')")
    db.execute("INSERT INTO world_book_entries VALUES ('legacy', 'old')")
    def cache(bot, source_id):
        db.execute('INSERT OR REPLACE INTO memory_vectors VALUES (?, ?, ?, ?, ?)',
                   (bot, source_id, 'model', 'hash', '[1]'))
    cache('bot1', 'memories:a')
    cache('bot2', 'memories:a')
    db.execute("UPDATE memories SET content='new' WHERE id='a'")
    assert db.execute('SELECT bot_id FROM memory_vectors').fetchall() == [('bot2',)]
    cache('bot1', 'memories:a')
    db.execute("DELETE FROM memories WHERE id='a'")
    assert db.execute('SELECT bot_id FROM memory_vectors').fetchall() == [('bot2',)]
    cache('bot1', 'world_book_entries:legacy')
    cache('bot2', 'world_book_entries:legacy')
    db.execute("UPDATE world_book_entries SET content='new' WHERE id='legacy'")
    assert db.execute("SELECT COUNT(*) FROM memory_vectors WHERE source_id='world_book_entries:legacy'").fetchone()[0] == 0
    cache('bot1', 'world_book_entries:legacy')
    db.execute("DELETE FROM world_book_entries WHERE id='legacy'")
    assert db.execute("SELECT COUNT(*) FROM memory_vectors WHERE source_id='world_book_entries:legacy'").fetchone()[0] == 0
    print('SQLite: actual cache DDL, update/delete triggers and bot isolation passed')
    # Exercise the actual live-row predicates from queryMemories at expiry boundaries.
    db_source = (ROOT / 'lib/db.dart').read_text()
    query = db_source.split('>>> queryMemories(', 1)[-1].split('queryMemoriesRelevant', 1)[0]
    initial = re.search(r'whereParts = <String>\[(.*?)\];', query, re.S)[1]
    predicates = re.findall(r"'([^']+)'", initial)
    predicates += [re.search(r"\.add\('([^']*expires_at[^']*)'\)", query)[1]]
    db.execute('CREATE TABLE live_rows(id TEXT, bot_id TEXT, is_deleted INTEGER, expires_at INTEGER)')
    db.executemany('INSERT INTO live_rows VALUES (?, ?, ?, ?)', [
        ('valid', 'bot1', 0, 101), ('permanent', 'bot1', None, 0),
        ('expired', 'bot1', 0, 99), ('boundary', 'bot1', 0, 100),
        ('deleted', 'bot1', 1, None), ('other_bot', 'bot2', 0, None),
    ])
    live = db.execute('SELECT id FROM live_rows WHERE ' + ' AND '.join(predicates), ('bot1', 100)).fetchall()
    assert set(live) == {('valid',), ('permanent',)}, live
    print('SQLite: actual active-row predicates exclude deleted/expired/other-bot memories')


def check_model(folder):
    import numpy as np
    import onnxruntime as ort
    from tokenizers import Tokenizer
    ort.set_default_logger_severity(3)
    native = (ROOT / 'android/app/src/main/kotlin/com/yutan123/tidebot/TideMemoryEmbeddingEngine.kt').read_text()
    for name, size, digest in re.findall(r'Triple\("([^"]+)", (\d+)L, "([0-9a-f]+)"\)', native):
        data = (folder / name.split('/')[-1]).read_bytes()
        assert len(data) == int(size)
        assert hashlib.sha256(data).hexdigest() == digest
    tokenizer = Tokenizer.from_file(str(folder / 'tokenizer.json'))
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    options.enable_cpu_mem_arena = False
    options.enable_mem_pattern = False
    options.log_severity_level = 3
    session = ort.InferenceSession(str(folder / 'model_int8.onnx'), options, providers=['CPUExecutionProvider'])
    assert {x.name for x in session.get_inputs()} == {'input_ids', 'attention_mask', 'token_type_ids'}
    assert session.get_outputs()[0].name == 'last_hidden_state'
    assert session.get_outputs()[0].shape[-1] == 512
    def embed(text):
        ids = tokenizer.encode(text).ids
        ids = ids[:511] + [102] if len(ids) > 512 else ids
        inputs = np.array([ids], dtype=np.int64)
        out = session.run(None, {'input_ids': inputs, 'attention_mask': np.ones_like(inputs),
                                 'token_type_ids': np.zeros_like(inputs)})[0][0, 0]
        vector = out / np.linalg.norm(out)
        assert len(vector) == 512 and np.isfinite(vector).all()
        assert abs(float(vector @ vector) - 1) < 1e-5
        return vector
    documents = ['用户的生日是八月十六日。', '对方养了一只叫团子的布偶猫。',
                 '用户有花生过敏史，饮食需要避开花生。', '双方约好周六去海边看日落。', '角色今天喝了一杯咖啡。']
    vectors = np.array([embed(x) for x in documents])
    threshold = float(re.search(r'semanticMemoryThreshold = ([0-9.]+)',
                               (ROOT / 'lib/memory_retrieval_policy.dart').read_text())[1])
    for query, target in [('我的生日是哪一天', 0), ('我家那只小家伙叫什么', 1),
                          ('我不吃花生，会过敏', 2), ('周末去哪里玩', 3)]:
        scores = vectors @ embed('为这个句子生成表示以用于检索相关文章：' + query)
        assert int(scores.argmax()) == target, (query, scores)
        assert scores[target] >= threshold, (query, scores)
        assert all(score < threshold for i, score in enumerate(scores) if i != target)
        print(f'ONNX semantic retrieval: {query} -> {documents[target]} ({scores[target]:.4f})')
    # Validate model behavior on the maximal accepted sequence length too.
    embed('这是用于验证长文本截断的记忆。' * 100)
    print('Pinned ONNX model: hashes, int64 inputs, 512D CLS pooling, normalization and semantic checks passed')


if __name__ == '__main__':
    check_storage()
    if len(sys.argv) > 1:
        check_model(Path(sys.argv[1]).resolve())
