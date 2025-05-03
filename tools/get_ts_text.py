# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from pathlib import Path
from xml.etree import ElementTree as ET


def get_ts_text(ts_file: Path) -> list[tuple[str, str | None]]:
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
    i18n_path = Path(__file__).parent.parent / "LDDC" / "res" / "i18n"
    for lang in i18n_path.iterdir():
        if lang.suffix == ".ts":
            msgs = get_ts_text(lang)
            print(f"{lang.name}: {len(msgs)}")
            for i, msg in enumerate(msgs, start=1):
                modified_source = msg[0].replace('\n', '\\n')
                print(f"[{i}]{modified_source} --> {msg[1]}")
