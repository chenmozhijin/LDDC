# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os

from mutagen import File, FileType  # type: ignore[reportPrivateImportUsage] mutagen中的File被误定义为私有 quodlibet/mutagen#647
from mutagen.id3 import USLT  # type: ignore[reportPrivateImportUsage]
from pydub import AudioSegment
from PySide6.QtWidgets import QApplication, QFileDialog, QMessageBox, QWidget

from LDDC.backend.fetcher import get_lyrics
from LDDC.utils.enum import Source


def verify_lyrics(lyrics_text: str) -> None:
    lyrics = get_lyrics(Source.Local, use_cache=False, data=lyrics_text.encode("utf-8"))[0]
    if not lyrics.get("orig"):
        msg = "Not a verified lyrics"
        raise AssertionError(msg)


def close_msg_boxs(widget: QWidget) -> None:
    for child in widget.children():
        if isinstance(child, QMessageBox):
            child.defaultButton().click()


def select_file(widget: QWidget, path: str | list[str]) -> None:
    for child in widget.children():
        if isinstance(child, QFileDialog):
            match child.fileMode():
                case QFileDialog.FileMode.ExistingFile | QFileDialog.FileMode.Directory | QFileDialog.FileMode.AnyFile:
                    if isinstance(path, list):
                        path = path[0]
                    child.fileSelected.emit(path)
                case QFileDialog.FileMode.ExistingFiles:
                    if isinstance(path, str):
                        path = [path]
                    child.filesSelected.emit(path)

            child.accept()
            child.deleteLater()
            break
    else:
        msg = "No QFileDialog found"
        raise RuntimeError(msg)


def grab(widget: QWidget, path: str) -> None:
    app = QApplication.instance()
    if isinstance(app, QApplication):
        rect = widget.frameGeometry()
        widget.screen().grabWindow(0, rect.x(), rect.y(), rect.width(), rect.height()).save(path)
    else:
        msg = "No QApplication instance found"
        raise RuntimeError(msg)  # noqa: TRY004


def create_audio_file(path: str, audio_format: str, duration: int, tags: dict[str, str] | None = None) -> None:
    """创建音频文件

    :param path: 文件路径
    :param format: 文件格式
    :param duration: 音频时长(秒)
    """
    if not os.path.exists(os.path.dirname(path)):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    silent_audio = AudioSegment.silent(duration=duration * 1000, frame_rate=44100)
    silent_audio.export(path, format=audio_format, tags=tags)


def verify_audio_lyrics(path: str) -> None:
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
