# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import logging
import os
import re

import mutagen
from chardet import detect

if __name__ != '__main__':
    from utils.utils import time2ms
else:
    from utils import time2ms

file_extensions = ['3g2', 'aac', 'aif', 'ape', 'apev2', 'dff', 'dsf', 'flac', 'm4a', 'm4b', 'mid', 'mp3', 'mp4', 'mpc', 'ofr', 'ofs', 'ogg', 'oggflac', 'oggtheora', 'opus', 'spx', 'tak', 'tta', 'wav', 'wma', 'wv']


def get_audio_file_info(file_path: str) -> dict | str:
    if not os.path.isfile(file_path):
        logging.error(f"未找到文件: {file_path}")
        return f"未找到文件: {file_path}"
    try:
        if file_path.lower().split('.')[-1] in file_extensions:
            audio = mutagen.File(file_path, easy=True)
            if audio is not None and audio.tags is not None:
                if "title" in audio and "�" not in str(audio["title"][0]):
                    title = str(audio["title"][0])
                elif "TIT2" in audio and "�" not in str(audio["TIT2"][0]):
                    title = str(audio["TIT2"][0])
                else:
                    return f"{file_path}无法获取歌曲标题,跳过"

                if "artist" in audio and "�" not in str(audio["artist"][0]):
                    artist = str(audio["artist"][0])
                elif "TPE1" in audio and "�" not in str(audio["TPE1"][0]):
                    artist = str(audio["TPE1"][0])
                else:
                    artist = None

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
                    return f"{file_path}无法获取歌曲标题,跳过"
                return metadata
    except Exception as e:
        logging.exception(f"{file_path}获取文件信息失败")
        return f"{file_path}获取文件信息失败: {e}"


def get_audio_duration(file_path: str) -> str | None:
    try:
        audio = mutagen.File(file_path)
        return int(audio.info.length) if audio.info.length else None
    except Exception:
        logging.exception(f"{file_path}获取文件时长失败")
        return None


def parse_cue(file_path: str) -> tuple[list, str]:  # noqa: PLR0915
    with open(file_path, 'rb') as f:
        raw_data = f.read()
        detect_result = detect(raw_data)
        if detect_result['confidence'] > 0.8:
            file_content = raw_data.decode(detect_result["encoding"], errors='ignore')
        else:
            logging.warning(f"{file_path}无法推测编码, 尝试遍历所有编码")
            file_content = None

        if file_content is None:
            encodings = ["ascii", "gb2312", "gbk", "gb18030", "big5", "big5hkscs",
                         "euc_jp", "euc_jis_2004", "euc_jisx0213", "euc_kr",
                         "hz", "iso2022_jp", "iso2022_jp_1", "iso2022_jp_2",
                         "iso2022_jp_2004", "iso2022_jp_3", "iso2022_jp_ext",
                         "iso2022_kr", "latin_1", "iso8859_2", "iso8859_3",
                         "iso8859_4", "iso8859_5", "iso8859_6", "iso8859_7",
                         "iso8859_8", "iso8859_9", "iso8859_10", "iso8859_11",
                         "iso8859_13", "iso8859_14", "iso8859_15", "iso8859_16",
                         "johab", "koi8_r", "koi8_t", "koi8_u", "kz1048", "mac_cyrillic",
                         "mac_greek", "mac_iceland", "mac_latin2", "mac_roman",
                         "mac_turkish", "ptcp154", "shift_jis", "shift_jis_2004",
                         "shift_jisx0213", "utf_32", "utf_32_be", "utf_32_le",
                         "utf_16", "utf_16_be", "utf_16_le", "utf_7", "utf_8",
                         "utf_8_sig", "cp037", "cp273", "cp424",
                         "cp437", "cp500", "cp720", "cp737", "cp775", "cp850",
                         "cp852", "cp855", "cp856", "cp857", "cp858", "cp860",
                         "cp861", "cp862", "cp863", "cp864", "cp865", "cp866",
                         "cp869", "cp874", "cp875", "cp932", "cp949", "cp950",
                         "cp1006", "cp1026", "cp1125", "cp1140", "cp1250",
                         "cp1251", "cp1252", "cp1253", "cp1254", "cp1255",
                         "cp1256", "cp1257", "cp1258"]
            file_content = None
            for encoding in encodings:
                try:
                    file_content = raw_data.decode(encoding)
                    if "FILE" in file_content and "TRACK" in file_content:
                        break
                except Exception:
                    logging.debug(f"尝试编码:{encoding}失败")

    if file_content is None:
        msg = "无法解码文件"
        raise UnicodeDecodeError(msg)

    cuedata = {"files": []}
    for line in file_content.splitlines():
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
            logging.warning(f"未知的行{line}")

    songs = []
    audio_file_paths = []
    for file in cuedata["files"]:

        # 处理音频文件路径
        audio_file_path = os.path.join(os.path.dirname(file_path), file["filename"])
        if not os.path.exists(audio_file_path):
            for file_extension in file_extensions:
                if os.path.exists(os.path.splitext(file_path)[0] + "." + file_extension):
                    audio_file_path = os.path.splitext(file_path)[0] + "." + file_extension
                    break

        if os.path.exists(audio_file_path):
            audio_file_paths.append(audio_file_path)

        for i, track in enumerate(file["tracks"]):
            if "title" not in track:
                logging.warning(f"未找到标题, 跳过第{i+1}首")
                continue
            songs.append({"title": track["title"],
                          "artist": None,
                          "album": None,
                          "date": None,
                          "duration": None,
                          "type": "cue",
                          "file_path": audio_file_path,
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
