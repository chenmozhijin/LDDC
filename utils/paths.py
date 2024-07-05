# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import os
import platform
import re
import sys

from utils.utils import compare_version_numbers

main = __import__("__main__")
main_path = os.path.dirname(os.path.abspath(main.__file__))

match platform.system():
    case 'Linux':
        home = os.path.expanduser("~")
        config_dir = os.path.join(home, ".config", "LDDC")
        data_dir = os.path.join(home, ".local", "share", "LDDC")
        cache_dir = os.path.join(home, ".cache", "LDDC")
        default_save_lyrics_dir = os.path.join(home, "Documents", "LDDC", "Lyrics")
    case 'Darwin':  # macOS
        home = os.path.expanduser("~")
        config_dir = os.path.join(home, "Library", "Preferences", "LDDC")
        data_dir = os.path.join(home, "Library", "Application Support", "LDDC")
        cache_dir = os.path.join(home, "Library", "Caches", "LDDC")
        default_save_lyrics_dir = os.path.join(home, "Documents", "LDDC", "Lyrics")
    case 'Windows':
        appdata = os.getenv('APPDATA')
        localappdata = os.getenv('LOCALAPPDATA')
        documents = os.path.join(os.path.expanduser("~"), "Documents")
        config_dir = os.path.join(appdata, "LDDC") if appdata else os.path.join(os.path.expanduser("~"), "AppData", "Roaming", "LDDC")
        data_dir = os.path.join(localappdata, "LDDC") if localappdata else os.path.join(os.path.expanduser("~"), "AppData", "Local", "LDDC")
        cache_dir = os.path.join(localappdata, "LDDC", "Cache") if localappdata else os.path.join(os.path.expanduser("~"), "AppData", "Local", "LDDC", "Cache")
        default_save_lyrics_dir = os.path.join(documents, "LDDC", "Lyrics")
    case _:
        msg = f"Unsupported platform: {platform.system()}"
        raise NotImplementedError(msg)


def create_directories(dirs: list[str]) -> None:
    for directory in dirs:
        if not os.path.exists(directory):
            os.makedirs(directory)


create_directories([config_dir, data_dir, cache_dir])
info_path = os.path.join(data_dir, "info.json")
self_path = sys.argv[0]
command_line = self_path if self_path.endswith(".exe") else f'{sys.executable} "{self_path}"'


def __update_info() -> None:
    if os.path.exists(info_path):
        with open(info_path, encoding="utf-8") as f:
            info = json.load(f)

        if (isinstance(info, dict) and
            "version" in info and
            "Command Line" in info and
                isinstance(info["version"], str)):

            command_line = info.get("Command Line")
            if '"' in command_line:
                old_path = re.sub(r'[^ ]* "([^"]*?)"', r'\1', command_line)
                if '"' in old_path:
                    old_path = None
            else:
                old_path = command_line

            try:
                if old_path and os.path.exists(old_path) and not compare_version_numbers(info["version"], main.__version__):
                    return
            except Exception:  # noqa: S110
                pass

    info = {
        "version": main.__version__,
        "Command Line": command_line,
    }
    with open(info_path, "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False)

__update_info()