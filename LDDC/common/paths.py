# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import os
import platform
import sys
from pathlib import Path

from .args import running_lddc
from .version import __version__

__all__ = ["auto_save_dir", "cache_dir", "config_dir", "data_dir", "default_save_lyrics_dir", "log_dir"]
csidl = {
    "desktop": 0,
    "documents": 5,
    "roaming_appdata": 26,
    "local_appdata": 28,
}


def get_win_path(csidl: int) -> Path:
    """获取windows系统中的特殊路径(当前路径,非默认)"""
    if platform.system() == "Windows":
        import ctypes.wintypes

        buffer = ctypes.create_unicode_buffer(ctypes.wintypes.MAX_PATH)
        ctypes.windll.shell32.SHGetFolderPathW(None, csidl, None, 0, buffer)
        return Path(buffer.value)
    msg = "get_win_path() is only available on Windows"
    raise OSError(msg)


match platform.system():
    case "Linux":
        home = Path.home()
        if "ANDROID_ARGUMENT" in os.environ or "P4A_BOOTSTRAP" in os.environ:
            # Android
            from android.storage import app_storage_path, primary_external_storage_path  # type: ignore[]

            _primary_ext_storage = primary_external_storage_path()
            _app_storage = app_storage_path()

            config_dir = _app_storage / "config"
            data_dir = _app_storage / "data"
            cache_dir = _app_storage / "cache"
            log_dir = _primary_ext_storage / "LDDC" / "logs"
            default_save_lyrics_dir = _primary_ext_storage / "Documents" / "Lyrics"
        else:
            home = Path.home()

            # XDG Base Directory
            config_dir = home / ".config" / "LDDC"
            data_dir = home / ".local" / "share" / "LDDC"
            cache_dir = home / ".cache" / "LDDC"
            log_dir = data_dir / "logs"
            default_save_lyrics_dir = home / "Documents" / "Lyrics"
        # XDG Base Directory
        config_dir = home / ".config" / "LDDC"
        data_dir = home / ".local" / "share" / "LDDC"
        cache_dir = home / ".cache" / "LDDC"
        log_dir = data_dir / "logs"
        default_save_lyrics_dir = home / "Documents" / "Lyrics"
    case "Darwin":  # macOS
        home = Path.home()

        config_dir = home / "Library" / "Preferences" / "LDDC"
        data_dir = home / "Library" / "Application Support" / "LDDC"
        cache_dir = home / "Library" / "Caches" / "LDDC"
        log_dir = home / "Library" / "Logs" / "LDDC"
        default_save_lyrics_dir = home / "Documents" / "Lyrics"
    case "Windows":
        config_dir = get_win_path(csidl["roaming_appdata"]) / "LDDC"
        data_dir = get_win_path(csidl["local_appdata"]) / "LDDC"
        cache_dir = data_dir / "Cache"
        log_dir = data_dir / "Logs"
        default_save_lyrics_dir = get_win_path(csidl["documents"]) / "Lyrics"
    case _:
        msg = f"Unsupported platform: {platform.system()}"
        raise OSError(msg)


auto_save_dir = data_dir / "auto_save"


def create_directories(dirs: list[Path]) -> None:
    for directory in dirs:
        directory.mkdir(parents=True, exist_ok=True)


create_directories([config_dir, data_dir, cache_dir, log_dir, auto_save_dir])

if running_lddc:
    info_path = data_dir / "info.json"
    if "__compiled__" in globals() or hasattr(sys, "_MEIPASS"):
        command_line = sys.argv[0]
    else:
        command_line = f'"{sys.executable}" "{Path(__import__("__main__").__file__).resolve()}"'
else:
    command_line = None


def __update_info() -> None:
    """更新info.json文件"""
    info = {
        "version": __version__,
        "Command Line": command_line,
    }
    with info_path.open("w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False)


if running_lddc:
    __update_info()
