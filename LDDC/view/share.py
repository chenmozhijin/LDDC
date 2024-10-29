# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re
import struct

from PySide6.QtCore import QMimeData

from LDDC.backend.song_info import get_audio_file_infos, parse_cue_from_file
from LDDC.utils.error import DropError
from LDDC.utils.logger import logger


def parse_drop_mime(mime: QMimeData) -> list[dict]:
    paths, tracks, indexs = None, None, None
    # 特殊适配
    if 'application/x-qt-windows-mime;value="ACL.FileURIs"' in mime.formats():
        # AIMP
        data = mime.data('application/x-qt-windows-mime;value="ACL.FileURIs"')
        urls = bytearray(data.data()[20:-4]).decode('UTF-16').split("\x00")
        for path in urls:
            if path.split(":")[-1].isdigit():
                if indexs is None or paths is None:
                    indexs = []
                    paths = []
                indexs.append(path.split(":")[-1])
                paths.append(":".join(path.split(":")[:-1]))
    elif 'application/x-qt-windows-mime;value="foobar2000_playable_location_format"' in mime.formats():
        # foobar2000
        i = 0
        paths_data = bytes(mime.data('application/x-qt-windows-mime;value="foobar2000_playable_location_format"').data())
        paths = []
        while i < len(paths_data) - 4:
            # 提取前4个字节的编号
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
                if tracks is None:
                    tracks = []
                tracks.append(matched.group('track'))

    if not paths:
        try:
            paths = [url.toLocalFile() for url in mime.urls()]
        except Exception as e:
            logger.exception(e)
            msg = "无法获取文件路径"
            raise DropError(msg) from e

    songs: list[dict] = []
    for i, path in enumerate(paths):
        track, index = None, None
        if tracks and len(tracks) > i:
            track = tracks[i]
        elif indexs and len(indexs) > i:
            index = indexs[i]

        if path.lower().endswith('.cue') and (isinstance(track, str | int) or index is not None):
            try:
                infos, _audio_file_paths = parse_cue_from_file(path)
            except Exception as e:
                msg = f"解析文件 {path} 失败: {e}"
                raise DropError(msg) from e
            if index is not None:
                if int(index) + 1 >= len(infos):
                    msg = f"文件 {path} 中没有找到第 {index} 轨歌曲"
                    raise DropError(msg)
                song = infos[int(index)]
            elif isinstance(track, str | int):
                for song in infos:
                    if song["track"] is not None and int(song["track"]) == int(track):
                        break
                else:
                    msg = f"文件 {path} 中没有找到第 {track} 轨歌曲"
                    raise DropError(msg)
        else:
            try:
                infos = get_audio_file_infos(path)
            except Exception as e:
                logger.exception(e)
                msg = f"解析文件 {path} 失败: {e}"
                raise DropError(msg) from e
            if len(infos) == 1:
                song = infos[0]
            elif isinstance(track, str | int):
                for song in infos:
                    if song["track"] is not None and int(song["track"]) == int(track):
                        break
                else:
                    msg = f"文件 {path} 中没有找到第 {track} 轨歌曲"
                    raise DropError(msg)
            else:
                msg = f"文件 {path} 中包含多个歌曲"
                raise DropError(msg)

        if not isinstance(song, dict):
            msg = "获取歌词信息时出现未知错误"
            raise DropError(msg)
        songs.append(song)

    return songs
