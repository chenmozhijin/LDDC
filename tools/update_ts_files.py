# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import subprocess
from pathlib import Path

lddc_dir = Path(__file__).resolve().parent.parent / "LDDC"
i18n_dir = lddc_dir / "res" / "i18n"

excluded_suffixes = ("_ui.py", "_rc.py")
langs = ["zh-Hant", "en", "ja"]
files2ts: list[Path] = []
for root, _dirs, files in lddc_dir.walk():
    for file in files:
        path = root / file
        if not path.name.endswith(excluded_suffixes) and path.suffix in (".py", ".ui"):
            files2ts.append(path)

cmd = ["pyside6-lupdate", *[str(path) for path in files2ts], "-ts", *(str(i18n_dir / f"LDDC_{lang}.ts") for lang in langs), "-no-obsolete"]
result = subprocess.run(cmd, check=True, text=True)  # noqa: S603
print(result.stdout or result.stderr)
