# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from collections.abc import Callable

from LDDC.common.data.config import cfg
from LDDC.common.models import LyricsFormat, LyricsLine, MultiLyricsData
from LDDC.common.time import ms2formattime, ms2roundedtime
from LDDC.common.version import __version__

from .share import get_lyrics_lines


def formattime_sub1(formattime: str) -> str:
    """将时间戳减1"""
    m, s_ms = formattime.split(":")
    s, ms = s_ms.split(".")
    ms_len = len(ms)
    if ms not in ("00", "000"):
        ms = f"{int(ms) - 1:0{ms_len}d}"
    elif s != "00":
        s = str(int(s) - 1)
    elif m != "00":
        m = str(int(m) - 1)
    return f"{m}:{s}.{ms}"


def lyrics_line2str(
    lyrics_line: LyricsLine,
    lyrics_format: LyricsFormat,
    line_start_time: int | None = None,
    line_end_time: int | None = None,
    ms_converter: Callable[[int], str] = ms2formattime,
) -> str:
    """将歌词行列表转换为LRC歌词字符串

    :param lyrics_line: 歌词行列表
    :param verbatim: 是否逐字模式
    :param Enhanced: 是否为增强格式歌词
    :param start_time: 替换的的行首时间戳
    :param end_time: 附加的行尾时间戳
    :return: LRC歌词字符串
    """
    line_start_time = line_start_time if line_start_time is not None else lyrics_line.start
    line_end_time = line_end_time if lyrics_line.end is None else lyrics_line.end

    text = ""

    # 添加行首时间戳
    if line_start_time is not None:
        text += f"[{ms_converter(line_start_time)}]"

    match lyrics_format:
        case LyricsFormat.LINEBYLINELRC:
            return text + "".join([word.text for word in lyrics_line.words if word.text != ""])
        case LyricsFormat.VERBATIMLRC:
            symbols = ("[", "]")
        case LyricsFormat.ENHANCEDLRC:
            symbols = ("<", ">")

    last_end = lyrics_line.start if lyrics_format == LyricsFormat.VERBATIMLRC else None
    for start, end, word in lyrics_line.words:
        if start is not None and start != last_end:
            text += f"{symbols[0]}{ms_converter(max(start, line_start_time if line_start_time else start))}{symbols[1]}"

        text += word

        if end is not None:
            text += f"{symbols[0]}{ms_converter(end)}{symbols[1]}"
        last_end = end

    if line_end_time is not None and not text.endswith(symbols[1]):
        text += f"{symbols[0]}{ms_converter(line_end_time)}{symbols[1]}"

    return text


def lrc_converter(
    tags: dict[str, str],
    lyrics_dict: MultiLyricsData,
    lyrics_format: LyricsFormat,
    langs_mapping: dict[str, dict[int, int]],
    langs_order: list[str],
) -> str:
    lrc_ms_digit_count: int = cfg["lrc_ms_digit_count"]
    ms_converter = ms2roundedtime if lrc_ms_digit_count == 2 else ms2formattime
    add_end_timestamp_line: bool = cfg["add_end_timestamp_line"]
    last_ref_line_time_sty: int = cfg["last_ref_line_time_sty"]

    # 添加开头的ID标签
    lrc_text = (
        "\n".join(f"[{k}:{v}]" for k, v in tags.items() if k in ("al", "ar", "au", "by", "offset", "ti") and v)
        + f"\n[tool:LDDC {__version__} https://github.com/chenmozhijin/LDDC]\n\n"
        if tags
        else ""
    )

    for orig_i, orig_line in enumerate(lyrics_dict["orig"]):
        # 如果同时有行开始时间与词开始时间则将词开始时间作为行开始时间
        line_start_time = orig_line.words[0].start if orig_line.words and orig_line.words[0].start is not None else orig_line.start
        line_end_time = orig_line.words[-1].end if orig_line.words and orig_line.words[-1].end is not None else orig_line.end

        for lyrics_line, last_sub1 in get_lyrics_lines(lyrics_dict, langs_order, orig_i, orig_line, langs_mapping, last_ref_line_time_sty):
            if not last_sub1:
                lrc_text += lyrics_line2str(lyrics_line, lyrics_format, line_start_time, line_end_time, ms_converter) + "\n"
            else:
                if orig_i + 1 < len(lyrics_dict["orig"]):
                    next_line = lyrics_dict["orig"][orig_i + 1]
                    ts_sub1_start_time = next_line.words[0].start if next_line.words and next_line.words[0].start is not None else next_line.start
                elif line_end_time:
                    ts_sub1_start_time = line_end_time + 10
                elif line_start_time:
                    ts_sub1_start_time = line_start_time + 10
                else:
                    ts_sub1_start_time = None
                ts_sub1_starformattime = f"{formattime_sub1(ms_converter(ts_sub1_start_time))}" if ts_sub1_start_time is not None else ""
                lrc_text += (f"[{ts_sub1_starformattime}]" if ts_sub1_starformattime else "") + "".join(
                    [word.text for word in lyrics_line.words if word.text != ""],
                )
                if ts_sub1_starformattime and lyrics_format == LyricsFormat.VERBATIMLRC:
                    lrc_text += f"[{ts_sub1_starformattime}]"
                elif ts_sub1_starformattime and lyrics_format == LyricsFormat.ENHANCEDLRC:
                    lrc_text += f"<{ts_sub1_starformattime}>"
                lrc_text += "\n"

        if (
            lyrics_format == LyricsFormat.LINEBYLINELRC
            and add_end_timestamp_line
            and line_end_time is not None
            and (orig_i == len(lyrics_dict["orig"]) - 1 or lyrics_dict["orig"][orig_i + 1].start != line_end_time)
        ):
            lrc_text += f"[{ms_converter(line_end_time)}]\n"

    return lrc_text
