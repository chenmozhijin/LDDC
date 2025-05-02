# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from collections.abc import Sequence

from .models import LyricInfo, SongInfo

try:
    from PySide6.QtCore import QObject

    class ErrorMsgTranslator(QObject):
        """错误信息翻译器"""

        def translate(self, msg: str) -> str:
            """翻译错误信息

            :param msg: 错误信息
            :return: 错误信息
            """
            match msg:
                case "没有可解密的数据":
                    return self.tr("没有可解密的数据")
                case "无效的加密数据类型":
                    return self.tr("无效的加密数据类型")
                case "解密失败":
                    return self.tr("解密失败")
                case "没有获取到可用的歌词":
                    return self.tr("没有获取到可用的歌词")
                case _:
                    if "请求歌词失败" in msg:
                        msg = msg.replace("请求歌词失败", self.tr("请求歌词失败"))

                    if "没有找到歌词" in msg:
                        msg = msg.replace("没有找到歌词", self.tr("没有找到歌词"))

                    if "JSON歌词数据缺少必要的键" in msg:
                        msg = msg.replace("JSON歌词数据缺少必要的键", self.tr("JSON歌词数据缺少必要的键"))

                    if "JSON歌词数据中包含值类型不正确的键" in msg:
                        msg = msg.replace("JSON歌词数据中包含值类型不正确的键", self.tr("JSON歌词数据中包含值类型不正确的键"))

                    if "JSON歌词数据中包含不正确的键" in msg:
                        msg = msg.replace("JSON歌词数据中包含不正确的键", self.tr("JSON歌词数据中包含不正确的键"))

                    if "JSON歌词数据中包含不正确的值" in msg:
                        msg = msg.replace("JSON歌词数据中包含不正确的值", self.tr("JSON歌词数据中包含不正确的值"))

                    if "不支持的歌词格式" in msg:
                        msg = msg.replace("不支持的歌词格式", self.tr("不支持的歌词格式"))

                    if "无法获取歌曲标题" in msg:
                        msg = msg.replace("无法获取歌曲标题", self.tr("无法获取歌曲标题"))

                    if "无法获取歌曲信息" in msg:
                        msg = msg.replace("无法获取歌曲信息", self.tr("无法获取歌曲信息"))

                    if "文件格式不支持" in msg:
                        msg = msg.replace("文件格式不支持", self.tr("文件格式不支持"))

                    if "获取文件信息失败" in msg:
                        msg = msg.replace("获取文件信息失败", self.tr("获取文件信息失败"))
                    if "不支持的文件格式" in msg:
                        msg = msg.replace("不支持的文件格式", self.tr("不支持的文件格式"))

                    return msg

    translator = ErrorMsgTranslator()
except ModuleNotFoundError:

    class DummyErrorMsgTranslator:
        """错误信息翻译器"""

        def translate(self, msg: str) -> str:
            """翻译错误信息

            :param msg: 错误信息
            :return: 错误信息
            """
            return msg

    translator = DummyErrorMsgTranslator()


class LDDCError(Exception):
    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class LyricsRequestError(LDDCError):
    """歌词请求错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class LyricsProcessingError(LDDCError):
    """歌词处理错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class LyricsDecryptError(LyricsProcessingError):
    """歌词解密错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class LyricsFormatError(LyricsProcessingError):
    """歌词格式错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class DecodingError(LDDCError):
    """解码错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class GetSongInfoError(LDDCError):
    """获取歌曲信息错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class FileTypeError(LDDCError):
    """文件类型错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class DropError(LDDCError):
    """拖放错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class APIError(LDDCError):
    """API调用错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class TranslateError(APIError):
    """翻译错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class APIParamsError(APIError):
    """API参数错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class APIRequestError(APIError):
    """API请求错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class LyricsNotFoundError(APIError):
    """没有歌词错误"""

    def __init__(self, msg: str, info: SongInfo | LyricInfo | None = None) -> None:
        super().__init__(translator.translate(msg))
        self.info = info


class AutoFetchError(LDDCError):
    """自动获取错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class NotEnoughInfoError(AutoFetchError):
    """信息不足错误"""

    def __init__(self, msg: str) -> None:
        super().__init__(translator.translate(msg))


class AutoFetchUnknownError(AutoFetchError):
    """自动获取未知错误"""

    def __init__(self, msg: str, excs: Sequence[Exception]) -> None:
        super().__init__(translator.translate(msg))
        self.exceptions = tuple(excs)
