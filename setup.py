import argparse
import subprocess
import time

import LDDC

parser = argparse.ArgumentParser()
parser.add_argument('--task', choices=['build', 'get_version', 'get_year'], required=True)
arg = parser.parse_args()
version = LDDC.__version__.replace('v', '')
year = time.strftime("%Y")
if year != '2024':
    year = "2024-" + year

match arg.task:
    case 'build':
        subprocess.check_call(
            [
                "python", "-m", "nuitka",
                "--windows-icon-from-ico=resource\\img\\icon\\logo.png",
                "--standalone",
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
                f"--copyright=Copyright (C) {year} 沉默の金",
                "LDDC.py",
            ],
        )
    case 'get_version':
        print(version)
    case 'get_year':
        print(year)
