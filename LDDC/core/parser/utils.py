# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from LDDC.common.models import FSLyricsData, LyricsData, LyricsLine, LyricsType, LyricsWord


def judge_lyrics_type(lyrics: LyricsData | FSLyricsData) -> LyricsType:
    lyrics_type = LyricsType.PlainText
    for line in lyrics:
        if len(line[2]) > 1:
            lyrics_type = LyricsType.VERBATIM
            break

        if line[0] is not None:
            lyrics_type = LyricsType.LINEBYLINE

    return lyrics_type


def plaintext2data(plaintext: str) -> LyricsData:
    lrc_list = LyricsData([])
    for line in plaintext.splitlines():
        lrc_list.append(LyricsLine(None, None, [LyricsWord(None, None, line)]))
    return lrc_list
