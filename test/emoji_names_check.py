"""Checks every shipped EmojiTwo label, including legacy/custom sequences."""
import json
from pathlib import Path
import re


def load_unique(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise AssertionError(f"Duplicate emoji key: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs)


def main():
    root = Path(__file__).resolve().parents[1]
    catalog = load_unique(root / "assets/emojitwo/emoji.json")
    names = load_unique(root / "assets/emojitwo/zh_names.json")
    assert names.keys() == catalog.keys(), "中文名称必须覆盖全部目录且没有多余键"
    for code, name in names.items():
        assert isinstance(name, str) and name.strip() == name and name, code
        assert not re.search(r"[A-Za-z]", name), (code, name)
        assert re.search(r"[\u3400-\u9fff]", name), (code, name)
    assert names["1f60b"] == "好吃", "截图中的美味表情必须使用完整中文名称"
    assert "家庭" in names["1f468-1f469-1f467"], "兼容旧版家庭组合序列"
    assert names["1f3f3-1f308"] == "彩虹旗", "兼容旧版彩虹旗序列"
    assert "肤色" in names["1f58e-1f3ff"], "覆盖自定义符号肤色变体"
    print(f"Passed: {len(names)} emoji labels, complete coverage, no English fragments.")


if __name__ == "__main__":
    main()
