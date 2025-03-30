# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import contextlib
import locale
import re
import sys
from collections import OrderedDict
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from charset_normalizer import from_bytes, from_path

from LDDC.common.exceptions import DecodingError
from LDDC.common.models import SongInfo

from .path_processor import get_save_path


def read_unknown_encoding_file(file_path: Path | None = None, file_data: bytes | None = None, sign_word: Iterable[str] | None = None) -> str:
    """读取未知编码的文件"""
    if sys.version_info >= (3, 11):
        sys_encoding = [locale.getencoding()]
    else:
        sys_encoding = [locale.getpreferredencoding(False)]
    if sys_encoding[0] in ("chinese", "csiso58gb231280", "euc-cn", "euccn", "eucgb2312-cn", "gb2312-1980", "gb2312-80", "iso-ir-58", "936", "cp936", "ms936"):
        sys_encoding = [
            "gb18030",
            "chinese",
            "csiso58gb231280",
            "euc-cn",
            "euccn",
            "eucgb2312-cn",
            "gb2312-1980",
            "gb2312-80",
            "iso-ir-58",
            "936",
            "cp936",
            "ms936",
        ]
    file_content = None

    if not file_data:
        if not file_path:
            msg = "文件路径和文件数据不能同时为空"
            raise ValueError(msg)
        with file_path.open("rb") as f:
            file_data = f.read()
    with contextlib.suppress(Exception):
        file_content = file_data.decode(sys_encoding[0])

        if (sys_encoding[0] == "gb18030" and "锘縍EM" in file_content) or "�" not in file_data.decode("utf-8", errors="replace"):
            file_content = None
        if sign_word is not None and file_content is not None:
            for sign in sign_word:
                if sign not in file_content:
                    file_content = None
                    break

    if file_content is None:
        if file_data is not None:
            results = from_bytes(file_data)
        elif file_path is not None:
            results = from_path(file_path)
        else:
            msg = "文件路径和文件数据不能同时为空"
            raise ValueError(msg)

        filtered_results = []
        if sign_word is not None:
            for result in results:
                for sign in sign_word:
                    if sign not in str(result):
                        break
                else:
                    filtered_results.append(result)
        else:
            filtered_results = results

        for result in filtered_results:
            if result.encoding in sys_encoding:
                file_content = str(result)
                break
        else:
            if filtered_results:
                file_content = str(filtered_results[0])

    if file_content is None:
        msg = "无法解码文件"
        raise DecodingError(msg)

    return file_content

class LimitedSizeDict(OrderedDict):
    def __init__(self, max_size: int, *args: Any, **kwargs: Any) -> None:
        self.max_size = max_size
        super().__init__(*args, **kwargs)

    def __setitem__(self, key: Any, value: Any) -> None:
        if len(self) >= self.max_size:
            self.popitem(last=False)  # 删除最早插入的项目
        super().__setitem__(key, value)


def has_content(line: str) -> bool:
    """检查是否有实际内容"""
    content = re.sub(r"\[\d+:\d+\.\d+\]|\[\d+,\d+\]|<\d+:\d+\.\d+>", "", line).strip()
    if content in ("", "//"):
        return False
    return not (len(content) == 2 and content[0].isupper() and content[1] == "：")  # 歌手标签行


def save2fomat_path(text: str, folder: Path, file_name_format: str, info: SongInfo, lyric_langs: list) -> Path:
    folder, file_name = get_save_path(folder, file_name_format, info, lyric_langs)
    folder.mkdir(parents=True, exist_ok=True)
    save_path = folder / file_name
    with save_path.open("w", encoding="utf-8") as f:
        f.write(text)
    return save_path
