from enum import Enum


class QrcType(Enum):
    LOCAL = 0
    CLOUD = 1


class LyricsType(Enum):
    PlainText = 0
    JSONVERBATIM = 1
    JSONLINE = 2
    LRC = 3
    QRC = 4
    KRC = 5
    YRC = 6


class LyricsProcessingError(Enum):
    REQUEST = 0
    DECRYPT = 1
    NOT_FOUND = 2
    UNSUPPORTED = 3


class LyricsFormat(Enum):
    VERBATIMLRC = 0
    LINEBYLINELRC = 1
    ENHANCEDLRC = 2
    SRT = 3
    ASS = 4


class SearchType(Enum):
    SONG = 0
    ARTIST = 1
    ALBUM = 2
    SONGLIST = 3
    LYRICS = 7


class Source(Enum):
    QM = 1
    KG = 2
    NE = 3

    # 定义 Source 类的序列化方法
    def __json__(self, obj: any) -> str:
        if isinstance(obj, Source):
            return str(obj.name)
        msg = f"Object of type {obj.__class__.__name__} is not JSON serializable"
        raise TypeError(msg)


class LocalMatchSaveMode(Enum):
    # 镜像/歌曲/指定
    MIRROR = 0
    SONG = 1
    SPECIFY = 2


class LocalMatchFileNameMode(Enum):
    # 歌曲/格式
    SONG = 0
    FORMAT = 1
