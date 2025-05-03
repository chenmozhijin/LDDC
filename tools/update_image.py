# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import shutil
from pathlib import Path

import pytest
from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QImage, QPainter

from LDDC.common.data.config import cfg

img_path = Path(__file__).parent.parent / "img"
tests_path = Path(__file__).parent.parent / "tests"
test_artifacts_path = tests_path / "artifacts"
screenshot_path = test_artifacts_path / "screenshots"


def get_image_path(image_name: str) -> str:
    return str(screenshot_path / (image_name + ".png"))


def stitch_images_grid(image_names: list[str], rows: int, cols: int) -> QImage:
    image_paths = [get_image_path(image_name) for image_name in image_names]
    if len(image_paths) != rows * cols:
        msg = "图片数量与网格尺寸不匹配！"
        raise ValueError(msg)

    # 加载所有图片
    images = [QImage(path) for path in image_paths]

    # 获取单个图片的宽高(假设所有图片尺寸相同)
    image_width = max(image.width() for image in images)
    image_height = max(image.height() for image in images)

    # 计算拼接后的网格图片尺寸
    total_width = cols * image_width
    total_height = rows * image_height

    # 创建目标图片
    result = QImage(total_width, total_height, QImage.Format.Format_ARGB32)
    result.fill(0)  # 透明背景

    # 使用 QPainter 进行拼接
    painter = QPainter(result)
    for row in range(rows):
        for col in range(cols):
            index = row * cols + col
            x_offset = col * image_width
            y_offset = row * image_height
            painter.drawImage(x_offset, y_offset, images[index])
    painter.end()

    return result


orig_lang = cfg["language"]
for lang in ("zh-Hans", "zh-Hant", "en", "ja"):
    cfg["language"] = lang
    pytest.main(["--not-clear-cache", "--language", lang, "-v", "-k", "test_gui_", "tests/"])
    lang_screenshot_path = tests_path / "screenshots" / lang
    if lang_screenshot_path.exists():
        shutil.rmtree(lang_screenshot_path)
    shutil.copytree(screenshot_path, lang_screenshot_path)
    image1 = stitch_images_grid(
        ["preview_verbatimlrc", "preview_ass", "preview_linebylinelrc", "preview_srt", "preview_enhancedlrc", "save_album_lyrics"],
        3,
        2,
    )

    setting = QImage(get_image_path("setting"))
    open_lyrics_krc = QImage(get_image_path("open_lyrics_krc"))
    open_lyrics_qrc = QImage(get_image_path("open_lyrics_qrc"))
    setting_width = setting.width() * ((open_lyrics_krc.height() + open_lyrics_qrc.height()) / setting.height())
    image2 = QImage(int(setting_width) + open_lyrics_krc.width(), open_lyrics_krc.height() + open_lyrics_qrc.height(), QImage.Format.Format_ARGB32)
    image2.fill(Qt.GlobalColor.transparent)  # 透明背景
    painter = QPainter(image2)
    painter.drawImage(QRectF(open_lyrics_krc.width(), 0, setting_width, open_lyrics_krc.height() + open_lyrics_qrc.height()), setting)
    painter.drawImage(0, 0, open_lyrics_qrc)
    painter.drawImage(0, open_lyrics_krc.height(), open_lyrics_qrc)
    painter.end()

    image1.save(str(img_path / f"{lang}_1.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]
    image2.save(str(img_path / f"{lang}_2.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]
    QImage(get_image_path("local_match_finish_FORMAT_BY_LYRICS_ONLY_FILE_FORMAT_BY_LYRICS")).save(str(img_path / f"{lang}_3.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]

    desktop_lyrics_img = QImage(get_image_path("desktop_lyrics_playing_with_control_bar"))
    desktop_lyrics_selector_img = QImage(get_image_path("desktop_lyrics_selector"))
    manager_img = QImage(get_image_path("desktop_lyrics_db_manager"))
    height = int(manager_img.height() * 0.5 + desktop_lyrics_selector_img.height())
    width = int(manager_img.width() * 0.5 + desktop_lyrics_selector_img.width())
    image4 = QImage(width, height, QImage.Format.Format_ARGB32)
    image4.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image4)
    painter.drawImage(width - manager_img.width(), 0, manager_img)
    painter.drawImage(0, manager_img.height() // 2, desktop_lyrics_selector_img)
    painter.drawImage(0, height - desktop_lyrics_selector_img.height() // 2, desktop_lyrics_img)
    image4.save(str(img_path / f"{lang}_4.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]

    QImage(get_image_path("batch_convert_before_VERBATIMLRC")).save(str(img_path / f"{lang}_5.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]


cfg["language"] = orig_lang
