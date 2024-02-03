import LDDC
import subprocess
import time
import shutil
import os
version = LDDC.__version__.replace('v', '')
year = time.strftime("%Y")
if not year == "2024":
    year = "2024-" + year

subprocess.check_call(
    [
        "python", "-m", "nuitka",
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
        f"--copyright=Copyright (C) {year}  沉默の金",
        "LDDC.py"
    ]
)

if os.path.exists(r".\dist\LDDC.dist.upx"):
    shutil.rmtree(r".\dist\LDDC.dist.upx")
shutil.copytree(r".\dist\LDDC.dist", r".\dist\LDDC.dist.upx")
file_list = []
for foldername, subfolders, filenames in os.walk(r".\dist\LDDC.dist.upx"):
    for filename in filenames:
        file_path = os.path.join(foldername, filename)
        file_list.append(file_path)

for file in file_list:
    if "LDDC.exe" not in file:
        try:
            subprocess.check_call(["upx", "-9", "--lzma", file])
        except Exception as e:
            print(f"Upx failed to compress {file}: {e}")
