# 中文表情名称来源

`zh_names.json` 覆盖本目录 `emoji.json` 的全部 2,013 个条目。

标准名称取自 Unicode CLDR 48 的简体中文表情注释：

- https://github.com/unicode-org/cldr/blob/release-48/common/annotations/zh.xml
- https://github.com/unicode-org/cldr/blob/release-48/common/annotationsDerived/zh.xml

Copyright © 1991-2025 Unicode, Inc. 保留上游许可全文于 [CLDR-LICENSE.txt](CLDR-LICENSE.txt)。

适配说明：按 Unicode 序列匹配，兼容旧 EmojiTwo 数据省略连接符及变体选择符的写法；非标准、历史符号及部分字母缩写由 TideBot 补译或改写为中文。`emoji.json` 与图像原文件保持原样，独立中文名称表由聊天面板加载，用于名称提示、无障碍名称和发送给模型的表情说明。
