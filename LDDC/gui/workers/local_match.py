# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from threading import Lock
from typing import ClassVar

from mutagen import MutagenError  # type: ignore[reportPrivateImportUsage]
from PySide6.QtCore import (
    QCoreApplication,
    QMimeData,
)

from LDDC.common.data.config import cfg
from LDDC.common.exceptions import LyricsNotFoundError
from LDDC.common.logger import logger
from LDDC.common.models import FileNameMode, LyricsFormat, SaveMode, SongInfo, Source
from LDDC.common.path_processor import get_local_match_save_path
from LDDC.common.task_manager import TaskSignal, TaskWorker
from LDDC.core.auto_fetch import auto_fetch
from LDDC.core.parser.cue import parse_cue
from LDDC.core.song_info import audio_formats, get_audio_file_infos, has_lyrics, parse_drop_infos, write_lyrics


class LocalMatchSave2TagMode(Enum):
    ONLY_FILE = 0  # 不保存到歌词标签
    ONLY_TAG = 1  # 保存到歌词标签(非cue)
    BOTH = 2  # 保存到歌词标签(非cue)与文件


class LocalMatchingStatusType(Enum):
    SUCCESS = 0
    SKIP_INST = 1
    AUTO_FETCH_FAIL = 2
    SAVE_FAIL = 3
    UNDERKNOWN_ERROR = 4
    SKIP_EXISTING = 5


@dataclass
class LocalMatchingStatus:
    status: LocalMatchingStatusType
    index: int
    text: str
    path: Path | None = None


@dataclass
class GetInfosProgress:
    value: int
    max_value: int


class GetInfosWorker(TaskWorker):
    progress = TaskSignal[str, int, int]()  # text, value, max_value, info, root_path
    finished = TaskSignal[list[tuple[SongInfo, Path | None]], list[str]]()  # result, errors

    get_infos_progress: ClassVar[dict[int, dict[int, GetInfosProgress]]] = {}
    get_infos_progress_lock = Lock()

    def __init__(self, parent: object, mime: QMimeData) -> None:
        super().__init__()
        self.mime = mime
        self.errors = []
        self.parent_id = id(parent)

    def update_get_infos_progress(self, msg: str, progress: int, total: int) -> None:
        with self.get_infos_progress_lock:
            self.get_infos_progress[self.parent_id][self.taskid].value = progress
            self.get_infos_progress[self.parent_id][self.taskid].max_value = total
            progress = sum(info.value for info in self.get_infos_progress[self.parent_id].values())
            total = sum(info.max_value for info in self.get_infos_progress[self.parent_id].values())
            self.progress.emit(msg, progress, total)

    def del_get_infos_progress(self) -> None:
        with self.get_infos_progress_lock:
            del self.get_infos_progress[self.parent_id][self.taskid]
            if not self.get_infos_progress[self.parent_id]:
                del self.get_infos_progress[self.parent_id]
                self.progress.emit("", 0, 0)

    def error_handling(self, e: Exception) -> None:
        self.finished.emit([], self.errors)
        self.del_get_infos_progress()
        return super().error_handling(e)

    def run_task(self) -> None:
        with self.get_infos_progress_lock:
            self.get_infos_progress[self.parent_id] = {self.taskid: GetInfosProgress(0, 0)}
        formats = self.mime.formats()
        if (
            'application/x-qt-windows-mime;value="ACL.FileURIs"' in formats
            or 'application/x-qt-windows-mime;value="foobar2000_playable_location_format"' in formats
        ):
            infos = [
                (info, None) for info in parse_drop_infos(self.mime, first=False, progress=self.update_get_infos_progress, running=lambda: not self.is_stopped)
            ]
            self.del_get_infos_progress()
            if not self.is_stopped:
                self.finished.emit(infos, [])

        else:
            self.update_get_infos_progress(QCoreApplication.translate("LocalMatch", "遍历文件..."), 0, 0)
            mix_paths = [Path(url.toLocalFile()) for url in self.mime.urls()]
            infos: list[tuple[SongInfo, Path | None]] = []
            dirs: list[Path] = []
            audio_paths: list[tuple[Path | None, Path]] = []  # (遍历的目录, 文件路径)
            cue_paths: list[tuple[Path | None, Path]] = []  # (遍历的目录, 文件路径)
            exclude_audio_paths: list[Path] = []
            for path in mix_paths:
                if self.is_stopped:
                    self.del_get_infos_progress()
                    return
                if path.is_dir():
                    dirs.append(path)
                elif path.is_file():
                    if path.suffix.lower() == ".cue":
                        cue_paths.append((None, path))
                    elif path.suffix.lower().removeprefix(".") in audio_formats:
                        audio_paths.append((None, path))

            for directory in dirs:
                if self.is_stopped:
                    self.del_get_infos_progress()
                    return
                for root, _, files in directory.walk():
                    for file in files:
                        if self.is_stopped:
                            self.del_get_infos_progress()
                            return
                        if file.lower().endswith(".cue"):
                            cue_paths.append((directory, root / file))
                        elif file.lower().split(".")[-1] in audio_formats:
                            audio_paths.append((directory, root / file))

            total = len(audio_paths) + len(cue_paths)

            # 解析cue文件
            for i, (root_path, cue_path) in enumerate(cue_paths, start=1):
                if self.is_stopped:
                    self.del_get_infos_progress()
                    return
                self.update_get_infos_progress(QCoreApplication.translate("LocalMatch", "解析cue{}...").format(cue_path), i, total)
                try:
                    cue_data = parse_cue(cue_path)
                    songs = cue_data.to_songinfos()
                    exclude_audio_paths.extend(cue_data.get_audio_paths())
                    for song in songs:  # 添加遍历根目录到歌曲信息
                        infos.append((song, root_path))
                except Exception as e:
                    logger.exception("解析cue文件失败: %s", cue_path)
                    self.errors.append(f"{e.__class__.__name__}: {e!s}")

            # 排除cue文件中的音频文件
            audio_paths = [path for path in audio_paths if path[1] not in exclude_audio_paths]
            # 解析音频文件
            for i, (root_path, audio_path) in enumerate(audio_paths, start=1 + len(cue_paths)):
                if self.is_stopped:
                    self.del_get_infos_progress()
                    return
                self.update_get_infos_progress(QCoreApplication.translate("LocalMatch", "解析歌曲文件{}...").format(audio_path), i + len(cue_paths), total)
                try:
                    songs = get_audio_file_infos(audio_path)
                    for song in songs:  # 添加遍历根目录到歌曲信息
                        infos.append((song, root_path))
                except Exception as e:
                    logger.exception("解析歌曲文件失败: %s", audio_path)
                    self.errors.append(f"{e.__class__.__name__}: {e!s}")

            self.del_get_infos_progress()
            self.finished.emit(infos, self.errors)


class LocalMatchWorker(TaskWorker):
    progress = TaskSignal[str, int, int, LocalMatchingStatus | None]()  # text, value, max_value, status
    finished = TaskSignal[int, int, int, int]()  # success_count, fail_count, skip_count

    def __init__(
        self,
        infos_root_paths: list[tuple[SongInfo, Path | None]],
        save_mode: SaveMode,
        file_name_mode: FileNameMode,
        save2tag_mode: LocalMatchSave2TagMode,
        lyrics_format: LyricsFormat,
        langs: list[str],
        save_root_path: Path | None,
        min_score: int,
        sources: list[Source],
        skip_existing_lyrics: bool,
    ) -> None:
        """本地匹配歌词

        Args:
            task (Literal["get_infos", "match_lyrics"]): 任务类型

            infos_root_paths (list[dict]): 要匹配的歌曲信息与文件遍历的根路径
            save_mode (LocalMatchSaveMode): 保存模式
            file_name_mode (LocalMatchFileNameMode): 文件名模式
            save2tag_mode (LocalMatchSave2TagMode): 保存到标签模式
            lyrics_format (LyricsFormat): 歌词格式
            langs (list[str]): 语言
            save_root_path (str): 保存根路径
            min_score (int): 最小匹配分数
            sources (list[Source]): 歌词源
            skip_existing_lyrics (bool): 是否跳过已存在的歌词


        """
        super().__init__()
        self.errors: list[str] = []
        self.running = True

        self.infos_root_paths = infos_root_paths
        self.save_mode = save_mode
        self.file_name_mode = file_name_mode
        self.save2tag_mode = save2tag_mode
        self.lyrics_format = lyrics_format
        self.langs = langs
        self.save_root_path = save_root_path
        self.min_score = min_score
        self.sources = sources
        self.skip_existing_lyrics = skip_existing_lyrics

        self.skip_inst_lyrics = cfg["skip_inst_lyrics"]
        self.file_name_format = cfg["lyrics_file_name_fmt"]

    def check_skip_existing_lyrics(self, info: SongInfo, song_root_path: Path | None) -> bool:
        song_file_has_lyrics = has_lyrics(info.path) if info.path else False
        if self.save2tag_mode == LocalMatchSave2TagMode.ONLY_TAG and song_file_has_lyrics:
            return True
        save_path = get_local_match_save_path(
            save_mode=self.save_mode,
            file_name_mode=self.file_name_mode,
            local_info=info,
            lyrics_format=self.lyrics_format,
            file_name_format=self.file_name_format,
            langs=self.langs,
            save_root_path=self.save_root_path,
            cloud_info=None,
            song_root_path=song_root_path,
        )
        lyrics_file_exists = save_path.is_file() if isinstance(save_path, Path) else False
        if self.save2tag_mode == LocalMatchSave2TagMode.ONLY_FILE and lyrics_file_exists:
            return True
        return bool(self.save2tag_mode == LocalMatchSave2TagMode.BOTH and (song_file_has_lyrics or lyrics_file_exists))

    def run_task(self) -> None:
        total = len(self.infos_root_paths)
        success_count, skip_count = 0, 0
        status: LocalMatchingStatus | None = None
        for i, (info, song_root_path) in enumerate(self.infos_root_paths):
            if self.is_stopped:
                break

            self.progress.emit(f"正在匹配 {info.artist_title(replace=True)} 的歌词...", i, total, status)

            if self.skip_existing_lyrics and self.check_skip_existing_lyrics(info, song_root_path):
                status = LocalMatchingStatus(LocalMatchingStatusType.SKIP_EXISTING, i, QCoreApplication.translate("LocalMatch", "跳过已存在的歌词"))
                skip_count += 1
                continue

            try:
                lyrics = auto_fetch(info=info, min_score=self.min_score, sources=self.sources)

                if self.skip_inst_lyrics and lyrics.is_inst():
                    status = LocalMatchingStatus(LocalMatchingStatusType.SKIP_INST, i, QCoreApplication.translate("LocalMatch", "跳过纯音乐"))
                    skip_count += 1
                    continue

                lyrics_text = lyrics.to(lyrics_format=self.lyrics_format, langs=self.langs)

                save_path = None
                if info.from_cue or self.save2tag_mode != LocalMatchSave2TagMode.ONLY_TAG:
                    save_path = get_local_match_save_path(
                        save_mode=self.save_mode,
                        file_name_mode=self.file_name_mode,
                        local_info=info,
                        lyrics_format=self.lyrics_format,
                        file_name_format=self.file_name_format,
                        langs=self.langs,
                        save_root_path=self.save_root_path,
                        cloud_info=lyrics.info.songinfo,
                        song_root_path=song_root_path,
                    )
                    if isinstance(save_path, int):
                        status = LocalMatchingStatus(LocalMatchingStatusType.SAVE_FAIL, i, QCoreApplication.translate("LocalMatch", "计算歌词保存路径失败"))
                        logger.error("计算歌词保存路径失败: %s ,错误码: %s", info.artist_title(replace=True), save_path)
                        continue
                    save_path.parent.mkdir(parents=True, exist_ok=True)
                    with save_path.open("w", encoding="utf-8") as f:
                        f.write(lyrics_text)

                if self.save2tag_mode in (LocalMatchSave2TagMode.ONLY_TAG, LocalMatchSave2TagMode.BOTH) and not info.from_cue:
                    if not info.path:
                        status = LocalMatchingStatus(
                            LocalMatchingStatusType.SKIP_INST,
                            i,
                            QCoreApplication.translate("LocalMatch", "没有获取到{}的歌曲路径,无法保存到标签").format(info.artist_title(replace=True)),
                        )
                        continue
                    write_lyrics(info.path, lyrics_text, lyrics)

                status = LocalMatchingStatus(LocalMatchingStatusType.SUCCESS, i, QCoreApplication.translate("LocalMatch", "成功"), save_path)
                success_count += 1
            except MutagenError:
                status = LocalMatchingStatus(LocalMatchingStatusType.SAVE_FAIL, i, QCoreApplication.translate("LocalMatch", "保存到标签失败"))
            except TimeoutError:
                status = LocalMatchingStatus(LocalMatchingStatusType.AUTO_FETCH_FAIL, i, QCoreApplication.translate("LocalMatch", "匹配超时"))
            except LyricsNotFoundError:
                status = LocalMatchingStatus(LocalMatchingStatusType.AUTO_FETCH_FAIL, i, QCoreApplication.translate("LocalMatch", "没有匹配到歌词"))
            except (OSError, FileExistsError, FileNotFoundError):
                status = LocalMatchingStatus(LocalMatchingStatusType.SAVE_FAIL, i, QCoreApplication.translate("LocalMatch", "保存失败"))
            except Exception as e:
                logger.exception("本地匹配歌词时发生错误未知: %s", info.artist_title(replace=True))
                status = LocalMatchingStatus(
                    LocalMatchingStatusType.UNDERKNOWN_ERROR,
                    i,
                    QCoreApplication.translate("LocalMatch", "未知错误 {}".format(f"{e.__class__.__name__}: {e!s}")),
                )

        # time.sleep(random.randint(500, 1000))

        self.progress.emit("", 0, 0, status)
        self.finished.emit(total, success_count, total - success_count - skip_count, skip_count)
