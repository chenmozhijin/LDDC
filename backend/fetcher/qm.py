import re

from backend.api import qm_get_lyrics
from backend.decryptor import qrc_decrypt
from backend.lyrics import Lyrics, LyricsData
from utils.enum import QrcType
from utils.error import LyricsProcessingError, LyricsRequestError

from .share import lrc2dict_list, plaintext2list


def qrc2list(qrc: str) -> tuple[dict, list]:
    """将qrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
    qrc = re.findall(r'<Lyric_1 LyricType="1" LyricContent="(.*?)"/>', qrc, re.DOTALL)[0]
    qrc_lines = qrc.split('\n')
    tags = {}
    lrc_list: LyricsData = []
    wrods_split_pattern = re.compile(r'(?:\[\d+,\d+\])?((?:(?!\(\d+,\d+\)).)+)\((\d+),(\d+)\)')  # 逐字匹配
    line_split_pattern = re.compile(r'^\[(\d+),(\d+)\](.*)$')  # 逐行匹配
    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")

    for i in qrc_lines:
        line = i.strip()
        line_split_content = re.findall(line_split_pattern, line)
        if line_split_content:  # 判断是否为歌词行
            line_start_time, line_duration, line_content = line_split_content[0]
            lrc_list.append((int(line_start_time), int(line_start_time) + int(line_duration), []))
            wrods_split_content = re.findall(wrods_split_pattern, line)
            if wrods_split_content:  # 判断是否为逐字歌词
                for text, starttime, duration in wrods_split_content:
                    if text != "\r":
                        lrc_list[-1][2].append((int(starttime), int(starttime) + int(duration), text))
            else:  # 如果不是逐字歌词
                lrc_list[-1][2].append((int(line_start_time), int(line_start_time) + int(line_duration), line_content))
        else:
            tag_split_content = re.findall(tag_split_pattern, line)
            if tag_split_content:
                tags.update({tag_split_content[0][0]: tag_split_content[0][1]})

    return tags, lrc_list


def get_lyrics(lyrics: Lyrics) -> None:
    response = qm_get_lyrics(lyrics.title, lyrics.artist, lyrics.album, lyrics.id, lyrics.duration)
    if isinstance(response, str):
        raise LyricsRequestError(response)
    for key, value in [("orig", 'lyric'),
                       ("ts", 'trans'),
                       ("roma", 'roma')]:
        lrc = response[value]
        lrc_t = (response["qrc_t"] if response["qrc_t"] != 0 else response["lrc_t"]) if value == "lyric" else response[value + "_t"]
        if lrc != "" and lrc_t != "0":
            encrypted_lyric = lrc

            lyric = qrc_decrypt(encrypted_lyric, QrcType.CLOUD)

            if lyric is not None:
                if re.search(r'<Lyric_1 LyricType="1" LyricContent="(.*?)"/>', lyric, re.DOTALL):
                    tags, lyric = qrc2list(lyric)
                elif "[" in lyric and "]" in lyric:
                    tags, lyric = lrc2dict_list(lyric, to_list=True)
                else:
                    tags = {}
                    lyric = plaintext2list(lyric)

                if key == "orig":
                    lyrics.tags = tags

                lyrics[key] = lyric
        elif (lrc_t == "0" and key == "orig"):
            msg = "没有获取到可用的歌词"
            raise LyricsProcessingError(msg)
