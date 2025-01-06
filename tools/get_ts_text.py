# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: T201 INP001
from xml.etree import ElementTree as ET


def get_ts_text(ts_file: str) -> list[tuple[str, str | None]]:
    tree = ET.parse(ts_file)  # noqa: S314
    root = tree.getroot()
    msgs = []
    for context in root.findall("context"):
        for msg in context.findall("message"):
            source = msg.find("source")
            translation = msg.find("translation")
            if source is not None and (translation is None or not translation.text):
                msgs.append((source.text, None))
    return msgs


if __name__ == "__main__":
    import os
    i18n_path = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "LDDC", "res", "i18n"))
    for lang in os.listdir(i18n_path):
        if lang.endswith(".ts"):
            msgs = get_ts_text(os.path.join(i18n_path, lang))
            print(f"{lang}: {len(msgs)}")
            for i, msg in enumerate(msgs, start=1):
                print(f"[{i}]{msg[0].replace('\n', '\\n')} --> {msg[1]}")
