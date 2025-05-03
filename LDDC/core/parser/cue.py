# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re
from dataclasses import dataclass, field
from pathlib import Path

from mutagen import File  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有

from LDDC.common.logger import logger
from LDDC.common.models import Artist, SongInfo, Source
from LDDC.common.time import time2ms
from LDDC.common.utils import read_unknown_encoding_file

AUDIO_FORMATS = [
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


@dataclass
class Track:
    id: str
    type: str
    indexes: dict[str, int] = field(default_factory=dict)  # 存储所有INDEX
    pregap: int | None = None
    postgap: int | None = None
    title: str | None = None
    performer: str | None = None
    songwriter: str | None = None
    isrc: str | None = None
    flags: str | None = None
    replaygain: dict[str, str] = field(default_factory=dict)


@dataclass
class AudioFile:
    filename: str
    type: str
    tracks: list[Track] = field(default_factory=list)


@dataclass
class CueData:
    path: Path
    title: str | None = None
    performer: str | None = None
    songwriter: str | None = None
    catalog: str | None = None
    files: list[AudioFile] = field(default_factory=list)

    genre: str | None = None
    discid: str | None = None
    date: str | None = None
    comment: str | None = None
    cdtextfile: str | None = None

    rem: str = field(default_factory=str)

    def get_audio_path(self, file: AudioFile) -> Path | None:
        song_path = self.path.parent / file.filename
        if not song_path.is_file():
            for file_extension in AUDIO_FORMATS:
                if self.path and (
                    ((song_path := self.path.parent / (Path(file.filename).stem + "." + file_extension)) and song_path.is_file())
                    or ((song_path := Path(Path(self.path).stem + "." + file_extension)) and song_path.is_file())
                ):
                    break
        return song_path if song_path and song_path.is_file() else None

    def get_audio_paths(self) -> list[Path]:
        """将 CueData 转换为歌曲路径列表"""
        paths = []
        for file in self.files:
            song_path = self.get_audio_path(file)
            if song_path:
                paths.append(song_path)
        return paths

    def to_songinfos(self) -> list[SongInfo]:
        """将 CueData 转换为 SongInfo 列表"""
        songinfos = []
        for file in self.files:
            # 计算路径
            song_path = self.get_audio_path(file) or self.path.parent / file.filename

            for i, track in enumerate(file.tracks):
                # 计算时间
                # start = (track.indexes.get("00") or track.indexes["01"]) - (track.pregap or 0)  # 计算开始时间
                start = track.indexes["01"] - (track.pregap or 0)

                # 计算结束时间
                if i < len(file.tracks) - 1:
                    next_track = file.tracks[i + 1]
                    # end = (next_track.indexes.get("00") or next_track.indexes["01"]) + (track.postgap or 0)
                    end = next_track.indexes["01"] + (track.postgap or 0)
                elif song_path.is_file():
                    try:
                        audio = File(song_path)  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
                        end = (audio.info.length * 1000 + (track.postgap or 0)) if audio is not None and audio.info.length else None  # type: ignore[reportOptionalMemberAccess]
                    except Exception:
                        end = None
                    if end is None:
                        logger.warning(f"没有获取到{song_path}的时长信息, {track.title} - {track.performer} 将没有时长")

                duration = end - start if end else None

                songinfos.append(
                    SongInfo(
                        source=Source.Local,
                        title=track.title,
                        artist=Artist(
                            [track.performer, self.performer]
                            if track.performer and self.performer
                            else track.performer or track.songwriter or self.performer or self.songwriter or [],
                        ),
                        album=self.title,
                        duration=max(int(duration), 0) if duration else None,
                        id=track.id,
                        from_cue=True,
                        path=song_path,
                    ),
                )

        return songinfos


def parse_quoted(s: str) -> str:
    """处理带引号的字符串"""
    return s[1:-1] if len(s) >= 2 and s[0] == s[-1] == '"' else s.strip()


def parse_cue(path: Path, data: str | None = None) -> CueData:
    """解析cue"""
    if data is None:
        data = read_unknown_encoding_file(path)

    cue = CueData(path=path)

    current_track: Track | None = None
    current_file: AudioFile | None = None
    for orig_line in data.splitlines():
        line = orig_line.rstrip()
        if not line:
            continue

        try:
            # 提取命令和参数
            indent = (len(line) - len(line.lstrip())) // 2  # 计算缩进级别
            line = line.lstrip()
            cmd_part, _, args = line.partition(" ")
            cmd = cmd_part.strip().upper()

            match indent:
                # 全局命令
                case 0:
                    match cmd:
                        case "FILE":
                            if match := re.match(r'^"(.*?)" (\w+)$|^(.*?) (\w+)$', args):
                                filename = parse_quoted(match.group(1) or match.group(3))
                                current_file = AudioFile(filename=filename, type=match.group(2) or match.group(4))
                                cue.files.append(current_file)
                        case "REM":
                            if " " in args:
                                subcmd, subargs = args.split(maxsplit=1)
                                if subcmd in ("GENRE", "DISCID", "DATE", "COMMENT", "CDTEXTFILE"):
                                    setattr(cue, subcmd.lower(), parse_quoted(subargs))
                                else:
                                    cue.rem += parse_quoted(args)
                        case _ if cmd in ("TITLE", "PERFORMER", "SONGWRITER", "CATALOG"):
                            setattr(cue, cmd.lower(), parse_quoted(args))

                # 文件级命令 (缩进1级)
                case 1:
                    match cmd:
                        case "TRACK" if current_file:
                            track_id, track_type = args.split(maxsplit=1)
                            current_track = Track(id=track_id, type=track_type)
                            current_file.tracks.append(current_track)

                # 轨道级命令 (缩进2级+)
                case _ if indent >= 2 and current_track:
                    match cmd:
                        case "INDEX":
                            idx, timecode = args.split(maxsplit=1)
                            current_track.indexes[idx] = time2ms(*timecode.split(":"))
                        case "PREGAP":
                            current_track.pregap = time2ms(*args.strip().split(":"))
                        case "POSTGAP":
                            current_track.postgap = time2ms(*args.strip().split(":"))
                        case "REM":
                            if args.startswith("REPLAYGAIN_"):
                                gain_type, gain_value = args.split(maxsplit=1)
                                current_track.replaygain[gain_type] = parse_quoted(gain_value)
                        case _ if cmd in ("TITLE", "PERFORMER", "SONGWRITER", "ISRC", "FLAGS"):
                            setattr(current_track, cmd.lower(), parse_quoted(args))

        except Exception as e:
            logger.warning(f"解析失败: {line} ({e})")

    return cue
