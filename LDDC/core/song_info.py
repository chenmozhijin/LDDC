# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re
import struct
from collections.abc import Callable
from pathlib import Path
from typing import Literal, overload

from mutagen import File, FileType, MutagenError  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
from mutagen.apev2 import APEv2
from mutagen.asf import ASFTags
from mutagen.flac import VCommentDict  # type: ignore[reportPrivateImportUsage]
from mutagen.id3 import ID3, SYLT, USLT  # type: ignore[reportPrivateImportUsage]
from mutagen.mp4 import MP4Tags
from PySide6.QtCore import QMimeData

from LDDC.common.data.config import cfg
from LDDC.common.exceptions import DropError, FileTypeError, GetSongInfoError
from LDDC.common.logger import logger
from LDDC.common.models import Artist, Lyrics, SongInfo, Source
from LDDC.core.parser.cue import parse_cue

audio_formats = [
    "3g2",
    "aac",
    "aif",
    "ape",
    "apev2",
    "dff",
    "dsf",
    "flac",
    "m4a",
    "m4b",
    "mid",
    "mp3",
    "mp4",
    "mpc",
    "ofr",
    "ofs",
    "ogg",
    "oggflac",
    "oggtheora",
    "opus",
    "spx",
    "tak",
    "tta",
    "wav",
    "wma",
    "wv",
]


def get_audio_file_infos(file_path: Path) -> list[SongInfo]:
    if not file_path.is_file():
        logger.error("未找到文件: %s", file_path)
        msg = f"未找到文件: {file_path}"
        raise GetSongInfoError(msg)
    try:
        if file_path.suffix.lower().removeprefix(".") in audio_formats:
            audio = File(file_path, easy=True)  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
            if isinstance(audio, FileType) and audio.info:
                if "cuesheet" in audio:
                    return parse_cue(file_path.parent, audio["cuesheet"][0]).to_songinfos()

                if "title" in audio and "�" not in str(audio["title"][0]):
                    title = str(audio["title"][0])
                elif "TIT2" in audio and "�" not in str(audio["TIT2"][0]):
                    title = str(audio["TIT2"][0])
                else:
                    title = None

                if "artist" in audio and "�" not in str(audio["artist"][0]):
                    artist = str(audio["artist"][0])
                elif "TPE1" in audio and "�" not in str(audio["TPE1"][0]):
                    artist = str(audio["TPE1"][0])
                else:
                    artist = []

                if "album" in audio and "�" not in str(audio["album"][0]):
                    album = str(audio["album"][0])
                elif "TALB" in audio and "�" not in str(audio["TALB"][0]):
                    album = str(audio["TALB"][0])
                else:
                    album = None

                metadata = SongInfo(
                    source=Source.Local,
                    title=title,
                    artist=Artist(artist),
                    album=album,
                    duration=int(audio.info.length) * 1000 if audio.info.length * 1000 else None,
                    path=file_path,
                )
            else:
                msg = f"{file_path} 无法获取歌曲信息"
                raise GetSongInfoError(msg)
        else:
            msg = f"{file_path} 文件格式不支持"
            raise GetSongInfoError(msg)

    except MutagenError as e:  # type: ignore[reportPrivateImportUsage] mutagen中的MutagenError被误定义为私有 quodlibet/mutagen#647
        logger.exception("%s获取文件信息失败", file_path)
        msg = f"获取文件信息失败:{e.__class__.__name__}: {e!s}"
        raise GetSongInfoError(msg) from e
    else:
        return [metadata]


def has_lyrics(file_path: Path | str) -> bool:
    """检查音频文件是否包含歌词标签。

    Args:
        file_path: 音频文件的路径 (字符串或 Path 对象)。

    Returns:
        如果找到任何形式的歌词标签 (USLT, SYLT, 'LYRICS', '©lyr', 'WM/Lyrics', 'Lyrics')
        且内容不为空，则返回 True，否则返回 False。
        如果文件无法加载、不支持或发生错误，也返回 False。

    """
    try:
        audio = File(file_path, easy=False)

        if audio is None:
            logger.warning("无法加载文件或文件格式无法识别: %s", file_path)
            return False

        if audio.tags is None:
            logger.debug("文件 %s 没有找到标签", file_path)
            return False

        # 1. ID3 标签 (MP3)
        if isinstance(audio.tags, ID3):
            # 检查 USLT (非同步歌词) 或 SYLT (同步歌词) 标签是否存在
            # getall 返回一个列表，如果列表非空，则表示标签存在
            has_uslt = any(uslt.text for uslt in audio.tags.getall("USLT"))
            has_sylt = any(sylt.text for sylt in audio.tags.getall("SYLT"))  # SYLT 的 text 是元组列表，非空即视为有内容
            if has_uslt or has_sylt:
                logger.debug("在 %s 中找到 ID3 歌词 (USLT/SYLT)", file_path)
                return True

        # 2. Vorbis Comment (FLAC, OGG, Opus) 或 APEv2 (APE)
        elif isinstance(audio.tags, (VCommentDict, APEv2)):
            # 检查 'LYRICS' 键是否存在且其值（通常是列表）非空且第一个元素非空字符串
            lyrics_val = audio.tags.get("LYRICS")
            # Vorbis/APE 标签值通常是列表，检查列表是否存在且包含非空字符串
            if lyrics_val and isinstance(lyrics_val, list) and any(s and s.strip() for s in lyrics_val):
                logger.debug("在 %s 中找到 Vorbis/APE 歌词 ('LYRICS')", file_path)
                return True
            # 处理 VCommentDict 可能返回单个字符串的情况 (虽然通常是列表)
            if lyrics_val and isinstance(lyrics_val, str) and lyrics_val.strip():
                logger.debug("在 %s 中找到 Vorbis/APE 歌词 ('LYRICS')", file_path)
                return True

        # 3. MP4 标签 (MP4, M4A)
        elif isinstance(audio.tags, MP4Tags):
            # 检查 '©lyr' 键是否存在，其值通常是包含一个字符串的列表
            lyrics_list = audio.tags.get("©lyr")
            if lyrics_list and isinstance(lyrics_list, list) and len(lyrics_list) > 0 and lyrics_list[0] and lyrics_list[0].strip():
                logger.debug("在 %s 中找到 MP4 歌词 ('©lyr')", file_path)
                return True

        # 4. ASF 标签 (WMA)
        elif isinstance(audio.tags, ASFTags):
            # 检查 'WM/LYRICS' 或其别名 'Lyrics' 是否存在且包含非空内容
            lyrics_present = False
            wm_lyrics = audio.tags.get("WM/LYRICS")
            if wm_lyrics and any(str(val.value).strip() for val in wm_lyrics if hasattr(val, "value")):
                lyrics_present = True

            if not lyrics_present:
                alias_lyrics = audio.tags.get("Lyrics")
                if alias_lyrics and any(str(val.value).strip() for val in alias_lyrics if hasattr(val, "value")):
                    lyrics_present = True

            if lyrics_present:
                logger.debug("在 %s 中找到 ASF 歌词 ('WM/LYRICS' 或 'Lyrics')", file_path)
                return True
        else:
            # 如果检查了所有类型但没有找到歌词
            logger.debug("在 %s 中未找到已知格式的歌词标签", file_path)
            return False

    except FileNotFoundError:
        logger.error("文件未找到: %s", file_path)
        return False
    except MutagenError as e:
        logger.error("处理 %s 时发生 Mutagen 错误: %s", file_path, e)
        return False
    except Exception as e:
        logger.error("处理 %s 时发生意外错误: %s", file_path, e)
        return False
    return False


def write_lyrics(file_path: Path | str, lyrics_text: str, lyrics: Lyrics | None = None) -> None:
    audio = File(file_path)

    if isinstance(audio, FileType):
        if audio.tags is None:
            audio.add_tags()

        # 判断标签类型并写入歌词
        if isinstance(audio.tags, ID3):
            # MP3 文件使用 ID3 标签

            # https://id3.org/id3v2.3.0#Unsychronised_lyrics.2Ftext_transcription
            audio.tags.add(USLT(text=lyrics_text))
            if lyrics and (orig := lyrics.get_fslyrics().get("orig")):
                # https://id3.org/id3v2.3.0#Synchronised_lyrics.2Ftext
                sylt: list[tuple[str, int]] = []
                for i, line in enumerate(orig):
                    for j, (start, _end, word) in enumerate(line[2]):
                        if i != 0 and j == 0:
                            word = f"\n{word}"  # noqa: PLW2901
                        sylt.append((word, start))

                audio.tags.add(SYLT(format=2, type=1, text=sylt))
        elif isinstance(audio.tags, VCommentDict | APEv2):
            # FLAC, OGG, Opus 等使用 VorbisComment, APE 文件使用 APEv2 标签
            audio["LYRICS"] = lyrics_text
        elif isinstance(audio.tags, MP4Tags):
            # MP4, M4A, M4B 文件使用 MP4 标签
            audio["©lyr"] = lyrics_text
        elif isinstance(audio.tags, ASFTags):
            # WMA 文件使用 ASF 标签
            # https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/wm-lyrics-attribute
            audio["WM/LYRICS"] = lyrics_text
            audio["Lyrics"] = lyrics_text  # Lyrics is an alias for WM/Lyrics attribute.
        else:
            msg = f"{file_path} 不支持的文件格式"
            raise FileTypeError(msg)

        # 保存修改
        if isinstance(audio.tags, ID3):
            audio.save(v2_version=3 if cfg["ID3_version"] == "v2.3" else 4)
        else:
            audio.save()
        logger.info("写入歌词到%s成功", file_path)
    else:
        msg = f"{file_path} 不支持的文件格式 {type(audio)}"
        raise FileTypeError(msg)


def get_audio_duration(file_path: str) -> int | None:
    """获取音频文件时长(毫秒)"""
    try:
        if duration := File(file_path).info.length:  # type: ignore[]
            return int(duration * 1000)  # 转换为毫秒
    except Exception as e:
        logger.error(f"获取音频时长失败: {file_path} - {e!s}")
        return None


def cue_time_to_ms(time_str: str) -> int:
    """将CUE时间格式转换为毫秒"""
    parts = list(map(int, time_str.split(":")))
    while len(parts) < 3:
        parts.append(0)
    minutes, seconds, frames = parts
    return (minutes * 60 + seconds) * 1000 + int(frames * (1000 / 75))


@overload
def parse_drop_infos(
    mime: QMimeData,
    first: Literal[True] = True,
    progress: Callable[[str, int, int], None] | None = None,
    running: Callable[[], bool] | None = None,
) -> SongInfo: ...


@overload
def parse_drop_infos(
    mime: QMimeData,
    first: Literal[False] = False,
    progress: Callable[[str, int, int], None] | None = None,
    running: Callable[[], bool] | None = None,
) -> list[SongInfo]: ...


def parse_drop_infos(
    mime: QMimeData,
    first: bool = True,
    progress: Callable[[str, int, int], None] | None = None,
    running: Callable[[], bool] | None = None,
) -> list[SongInfo] | SongInfo:
    """解析拖拽的文件

    :param mime: 拖拽的文件信息
    :param first: 是否只获取第一个文件
    :param progress: 进度回调函数
    :param running: 是否正在运行
    :return: 解析后的文件信息
    """
    paths: list[Path] = []
    tracks = []
    indexs = []
    # 特殊适配
    if 'application/x-qt-windows-mime;value="ACL.FileURIs"' in mime.formats():
        # AIMP
        data = mime.data('application/x-qt-windows-mime;value="ACL.FileURIs"')
        urls = bytearray(data.data()[20:-4]).decode("UTF-16").split("\x00")
        for path in urls:
            if path.split(":")[-1].isdigit():
                indexs.append(path.split(":")[-1])
                paths.append(Path(":".join(path.split(":")[:-1])))
    elif 'application/x-qt-windows-mime;value="foobar2000_playable_location_format"' in mime.formats():
        # foobar2000
        i = 0
        paths_data = bytes(mime.data('application/x-qt-windows-mime;value="foobar2000_playable_location_format"').data())
        paths = []
        while i < len(paths_data) - 4:
            # 提取前4个字节的整数,不知道表示什么,跳过
            # index = struct.unpack_from('<I', paths_data, i)[0]
            i += 4
            # 提取下一个4字节,表示后续路径的长度
            length = struct.unpack_from("<I", paths_data, i)[0]
            i += 4
            # 提取指定长度的文件路径,解码为UTF-8
            path = paths_data[i : i + length].decode("UTF-8")
            i += length
            path = path.removeprefix("file://")
            paths.append(Path(path))

        for song in mime.text().splitlines():
            if (matched := re.fullmatch(r"(?:(?P<artist>.*?) - )?\[(?P<album>.*?) (?:CD\d+/\d+ )?#(?P<track>\d+)\] (?P<title>.*)", song)) is not None:
                tracks.append(matched.group("track"))
            else:
                tracks.append(None)

    if not paths:
        try:
            paths = [Path(url.toLocalFile()) for url in mime.urls()]
        except Exception as e:
            logger.exception(e)
            msg = "无法获取文件路径"
            logger.error(msg)
            raise DropError(msg) from e

    songs: list[SongInfo] = []
    if first:
        if len(paths) >= 1:
            paths = paths[:1]
        else:
            msg = "没有获取到任何文件信息"
            raise DropError(msg)
    paths_count = len(paths)
    for i, path in enumerate(paths):
        if running is not None and running() is False:
            break
        track, index = None, None
        if tracks and len(tracks) > i:
            track = tracks[i]
        elif indexs and len(indexs) > i:
            index = indexs[i]
        logger.info(f"解析文件 {path}, track={track}, index={index}")
        if progress is not None:
            msg = f"正在解析文件 {path}"
            progress(msg, i + 1, paths_count)

        if path.suffix == ".cue" and (isinstance(track, str | int) or index is not None):
            try:
                infos = parse_cue(path).to_songinfos()
            except Exception as e:
                msg = f"解析文件 {path} 失败: {e}"
                logger.exception(e)
                raise DropError(msg) from e
            if index is not None:
                if int(index) + 1 >= len(infos):
                    msg = f"文件 {path} 中没有找到第 {index} 轨歌曲"
                    logger.error(msg)
                    raise DropError(msg)
                song = infos[int(index)]
            elif isinstance(track, str | int):
                for song in infos:
                    if song.id is not None and int(song.id) == int(track):
                        break
                else:
                    msg = f"文件 {path} 中没有找到第 {track} 轨歌曲"
                    logger.error(msg)
                    raise DropError(msg)
        else:
            try:
                infos = get_audio_file_infos(path)
            except Exception as e:
                logger.exception(e)
                msg = f"解析文件 {path} 失败: {e}"
                logger.error(msg)
                raise DropError(msg) from e
            if len(infos) == 1:
                song = infos[0]
            elif isinstance(track, str | int):
                for song in infos:
                    if song.id is not None and int(song.id) == int(track):
                        break
                else:
                    msg = f"文件 {path} 中没有找到第 {track} 轨歌曲"
                    logger.error(msg)
                    raise DropError(msg)
            else:
                msg = f"文件 {path} 中包含多个歌曲"
                logger.error(msg)
                raise DropError(msg)

        if not isinstance(song, SongInfo):
            msg = "获取歌词信息时出现未知错误"
            logger.error(msg)
            raise DropError(msg)
        songs.append(song)

    if first:
        return songs[0]
    return songs
