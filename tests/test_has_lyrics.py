# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from pathlib import Path

import pytest

from LDDC.core.song_info import has_lyrics, write_lyrics
from tests.helper import create_audio_file, get_tmp_dir


@pytest.mark.parametrize(
    ("audio_format", "extension"),
    [
        ("mp3", "mp3"),  # ID3 标签
        ("flac", "flac"),  # VCommentDict 标签
        ("mp4", "m4a"),  # MP4Tags 标签
        ("wav", "wav"),  # 可能使用 ID3 标签
    ],
)
def test_has_lyrics_detection(audio_format: str, extension: str) -> None:
    """测试不同音频格式的歌词检测功能"""
    # 创建临时目录
    tmp_dir = Path(get_tmp_dir())

    # 1. 创建音频文件（不包含歌词）
    audio_path = tmp_dir / f"test_audio.{extension}"
    create_audio_file(
        path=audio_path,
        audio_format=audio_format,
        duration=5,
        tags={"title": "Test Title", "artist": "Test Artist", "album": "Test Album"},
    )

    # 2. 验证刚创建的文件没有歌词
    assert not has_lyrics(audio_path), f"新创建的 {extension} 文件不应该有歌词"

    # 3. 写入歌词到文件
    test_lyrics = "[00:00.00]This is a test lyric\n[00:01.00]Second line"
    write_lyrics(audio_path, test_lyrics)

    # 4. 验证 has_lyrics 能正确检测到歌词
    assert has_lyrics(audio_path), f"{extension} 文件写入歌词后 has_lyrics 应该返回 True"
