# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os
import re

import mutagen

from utils.error import GetSongInfoError
from utils.logger import logger
from utils.utils import read_unknown_encoding_file, time2ms

file_extensions = ['3g2', 'aac', 'aif', 'ape', 'apev2', 'dff',
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
        if file_path.lower().split('.')[-1] in file_extensions:
            audio = mutagen.File(file_path, easy=True)  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
            if audio is not None:
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

    except mutagen.MutagenError as e:    # type: ignore[reportPrivateImportUsage] mutagen中的MutagenError被误定义为私有 quodlibet/mutagen#647
        logger.exception("%s获取文件信息失败", file_path)
        msg = f"获取文件信息失败:{e.__class__.__name__}: {e!s}"
        raise GetSongInfoError(msg) from e
    else:
        return [metadata]


def get_audio_duration(file_path: str) -> int | None:
    try:
        audio = mutagen.File(file_path)  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
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
            elif line.startswith("CATALOG"):  # 指定唱片的唯一 EAN 编号
                if '"' in line:
                    cuedata['catalog'] = re.findall(r'^CATALOG "(.*)"', line)[0]
                else:
                    cuedata['catalog'] = re.findall(r'^CATALOG (.*)', line)[0]
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
        if not os.path.exists(audio_file_path) and file_path:
            for file_extension in file_extensions:
                if os.path.exists(os.path.splitext(file_path)[0] + "." + file_extension):
                    audio_file_path = os.path.splitext(file_path)[0] + "." + file_extension
                    break

        if os.path.exists(audio_file_path):
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
