import LDDC
import subprocess
import time
version = LDDC.__version__.replace('v', '')
year = time.strftime("%Y")
if not year == "2024":
    year = "2024-" + year


subprocess.check_call(
    [
        "python", "-m", "nuitka",
        "--standalone",
        "--follow-imports",
        "--lto=yes",
        "--report=report.xml",
        "--mingw64",
        "--show-progress",
        "--show-memory",
        "--windows-disable-console",
        "--enable-plugin=pyside6",
        "--output-dir=dist",
        "--output-filename=LDDC.exe",
        "--product-name=LDDC",
        "--product-version=" + version,
        f"--copyright=Copyright (C) {year}  沉默の金",
        "LDDC.py"
    ]
)
