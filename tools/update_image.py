# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: INP001
import os

import pytest
from PySide6.QtCore import QRectF
from PySide6.QtGui import QImage, QPainter

from LDDC.utils.data import cfg

img_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "img")
tests_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tests")
test_artifacts_path = os.path.join(tests_path, "artifacts")
screenshot_path = os.path.join(test_artifacts_path, "screenshots")


def get_image_path(image_name: str) -> str:
    return os.path.join(screenshot_path, image_name + ".png")


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
for index, lang in enumerate(("zh-Hans", "zh-Hant", "en", "ja"), start=1):
    cfg["language"] = lang
    pytest.main(["--not-clear-cache"])
    image1 = stitch_images_grid(["preview_verbatimlrc", "preview_ass",
                                 "preview_linebylinelrc", "preview_srt",
                                 "preview_enhancedlrc", "save_album_lyrics"], 3, 2)

    setting = QImage(get_image_path("setting"))
    open_lyrics_krc = QImage(get_image_path("open_lyrics_krc"))
    open_lyrics_qrc = QImage(get_image_path("open_lyrics_qrc"))
    setting_width = setting.width() * ((open_lyrics_krc.height() + open_lyrics_qrc.height()) / setting.height())
    image2 = QImage(int(setting_width) + open_lyrics_krc.width(), open_lyrics_krc.height() + open_lyrics_qrc.height(), QImage.Format.Format_ARGB32)
    image2.fill(0)  # 透明背景
    painter = QPainter(image2)
    painter.drawImage(QRectF(open_lyrics_krc.width(), 0,
                             setting_width,
                             open_lyrics_krc.height() + open_lyrics_qrc.height()), setting)
    painter.drawImage(0, 0, open_lyrics_qrc)
    painter.drawImage(0, open_lyrics_krc.height(), open_lyrics_qrc)
    painter.end()

    image1.save(os.path.join(img_path, f"{lang}_1.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]
    image2.save(os.path.join(img_path, f"{lang}_2.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]
    QImage(get_image_path("local_match_finish_FORMAT_ONLY_FILE_MIRROR")).save(os.path.join(img_path, f"{lang}_3.jpg"), "JPG", 20)  # type: ignore[reportCallIssue]

    from LDDC.view.main_window import main_window
    main_window.settings_widget.language_comboBox.setCurrentIndex(index + 1)
cfg["language"] = orig_lang
