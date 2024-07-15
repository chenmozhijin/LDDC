# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金

from backend.lyrics import MultiLyricsData, get_full_timestamps_lyrics_data
from utils.utils import get_divmod_time

from .share import get_lyrics_lines


def ms2srt_timestamp(ms: int) -> str:
    h, m, s, ms = get_divmod_time(ms)

    return f"{int(h):02d}:{int(m):02d}:{int(s):02d},{int(ms):03d}"


def srt_converter(lyrics_dict: MultiLyricsData,
                  langs_mapping: dict[str, dict[int, int]],
                  lyrics_order: list[str],
                  duration: int | None) -> str:

    srt_text = ""
    lyrics_orig = get_full_timestamps_lyrics_data(lyrics_dict["orig"], end_time=duration * 1000 if duration is not None else None, only_line=True)

    for orig_i, orig_line in enumerate(lyrics_orig):
        orig_start, orig_end = orig_line[0], orig_line[1]
        if orig_start is None or orig_end is None:
            continue
        srt_text += f"{orig_i + 1}\n{ms2srt_timestamp(orig_start)} --> {ms2srt_timestamp(orig_end)}\n"

        for lyrics_line in get_lyrics_lines(lyrics_dict, lyrics_order, orig_i, orig_line, langs_mapping):
            srt_text += "".join([word[2] for word in lyrics_line[2] if word[2] != ""]) + "\n"

        srt_text += "\n"

    return srt_text
