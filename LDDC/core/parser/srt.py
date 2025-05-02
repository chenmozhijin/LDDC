# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import re
from collections.abc import Generator
from re import Pattern

from LDDC.common.logger import logger
from LDDC.common.models import (
    LyricsData,
    LyricsLine,
    LyricsWord,
    MultiLyricsData,
)

# 匹配字幕块之间的分隔符(一个或多个空行, 兼容 \n 和 \r\n)
BLOCK_SEPARATOR: Pattern[str] = re.compile(r"\r?\n\r?\n+")
# 匹配时间戳行,例如:00:00:20,000 --> 00:00:24,400
TIMESTAMP_LINE: Pattern[str] = re.compile(
    r"(\d{2}:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{3})",
)


def _parse_time(time_str: str) -> int:
    """解析 HH:MM:SS,ms 或 HH:MM:SS.ms 格式的时间戳为毫秒"""
    # 兼容逗号和点作为毫秒分隔符
    time_str = time_str.replace(",", ".")
    parts = time_str.split(":")
    seconds_ms = parts[2].split(".")

    hours = int(parts[0])
    minutes = int(parts[1])
    seconds = int(seconds_ms[0])
    milliseconds = int(seconds_ms[1]) if len(seconds_ms) > 1 else 0

    return (int(hours) * 3600 + int(minutes) * 60 + int(seconds)) * 1000 + int(milliseconds)


def parse_srt(srt_content: str) -> Generator[tuple[int, int, list[str]], None, None]:
    """解析SRT文件内容为对话行列表"""
    # 按空行分割成块, 移除首尾可能存在的空块
    blocks = BLOCK_SEPARATOR.split(srt_content.strip())

    for block in blocks:
        lines = block.strip().splitlines()  # 分割成行并移除块内首尾空白

        if len(lines) >= 3:  # 至少需要索引、时间、内容三行
            try:
                # 1. 解析索引
                # index = int(lines[0])

                # 2. 解析时间戳
                time_match = TIMESTAMP_LINE.match(lines[1])
                if not time_match:
                    logger.warning(f"跳过时间格式不正确的块: {lines[1]}")
                    continue  # 跳过时间格式不正确的块

                start_time_str, end_time_str = time_match.groups()
                start_time = _parse_time(start_time_str)
                end_time = _parse_time(end_time_str)

                yield start_time, end_time, lines[2:]  # 返回开始时间、结束时间和内容行列表

            except Exception:
                logger.exception("解析SRT文件时出错:")
                continue


def srt2mdata(srt_content: str) -> tuple[dict[str, str], MultiLyricsData]:
    """解析SRT文件内容为MultiLyricsData

    Args:
        srt_content: srt文件内容

    Returns:
        dict[str, str]: 标签字典(为空)
        MultiLyricsData: MultiLyricsData对象

    """
    lyrics_mdata = MultiLyricsData(
        {k: LyricsData([]) for k in ["orig", "roma", "ts"]},
    )
    for start_time, end_time, contents in parse_srt(srt_content):
        if len(contents) == 1:
            lyrics_mdata["orig"].append(LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, contents[0])]))
        elif len(contents) == 2:
            lyrics_mdata["orig"].append(LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, contents[0])]))
            lyrics_mdata["ts"].append(LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, contents[1])]))
        elif len(contents) == 3:
            lyrics_mdata["roma"].append(LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, contents[0])]))
            lyrics_mdata["orig"].append(LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, contents[1])]))
            lyrics_mdata["ts"].append(LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, contents[2])]))
        else:
            lyrics_mdata["orig"].append(LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, "".join(contents))]))

    return {}, MultiLyricsData({k: v for k, v in lyrics_mdata.items() if v})


def srt2data(srt_content: str) -> tuple[dict[str, str], LyricsData]:
    """解析SRT文件内容为LyricsData"""
    lyrics_data = LyricsData(
        [
            LyricsLine(start_time, end_time, [LyricsWord(start_time, end_time, content)])
            for start_time, end_time, contents in parse_srt(srt_content)
            for content in contents
        ],
    )
    return {}, lyrics_data
