# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import re

from backend.lyrics import LyricsData, MultiLyricsData


def get_lyrics_lines(lyrics_dict: MultiLyricsData,
                     lyrics_order: list[str],
                     orig_i: int,
                     orig_line: LyricsData,
                     langs_mapping: dict[str, dict[int, int]]) -> list[LyricsData]:
    """获取歌词同一句歌词所有语言类型的行列表"""
    lyrics_lines = []
    for lang in lyrics_order:
        if lang == "orig":
            lyrics_line = orig_line
        else:
            index = langs_mapping[lang].get(orig_i)
            if index is None:
                continue
            lyrics_line = lyrics_dict[lang][index]

        if len(lyrics_line[2]) == 1:
            word = lyrics_line[2][0][2]
            if word in ("", "//") or len(word) == 2 and word[0].isupper() and word[1] == "：":
                continue
        lyrics_lines.append(lyrics_line)
    return lyrics_lines


def has_content(line: str) -> bool:
    """检查是否有实际内容"""
    content = re.sub(r"\[\d+:\d+\.\d+\]|\[\d+,\d+\]|<\d+:\d+\.\d+>", "", line).strip()
    if content in ("", "//"):
        return False
    return not (len(content) == 2 and content[0].isupper() and content[1] == "：")  # 歌手标签行


def get_clear_lyric(lyric: str) -> str:
    # 为保证find_closest_match的准确性不可直接用于原歌词
    start_double_timestamp_pattern = re.compile(r"^(\[\d+:\d+\.\d+\])\[\d+:\d+\.\d+\]")  # 行首双重时间戳匹配表达式
    end_double_timestamp_pattern = re.compile(r"(\[\d+:\d+\.\d+\])\[\d+:\d+\.\d+\]")  # 行尾双重时间戳匹配表达式
    result = []
    for line in lyric.splitlines():
        line1 = start_double_timestamp_pattern.sub(r"\1", line)
        line1 = end_double_timestamp_pattern.sub(r"\1", line1)
        if has_content(line1):
            result.append(line1)
    return "\n".join(result)
