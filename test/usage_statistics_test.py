"""Exercise the production statistics SQL with SQLite, without Flutter builds."""
import datetime as dt
import os
from pathlib import Path
import sqlite3
import time
import unittest


class UsageStatisticsTest(unittest.TestCase):
    def setUp(self):
        self.old_tz = os.environ.get('TZ')
        os.environ['TZ'] = 'Asia/Shanghai'
        time.tzset()
        source = (Path(__file__).resolve().parents[1] / 'lib/db.dart').read_text()
        method = source.split('>>> dailyUsageStats(', 1)[1]
        self.sql = method.split("'''", 2)[1]
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
            CREATE TABLE ai_usage_events (
                bot_id TEXT, event_type TEXT, timestamp INTEGER,
                total_tokens INTEGER, reply_count INTEGER);
            CREATE TABLE chat_history (
                bot_id TEXT, role TEXT, type TEXT, timestamp INTEGER,
                error_log TEXT, error_code TEXT);
        ''')
        self.today = int(dt.datetime(2026, 11, 5).timestamp() * 1000)

    def tearDown(self):
        self.db.close()
        if self.old_tz is None:
            os.environ.pop('TZ', None)
        else:
            os.environ['TZ'] = self.old_tz
        time.tzset()

    def usage(self, tokens, kind='chat', bot='a', offset=1000):
        self.db.execute('INSERT INTO ai_usage_events VALUES (?, ?, ?, ?, 1)',
                        (bot, kind, self.today + offset, tokens))

    def reply(self, bot='a', offset=1000, role='assistant', kind='text',
              error_log=None, error_code=None):
        self.db.execute('INSERT INTO chat_history VALUES (?, ?, ?, ?, ?, ?)',
                        (bot, role, kind, self.today + offset, error_log, error_code))

    def stats(self, bot=None, since=0):
        sql = self.sql.replace('$botFilter', '' if bot is None else 'AND bot_id = ?')
        args = [since] if bot is None else [since, bot]
        return list(self.db.execute(sql, args + args))

    def totals(self, **kwargs):
        rows = self.stats(**kwargs)
        return (sum(r['total_tokens'] for r in rows),
                sum(r['reply_count'] for r in rows))

    def test_proactive_and_other_requests_are_included(self):
        self.usage(100)
        self.usage(200, 'proactiveChat')
        self.usage(50, 'jarvis')
        self.reply()
        self.reply(offset=2000)
        self.assertEqual(self.totals(), (350, 2))

    def test_replies_count_bubbles_not_requests_or_silence(self):
        self.usage(100, 'proactiveChat')
        self.usage(20, 'proactiveChat')  # Silent request, no delivered message.
        self.reply()
        self.reply()
        self.reply()
        self.assertEqual(self.totals(), (120, 3))

    def test_history_without_usage_counts_all_replies_without_fake_tokens(self):
        for _ in range(3):
            self.reply(offset=-86400000)
        self.assertEqual(self.totals(), (0, 3))
        self.assertEqual(self.totals(since=self.today), (0, 0))

    def test_errors_user_and_non_text_do_not_count(self):
        self.reply()
        self.reply(role='user')
        self.reply(kind='call_summary')
        self.reply(error_log='failed')
        self.reply(error_code='timeout')
        self.assertEqual(self.totals(), (0, 1))

    def test_global_totals_equal_sum_of_bot_sidebars(self):
        self.usage(100, bot='a')
        self.usage(250, 'proactiveChat', bot='b')
        self.reply(bot='a')
        self.reply(bot='b')
        global_totals = self.totals(since=self.today)
        a = self.totals(bot='a', since=self.today)
        b = self.totals(bot='b', since=self.today)
        self.assertEqual(global_totals, tuple(x + y for x, y in zip(a, b)))
        self.assertEqual(a, (100, 1))
        self.assertEqual(b, (250, 1))

    def test_local_midnight_and_empty_database(self):
        self.assertEqual(self.totals(), (0, 0))
        self.usage(10, offset=-1)
        self.usage(20, offset=0)
        self.reply(offset=-1)
        self.reply(offset=0)
        self.assertEqual(len(self.stats()), 2)
        self.assertEqual(self.totals(since=self.today), (20, 1))
        self.assertEqual(self.totals(), (30, 2))


if __name__ == '__main__':
    unittest.main()
