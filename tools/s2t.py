# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: T201 INP001
from xml.etree import ElementTree as ET

import opencc

converter = opencc.OpenCC('s2t.json')


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
    import os
    i18n_path = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "LDDC", "res", "i18n"))
    for file in os.listdir(i18n_path):
        if file == "LDDC_zh-Hant.ts":
            msgs = s2t(os.path.join(i18n_path, file))
