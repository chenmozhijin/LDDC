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


csidl = {
    "desktop": 0,
    "documents": 5,
    "roaming_appdata": 26,
    "local_appdata": 28,
}


def get_win_path(csidl: int) -> str:
    """获取windows系统中的特殊路径(当前路径,非默认)"""
    if platform.system() == "Windows":
        import ctypes.wintypes

        buffer = ctypes.create_unicode_buffer(ctypes.wintypes.MAX_PATH)
        ctypes.windll.shell32.SHGetFolderPathW(None, csidl, None, 0, buffer)
        return buffer.value
    msg = "get_win_path() is only available on Windows"
    raise OSError(msg)


match platform.system():
    case 'Linux':
        home = os.path.expanduser("~")

        # XDG Base Directory
        config_dir = os.path.join(home, ".config", "LDDC")
        data_dir = os.path.join(home, ".local", "share", "LDDC")
        cache_dir = os.path.join(home, ".cache", "LDDC")
        log_dir = os.path.join(data_dir, "logs")
        default_save_lyrics_dir = os.path.join(home, "Documents", "Lyrics")
    case 'Darwin':  # macOS
        home = os.path.expanduser("~")

        config_dir = os.path.join(home, "Library", "Preferences", "LDDC")
        data_dir = os.path.join(home, "Library", "Application Support", "LDDC")
        cache_dir = os.path.join(home, "Library", "Caches", "LDDC")
        log_dir = os.path.join(home, "Library", "Logs", "LDDC")
        default_save_lyrics_dir = os.path.join(home, "Documents", "Lyrics")
    case 'Windows':
        config_dir = os.path.join(get_win_path(csidl["roaming_appdata"]), "LDDC")
        data_dir = os.path.join(get_win_path(csidl["local_appdata"]), "LDDC")
        cache_dir = os.path.join(data_dir, "Cache")
        log_dir = os.path.join(data_dir, "Logs") if not __debug__ else os.path.join(main_path, "Logs")
        default_save_lyrics_dir = os.path.join(get_win_path(csidl["documents"]), "Lyrics")
    case _:
        msg = f"Unsupported platform: {platform.system()}"
        raise OSError(msg)


def create_directories(dirs: list[str]) -> None:
    for directory in dirs:
        if not os.path.exists(directory):
            os.makedirs(directory)


create_directories([config_dir, data_dir, cache_dir, log_dir])
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
            if isinstance(command_line, str) and '"' in command_line:
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
