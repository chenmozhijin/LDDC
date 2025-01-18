# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import re
from xml.etree import ElementTree as ET


def add2ts(ts_file: str, mapping: dict[str, int], msgs: dict[int, tuple[str, str]]) -> None:
    tree = ET.parse(ts_file)  # noqa: S314
    root = tree.getroot()
    count = 0
    for context in root.findall("context"):
        for msg in context.findall("message"):
            source = msg.find("source")
            translation = msg.find("translation")
            if source is not None and source.text and (translation is not None and not translation.text):
                index = mapping.get(source.text)
                if index is not None and msgs[index][0] == source.text:
                    translation.text = msgs[index][1]
                    translation.set("type", "unfinished")
                    count += 1
                else:
                    translation.text = ""
    tree.write(ts_file, encoding="utf-8", xml_declaration=True)
    print(f"已添加{count}条翻译")


if __name__ == "__main__":
    ts_file = input("输入ts文件路径：")
    ts = ""
    while True:
        i = input("翻译")
        if i == "":
            break
        ts += i + "\n"
    pattern = re.compile(r"\[(?P<index>\d+)\](?P<source>.+) --> (?P<translation>.*)")
    mapping = {}
    msgs = {}
    for m in pattern.findall(ts):
        if m:
            mapping[m[1].replace("\\n", "\n")] = int(m[0])
            msgs[int(m[0])] = (m[1].replace("\\n", "\n"), m[2].replace("\\n", "\n"))
    add2ts(ts_file, mapping, msgs)
