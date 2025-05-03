# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Literal

from mutagen import File, FileType  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
from mutagen.easyid3 import EasyID3
from mutagen.id3 import ID3, USLT  # type: ignore[reportPrivateImportUsage]
from pydub import AudioSegment
from PySide6.QtCore import QPoint
from PySide6.QtWidgets import QApplication, QFileDialog, QMessageBox, QWidget

from LDDC.core.api.lyrics import get_lyrics

tmp_dirs: list[TemporaryDirectory] = []
test_artifacts_path = Path(__file__).parent / "artifacts"
screenshot_path = test_artifacts_path / "screenshots"
tmp_dir_root = test_artifacts_path / "tmp"


def get_tmp_dir() -> Path:
    directory = TemporaryDirectory(dir=tmp_dir_root)
    tmp_dirs.append(directory)
    return Path(directory.name)


def verify_lyrics(lyrics_text: str) -> None:
    lyrics = get_lyrics(data=lyrics_text)
    if not lyrics.get("orig"):
        msg = "Not a verified lyrics"
        raise AssertionError(msg)


def close_msg_boxs(widget: QWidget) -> None:
    for child in widget.children():
        if isinstance(child, QMessageBox):
            child.defaultButton().click()


def select_file(widget: QWidget, path: str | list[str] | Path | list[Path]) -> None:
    for child in widget.children():
        if isinstance(child, QFileDialog):
            if child.property("opened"):
                continue
            match child.fileMode():
                case QFileDialog.FileMode.ExistingFile | QFileDialog.FileMode.Directory | QFileDialog.FileMode.AnyFile:
                    if isinstance(path, list):
                        path = path[0]
                    child.fileSelected.emit(str(path))
                case QFileDialog.FileMode.ExistingFiles:
                    if isinstance(path, str):
                        path = [path]
                    child.filesSelected.emit(str(path))

            child.accept()
            child.deleteLater()
            child.setProperty("opened", True)
            break
    else:
        msg = "No QFileDialog found"
        raise RuntimeError(msg)


def grab(widget: QWidget, path: Path | str, method: Literal["screen", "widget"] = "screen") -> None:
    """截图

    Args:
        widget (QWidget): 截图对象
        path (str): 保存路径
        method (Literal["screen", "widget"]): 截图方式

    """
    app = QApplication.instance()
    screenshot_origin_global_pos = None
    if isinstance(app, QApplication):
        if method == "screen":
            rect = widget.frameGeometry()
            widget.screen().grabWindow(0, rect.x(), rect.y(), rect.width(), rect.height()).save(str(path) + ".png")
            screenshot_origin_global_pos = rect.topLeft()
        elif method == "widget":
            widget.grab().save(str(path) + ".png")

        rects = {}

        recorded_widget = []

        def get_rects(w: QWidget, prefix: str = "") -> None:
            for name, obj in w.__dict__.items():
                if isinstance(obj, QWidget) and obj.isVisible() and obj not in recorded_widget:
                    recorded_widget.append(obj)
                    rect = obj.geometry()
                    pos = obj.mapToGlobal(QPoint(0, 0)) - screenshot_origin_global_pos if screenshot_origin_global_pos else rect.topLeft()
                    full_name = name if not prefix else f"{prefix}.{name}"
                    rects[full_name] = (
                        pos.x() * obj.devicePixelRatioF(),
                        pos.y() * obj.devicePixelRatioF(),
                        rect.width() * obj.devicePixelRatioF(),
                        rect.height() * obj.devicePixelRatioF(),
                    )
                    get_rects(obj, full_name)

        get_rects(widget)

        with Path(str(path) + ".json").open("w") as f:
            json.dump(rects, f, indent=4, ensure_ascii=False)
    else:
        msg = "No QApplication instance found"
        raise RuntimeError(msg)  # noqa: TRY004


def create_audio_file(path: Path, audio_format: str, duration: int, tags: dict[str, str] | None = None) -> None:
    """创建音频文件

    :param path: 文件路径
    :param format: 文件格式
    :param duration: 音频时长(秒)
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    silent_audio = AudioSegment.silent(duration=duration * 1000, frame_rate=44100)
    silent_audio.export(path, format=audio_format)
    if tags:
        audio = File(path, easy=True)
        if isinstance(audio, FileType):
            if audio.tags is None:
                audio.add_tags()

            if isinstance(audio.tags, ID3):
                # 对于ID3类型的标签(wave文件),使用mutagen.easyid3.EasyID3来转换
                easy_tags = EasyID3()
                for tag, value in tags.items():
                    easy_tags[tag] = value
                id3: ID3 = easy_tags._EasyID3__id3  # id3是EasyID3的一个私有变量  # type: ignore[reportAttributeAccessIssue]  # noqa: SLF001
                for value in id3.values():
                    audio.tags.add(value)
            else:
                for tag, value in tags.items():
                    audio[tag] = value

            audio.save()


def verify_audio_lyrics(path: str | Path) -> None:
    audio = File(path)
    count = 0

    if audio and isinstance(audio, FileType):
        if not audio.tags:
            msg = f"No tags found in audio file: {path}"
            raise AssertionError(msg)

        for tag in audio:
            if tag in ["lyrics", "Lyrics", "WM/LYRICS", "©lyr", "LYRICS", "USLT"] or (isinstance(tag, str) and tag.startswith("USLT")):
                try:
                    t = audio[tag]
                    if isinstance(t, USLT):
                        verify_lyrics(t.text)
                    else:
                        verify_lyrics(t[0])
                    count += 1
                except ValueError:
                    pass

    if count == 0:
        msg = f"No lyrics found in audio file: {path}"
        raise AssertionError(msg)
