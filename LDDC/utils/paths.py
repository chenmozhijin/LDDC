# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import os
import platform
import sys

from .args import running_lddc
from .version import __version__

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
        log_dir = os.path.join(data_dir, "Logs")
        default_save_lyrics_dir = os.path.join(get_win_path(csidl["documents"]), "Lyrics")
    case _:
        msg = f"Unsupported platform: {platform.system()}"
        raise OSError(msg)


auto_save_dir = os.path.join(data_dir, "auto_save")


def create_directories(dirs: list[str]) -> None:
    for directory in dirs:
        if not os.path.exists(directory):
            os.makedirs(directory)


create_directories([config_dir, data_dir, cache_dir, log_dir, auto_save_dir])

if running_lddc:
    info_path = os.path.join(data_dir, "info.json")
    if "__compiled__" in globals() or hasattr(sys, '_MEIPASS'):
        command_line = sys.argv[0]
    else:
        command_line = f'"{sys.executable}" "{os.path.abspath(__import__("__main__").__file__)}"'
else:
    command_line = None


def __update_info() -> None:
    """更新info.json文件"""
    info = {
        "version": __version__,
        "Command Line": command_line,
    }
    with open(info_path, "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False)


if running_lddc:
    __update_info()
