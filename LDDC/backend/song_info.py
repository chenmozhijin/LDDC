# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os
import re
import struct
from typing import Literal, overload

from mutagen import File, FileType, MutagenError  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
from mutagen.apev2 import APEv2
from mutagen.asf import ASFTags
from mutagen.flac import VCommentDict  # type: ignore[reportPrivateImportUsage]
from mutagen.id3 import ID3, SYLT, USLT  # type: ignore[reportPrivateImportUsage]
from mutagen.mp4 import MP4Tags
from PySide6.QtCore import QMimeData

from LDDC.utils.data import cfg
from LDDC.utils.error import DropError, FileTypeError, GetSongInfoError
from LDDC.utils.logger import logger
from LDDC.utils.utils import read_unknown_encoding_file, time2ms

from .lyrics import Lyrics

audio_formats = ['3g2', 'aac', 'aif', 'ape', 'apev2', 'dff',
                 'dsf', 'flac', 'm4a', 'm4b', 'mid', 'mp3',
                 'mp4', 'mpc', 'ofr', 'ofs', 'ogg', 'oggflac',
                 'oggtheora', 'opus', 'spx', 'tak', 'tta',
                 'wav', 'wma', 'wv']


def get_audio_file_infos(file_path: str) -> list[dict]:
    if not os.path.isfile(file_path):
        logger.error("未找到文件: %s", file_path)
        msg = f"未找到文件: {file_path}"
        raise GetSongInfoError(msg)
    try:
        if file_path.lower().split('.')[-1] in audio_formats:
            audio = File(file_path, easy=True)  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
            if isinstance(audio, FileType) and audio.info:
                if "cuesheet" in audio:
                    return parse_cue(audio["cuesheet"][0], os.path.dirname(file_path))[0]

                if "title" in audio and "�" not in str(audio["title"][0]):
                    title = str(audio["title"][0])
                elif "TIT2" in audio and "�" not in str(audio["TIT2"][0]):
                    title = str(audio["TIT2"][0])
                else:
                    msg = f"{file_path} 无法获取歌曲标题"
                    raise GetSongInfoError(msg)

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

                if "year" in audio and "�" not in str(audio["year"][0]):
                    date = str(audio["year"][0])
                elif "TDRC" in audio and "�" not in str(audio["TDRC"][0]):
                    date = str(audio["TDRC"][0])
                else:
                    date = None

                metadata = {
                    "title": title,
                    "artist": artist,
                    "album": album,
                    "date": date,
                    "duration": int(audio.info.length) if audio.info.length else None,
                    "type": "audio",
                    "file_path": file_path,
                }
                if metadata["title"] is None:
                    msg = f"{file_path} 无法获取歌曲标题"
                    raise GetSongInfoError(msg)
            else:
                msg = f"{file_path} 无法获取歌曲信息"
                raise GetSongInfoError(msg)
        else:
            msg = f"{file_path} 文件格式不支持"
            raise GetSongInfoError(msg)

    except MutagenError as e:    # type: ignore[reportPrivateImportUsage] mutagen中的MutagenError被误定义为私有 quodlibet/mutagen#647
        logger.exception("%s获取文件信息失败", file_path)
        msg = f"获取文件信息失败:{e.__class__.__name__}: {e!s}"
        raise GetSongInfoError(msg) from e
    else:
        return [metadata]


def write_lyrics(file_path: str, lyrics_text: str, lyrics: Lyrics | None = None) -> None:
    audio = File(file_path)

    if audio and isinstance(audio, FileType):
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
        msg = f"{file_path} 不支持的文件格式"
        raise FileTypeError(msg)


def get_audio_duration(file_path: str) -> int | None:
    if not os.path.isfile(file_path):
        logger.error("未找到文件: %s", file_path)
        return None
    try:
        audio = File(file_path)  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
        return int(audio.info.length) if audio.info.length else None  # type: ignore[reportOptionalMemberAccess]
    except Exception:
        logger.exception("%s获取文件时长失败", file_path)
        return None


def parse_cue_from_file(file_path: str) -> tuple[list, list]:
    file_content = read_unknown_encoding_file(file_path=file_path, sign_word=("FILE", "FILE"))
    return parse_cue(data=file_content, file_dir=os.path.dirname(file_path), file_path=file_path)


def parse_cue(data: str, file_dir: str, file_path: str | None = None) -> tuple[list, list]:  # noqa: PLR0915, C901, PLR0912
    cuedata: dict = {"files": []}
    for line in data.splitlines():
        if line.startswith('TITLE'):  # 标题
            if '"' in line:
                cuedata['title'] = re.findall(r'^TITLE "(.*)"', line)[0]
            else:
                cuedata['title'] = re.findall(r'^TITLE (.*)', line)[0]
        elif line.startswith('PERFORMER'):  # 演唱者
            if '"' in line:
                cuedata['performer'] = re.findall(r'^PERFORMER "(.*)"', line)[0]
            else:
                cuedata['performer'] = re.findall(r'^PERFORMER (.*)', line)[0]
        elif line.startswith("SONGWRITER"):  # 编曲者
            if '"' in line:
                cuedata['songwriter'] = re.findall(r'^SONGWRITER "(.*)"', line)[0]
            else:
                cuedata['songwriter'] = re.findall(r'^SONGWRITER (.*)', line)[0]
        elif line.startswith("CATALOG"):  # 唯一 EAN 编号
            if '"' in line:
                cuedata['catalog'] = re.findall(r'^CATALOG "(.*)"', line)[0]
            else:
                cuedata['catalog'] = re.findall(r'^CATALOG (.*)', line)[0]
        elif line.startswith("REM"):  # 注释(扩展命令)
            if line.startswith("REM GENRE"):  # 分类
                if '"' in line:
                    cuedata['genre'] = re.findall(r'^REM GENRE "(.*)"', line)[0]
                else:
                    cuedata['genre'] = re.findall(r'^REM GENRE (.*)', line)[0]
            elif line.startswith("REM DISCID"):  # CD 的唯一编号
                if '"' in line:
                    cuedata['discid'] = re.findall(r'^REM DISCID "(.*)"', line)[0]
                else:
                    cuedata['discid'] = re.findall(r'^REM DISCID (.*)', line)[0]
            elif line.startswith("REM DATE"):
                if '"' in line:
                    cuedata['date'] = re.findall(r'^REM DATE "(.*)"', line)[0]
                else:
                    cuedata['date'] = re.findall(r'^REM DATE (.*)', line)[0]
            elif line.startswith("REM COMMENT"):  # CUE 的生成说明
                if '"' in line:
                    cuedata['comment'] = re.findall(r'^REM COMMENT "(.*)"', line)[0]
                else:
                    cuedata['comment'] = re.findall(r'^REM COMMENT (.*)', line)[0]
            elif line.startswith("CDTEXTFILE"):  # CD-TEXT 信息文件
                if '"' in line:
                    cuedata['cdtextfile'] = re.findall(r'^CDTEXTFILE "(.*)"', line)[0]
                else:
                    cuedata['cdtextfile'] = re.findall(r'^CDTEXTFILE (.*)', line)[0]
            else:
                if "rem" not in cuedata:
                    cuedata["rem"] = ""
                cuedata["rem"] += line.replace("REM ", "") + "\n"
        elif line.startswith("FILE"):
            cuedata["filetype"] = re.findall(r'\w+$', line)[0]
            if '"' in line:
                cuedata["files"].append({"filename": re.findall(r'^FILE "(.*)"', line)[0], "tracks": []})
            else:
                cuedata["files"].append({"filename": re.findall(r'^FILE (.*)', line)[0], "tracks": []})
        elif line.startswith("  TRACK"):
            cuedata["files"][-1]["tracks"].append({})
            cuedata["files"][-1]["tracks"][-1]["id"] = re.findall(r'^  TRACK (\d+)', line)[0]
            cuedata["files"][-1]["tracks"][-1]["type"] = re.findall(r'^  TRACK \d+ (\w+)', line)[0]
        elif line.startswith("    INDEX"):
            index = re.findall(r'^    INDEX (\d+)', line)[0]
            if index == "00":  # 空档
                pass
            if cuedata["files"][-1]["tracks"]:
                cuedata["files"][-1]["tracks"][-1]["index"] = index
                cuedata["files"][-1]["tracks"][-1]["begintime"] = re.findall(r'^    INDEX \d+ (\d+:\d+:\d+)', line)[0]
        elif line.startswith("  PREGAP"):  # 轨段前的空白时间
            cuedata["files"][-1]["tracks"][-1]["pregap"] = re.findall(r'^    PREGAP (\d+:\d+:\d+)', line)[0]
        elif line.startswith("  POSTGAP"):  # 轨段后的空白时间
            cuedata["files"][-1]["tracks"][-1]["postgap"] = re.findall(r'^    POSTGAP (\d+:\d+:\d+)', line)[0]
        elif line.startswith("    TITLE"):  # 标题
            if '"' in line:
                cuedata["files"][-1]["tracks"][-1]["title"] = re.findall(r'^    TITLE "(.*)"', line)[0]
            else:
                cuedata["files"][-1]["tracks"][-1]["title"] = re.findall(r'^    TITLE (.*)', line)[0]
        elif line.startswith("    SONGWRITER"):  # 编曲者
            if '"' in line:
                cuedata["files"][-1]["tracks"][-1]["songwriter"] = re.findall(r'^    SONGWRITER "(.*)"', line)[0]
            else:
                cuedata["files"][-1]["tracks"][-1]["songwriter"] = re.findall(r'^    SONGWRITER (.*)', line)[0]
        elif line.startswith("    PERFORMER"):  # 演唱者
            if '"' in line:
                cuedata["files"][-1]["tracks"][-1]["performer"] = re.findall(r'^    PERFORMER "(.*)"', line)[0]
            else:
                cuedata["files"][-1]["tracks"][-1]["performer"] = re.findall(r'^    PERFORMER (.*)', line)[0]
        elif line.startswith("    ISRC"):  # ISRC 码
            cuedata["files"][-1]["tracks"][-1]["isrc"] = re.findall(r'^    ISRC (.*)', line)[0]
        elif line.startswith("    FLAGS"):  # 指定SUBCODES
            cuedata["files"][-1]["tracks"][-1]["flags"] = re.findall(r'^    FLAGS (.*)', line)[0]
        elif line.startswith("    REM"):  # 注释(扩展命令)
            if line.startswith("    REM REPLAYGAIN_TRACK_GAIN"):  # 增益回放信息,用于提高/降低音量
                if '"' in line:
                    cuedata["files"][-1]["tracks"][-1]["replaygain_track_gain"] = re.findall(r'^    REM REPLAYGAIN_TRACK_GAIN "(.*)"', line)[0]
                else:
                    cuedata["files"][-1]["tracks"][-1]["replaygain_track_gain"] = re.findall(r'^    REM REPLAYGAIN_TRACK_GAIN (.*)', line)[0]
            elif line.startswith("    REM REPLAYGAIN_TRACK_PEAK"):  # 增益回放信息,指定音轨峰值
                if '"' in line:
                    cuedata["files"][-1]["tracks"][-1]["replaygain_track_peak"] = re.findall(r'^    REM REPLAYGAIN_TRACK_PEAK "(.*)"', line)[0]
                else:
                    cuedata["files"][-1]["tracks"][-1]["replaygain_track_peak"] = re.findall(r'^    REM REPLAYGAIN_TRACK_PEAK (.*)', line)[0]
        else:
            logger.warning("解析cue时遇到未知的行: %s", line)

    songs = []
    audio_file_paths = []
    for file in cuedata["files"]:

        # 处理音频文件路径
        audio_file_path = os.path.join(file_dir, file["filename"])
        if not os.path.isfile(audio_file_path):
            for file_extension in audio_formats:
                if file_path and (
                    (audio_file_path := os.path.join(os.path.dirname(file_path), os.path.splitext(file["filename"])[0] + "." + file_extension))
                    and os.path.isfile(audio_file_path) or
                    (audio_file_path := os.path.splitext(file_path)[0] + "." + file_extension)
                        and os.path.isfile(audio_file_path)):
                    break
            else:
                logger.warning("未找到音频文件: %s", file["filename"])
                audio_file_path = ""

        if os.path.isfile(audio_file_path):
            audio_file_paths.append(audio_file_path)

        for i, track in enumerate(file["tracks"]):
            if "title" not in track:
                logger.warning("未找到标题, 跳过第%s首", i + 1)
                continue
            songs.append({"title": track["title"],
                          "artist": None,
                          "album": None,
                          "date": None,
                          "duration": None,
                          "type": "cue",
                          "file_path": audio_file_path,
                          "track": track.get("id"),
                          })

            if "performer" in track and track["performer"].strip() != "":
                songs[-1]["artist"] = track["performer"]
            elif "songwriter" in track and track["songwriter"].strip() != "":
                songs[-1]["artist"] = track["songwriter"]
            elif "performer" in cuedata and cuedata["performer"].strip() != "":
                songs[-1]["artist"] = cuedata["performer"]
            elif "songwriter" in cuedata and cuedata["songwriter"].strip() != "":
                songs[-1]["artist"] = cuedata["songwriter"]

            if "title" in cuedata and cuedata["title"].strip() != "":
                songs[-1]["album"] = cuedata["title"]

            if "date" in cuedata and cuedata["date"].strip() != "":
                songs[-1]["date"] = cuedata["date"]

            if "begintime" in track:
                begin_time = time2ms(*track["begintime"].split(":"))
                if i != 0:
                    songs[-2]["duration"] = (begin_time - songs[-2]["duration"] - time2ms(*file["tracks"][i - 1].get("postgap", "0:0:0").split(":"))) // 1000
                begin_time += time2ms(*track.get("pregap", "0:0:0").split(":"))
                songs[-1]["duration"] = begin_time

        audio_duration = get_audio_duration(audio_file_path)
        if audio_duration is not None and len(songs) != 0:
            songs[-1]["duration"] = audio_duration - (songs[-1]["duration"] // 1000)
        elif len(songs) != 0:
            songs[-1]["duration"] = None

    return songs, audio_file_paths


@overload
def parse_drop_infos(mime: QMimeData, first: Literal[True] = True) -> dict:
    ...


@overload
def parse_drop_infos(mime: QMimeData, first: Literal[False] = False) -> list[dict]:
    ...


def parse_drop_infos(mime: QMimeData, first: bool = True) -> list[dict] | dict:
    """解析拖拽的文件

    :param mime: 拖拽的文件信息
    :param first: 是否只获取第一个文件
    :return: 解析后的文件信息
    """
    paths, tracks, indexs = [], [], []
    # 特殊适配
    if 'application/x-qt-windows-mime;value="ACL.FileURIs"' in mime.formats():
        # AIMP
        data = mime.data('application/x-qt-windows-mime;value="ACL.FileURIs"')
        urls = bytearray(data.data()[20:-4]).decode('UTF-16').split("\x00")
        for path in urls:
            if path.split(":")[-1].isdigit():
                indexs.append(path.split(":")[-1])
                paths.append(":".join(path.split(":")[:-1]))
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
            length = struct.unpack_from('<I', paths_data, i)[0]
            i += 4
            # 提取指定长度的文件路径,解码为UTF-8
            path = paths_data[i:i + length].decode('UTF-8')
            i += length
            if path.startswith("file://"):
                path = path[7:]
            paths.append(path)

        for song in mime.text().splitlines():
            if (matched := re.fullmatch(r"(?:(?P<artist>.*?) - )?\[(?P<album>.*?) (?:CD\d+/\d+ )?#(?P<track>\d+)\] (?P<title>.*)", song)) is not None:
                tracks.append(matched.group('track'))
            else:
                tracks.append(None)

    if not paths:
        try:
            paths = [url.toLocalFile() for url in mime.urls()]
        except Exception as e:
            logger.exception(e)
            msg = "无法获取文件路径"
            logger.error(msg)
            raise DropError(msg) from e

    songs: list[dict] = []
    if first:
        if len(paths) >= 1:
            paths = paths[:1]
        else:
            msg = "没有获取到任何文件信息"
            raise DropError(msg)
    for i, path in enumerate(paths):
        track, index = None, None
        if tracks and len(tracks) > i:
            track = tracks[i]
        elif indexs and len(indexs) > i:
            index = indexs[i]
        logger.info(f"解析文件 {path}, track={track}, index={index}")

        if path.lower().endswith('.cue') and (isinstance(track, str | int) or index is not None):
            try:
                infos, _audio_file_paths = parse_cue_from_file(path)
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
                    if song["track"] is not None and int(song["track"]) == int(track):
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
                    if song["track"] is not None and int(song["track"]) == int(track):
                        break
                else:
                    msg = f"文件 {path} 中没有找到第 {track} 轨歌曲"
                    logger.error(msg)
                    raise DropError(msg)
            else:
                msg = f"文件 {path} 中包含多个歌曲"
                logger.error(msg)
                raise DropError(msg)

        if not isinstance(song, dict):
            msg = "获取歌词信息时出现未知错误"
            logger.error(msg)
            raise DropError(msg)
        songs.append(song)

    if first:
        return songs[0]
    return songs
