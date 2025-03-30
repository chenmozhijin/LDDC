# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from LDDC.common.models import LyricsLine, MultiLyricsData
from LDDC.common.utils import has_content


def get_lyrics_lines(lyrics_dict: MultiLyricsData,
                     langs_order: list[str],
                     orig_i: int,
                     orig_line: LyricsLine,
                     langs_mapping: dict[str, dict[int, int]],
                     last_ref_line_time_sty: int = 0) -> list[tuple[LyricsLine, bool]]:
    """获取歌词同一句歌词所有语言类型的行列表"""
    lyrics_lines = []
    for i, lang in enumerate(langs_order):
        if lang == "orig":
            lyrics_line = orig_line
        else:
            index = langs_mapping[lang].get(orig_i)
            if index is None:
                continue
            lyrics_line = lyrics_dict[lang][index]

        if has_content("".join([word.text for word in lyrics_line.words if word.text != ""])):
            lyrics_lines.append((lyrics_line, bool(last_ref_line_time_sty == 1 and i == len(langs_order) - 1 and len(lyrics_line.words) == 1)))
    return lyrics_lines
