# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from pathlib import Path
from xml.etree import ElementTree as ET

import opencc

converter = opencc.OpenCC("s2t.json")


def s2t(ts_file: str) -> None:
    tree = ET.parse(ts_file)  # noqa: S314
    root = tree.getroot()
    for context in root.findall("context"):
        for msg in context.findall("message"):
            source = msg.find("source")
            translation = msg.find("translation")
            if source is not None and (translation is not None and not translation.text):
                t = converter.convert(source.text)
                translation.text = t
    tree.write(ts_file, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    i18n_path = Path(__file__).parent.parent / "LDDC" / "res" / "i18n"
    for file in i18n_path.iterdir():
        if file.name == "LDDC_zh-Hant.ts":
            s2t(str(file))
