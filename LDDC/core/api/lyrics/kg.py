# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: S311 S324
import hashlib
import json
import time
from base64 import b64decode
from datetime import datetime, timedelta, timezone
from typing import Literal, overload

import httpx

from LDDC.common.exceptions import APIRequestError, LyricsNotFoundError
from LDDC.common.models import APIResultList, Artist, Language, LyricInfo, Lyrics, SearchInfo, SearchType, SongInfo, SongListInfo, SongListType, Source
from LDDC.core.decryptor import krc_decrypt
from LDDC.core.parser.krc import krc2dict
from LDDC.core.parser.utils import judge_lyrics_type

from .models import CloudAPI

SEARCH_TYPE_MAPPING = {
    SearchType.SONG: ("http://complexsearch.kugou.com/v2/search/song", "SearchSong"),
    SearchType.ALBUM: ("http://complexsearch.kugou.com/v1/search/album", "SearchAlbum"),
    SearchType.SONGLIST: ("http://complexsearch.kugou.com/v1/search/special", "SearchSongRecommand"),
}

LANGUAGE_MAPPING = {
    "伴奏": Language.INSTRUMENTAL,
    "纯音乐": Language.INSTRUMENTAL,
    "英语": Language.ENGLISH,
    "韩语": Language.KOREAN,
    "日语": Language.JAPANESE,
    "粤语": Language.CHINESE,
    "国语": Language.CHINESE,
}


class KGAPI(CloudAPI):
    source = Source.KG
    supported_search_types = (SearchType.SONG, SearchType.ALBUM, SearchType.SONGLIST)

    def __init__(self) -> None:
        self.client = httpx.Client()

    def request(
        self, url: str, params: dict, module: str, method: Literal["GET", "POST"] = "GET", data: str | None = None, headers: dict | None = None,
    ) -> dict:
        headers = {
            "User-Agent": f"Android14-1070-11070-201-0-{module}-wifi",
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip, deflate",
            "KG-Rec": "1",
            "KG-RC": "1",
            "KG-CLIENTTIMEMS": str(int(time.time() * 1000)),
            **(headers if headers else {}),
        }

        # web的mid生成方式,客户端好像也能用
        # hex_str = f"{random.getrandbits(128):032x}"
        # mid = hashlib.md5(f"{hex_str[:8]}-{hex_str[8:12]}-{hex_str[12:16]}-{hex_str[16:20]}-{hex_str[20:]}".encode()).hexdigest()
        mid = hashlib.md5(b"-").hexdigest()

        if module == "Lyric":
            params = {
                "appid": "3116",
                "clientver": "11070",
                **params,
            }
        elif module == "album_song_list":
            params = {
                "dfid": "-",
                "appid": "3116",
                "mid": mid,
                "clientver": "11070",
                "clienttime": int(time.time()),
                "uuid": "-",
            }
            headers["KG-TID"] = "221"
        else:
            params = {
                "userid": "0",
                "appid": "3116",
                "token": "",
                "clienttime": int(time.time()),
                "iscorrection": "1",
                "uuid": "-",
                # "uuid": "15e772e1213bdd0718d0c1d10d64e06f",
                "mid": mid,
                "dfid": "-",
                "clientver": "11070",
                "platform": "AndroidFilter",
                **params,
            }
        headers["mid"] = mid
        params["signature"] = hashlib.md5(
            (
                "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
                + "".join([f"{k}={json.dumps(v) if isinstance(v, dict) else v}" for k, v in sorted(params.items())])
                + (data or "")
                + "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
            ).encode(),
        ).hexdigest()

        response = (
            self.client.get(url, params=params, headers=headers) if method == "GET" else self.client.post(url, params=params, headers=headers, content=data)
        )
        response.raise_for_status()
        response_data = response.json()
        if response_data.get("error_code", 0) not in (0, 200):
            raise APIRequestError("kg API请求错误,错误码:" + str(response_data.get("error_code")))
        return response_data

    @overload
    def search(self, keyword: str, search_type: Literal[SearchType.SONG], page: int = 1) -> APIResultList[SongInfo]: ...

    @overload
    def search(
        self,
        keyword: str,
        search_type: Literal[SearchType.SONGLIST, SearchType.ALBUM],
        page: int = 1,
    ) -> APIResultList[SongListInfo]: ...

    def search(self, keyword: str, search_type: SearchType, page: int = 1) -> APIResultList[SongInfo] | APIResultList[SongListInfo]:
        pagesize = 20
        params = {
            "sorttype": "0",
            "keyword": keyword,
            "pagesize": pagesize,  # 客户端30
            "page": page,
        }
        url, module = SEARCH_TYPE_MAPPING[search_type]
        data = self.request(url, params, module, headers={"x-router": "complexsearch.kugou.com"})

        if not data["data"]["lists"]:
            return APIResultList(
                [],
                SearchInfo(
                    source=self.source,
                    keyword=keyword,
                    search_type=search_type,
                    page=page,
                ),
                (0, 0, 0),
            )

        start_index = (page - 1) * pagesize
        match search_type:
            case SearchType.SONG:
                return APIResultList(
                    [
                        SongInfo(
                            source=self.source,
                            id=info["ID"],
                            hash=info["FileHash"],
                            title=info["SongName"],
                            subtitle=info["Auxiliary"],
                            artist=Artist(singer["name"] for singer in info["Singers"] if singer["name"] != ""),
                            album=info["AlbumName"],
                            duration=info["Duration"] * 1000,
                            language=LANGUAGE_MAPPING.get(info["trans_param"].get("language"), Language.OTHER),
                        )
                        for info in data["data"]["lists"]
                    ],
                    SearchInfo(
                        source=self.source,
                        keyword=keyword,
                        search_type=search_type,
                        page=page,
                    ),
                    (
                        start_index,
                        start_index + len(data["data"]["lists"]) - 1,
                        data["data"]["total"] if len(data["data"]["lists"]) == pagesize else start_index + len(data["data"]["lists"]),
                    ),
                )

            case SearchType.ALBUM:
                return APIResultList(
                    [
                        SongListInfo(
                            source=self.source,
                            type=SongListType.ALBUM,
                            id=info["albumid"],
                            title=info["albumname"],
                            imgurl=info["img"],
                            songcount=info["songcount"],
                            publishtime=int(
                                datetime.strptime(info["publish_time"], "%Y-%m-%d")
                                .replace(tzinfo=timezone(timedelta(hours=8)))
                                .astimezone(timezone.utc)
                                .timestamp(),
                            )
                            if info["publish_time"] != "0000-00-00"
                            else None,
                            author=info["singer"],
                        )
                        for info in data["data"]["lists"]
                    ],
                    SearchInfo(
                        source=self.source,
                        keyword=keyword,
                        search_type=search_type,
                        page=page,
                    ),
                    (
                        start_index,
                        start_index + len(data["data"]["lists"]) - 1,
                        data["data"]["total"] if len(data["data"]["lists"]) == pagesize else start_index + len(data["data"]["lists"]),
                    ),
                )

            case SearchType.SONGLIST:
                return APIResultList(
                    [
                        SongListInfo(
                            source=self.source,
                            type=SongListType.SONGLIST,
                            id=info["gid"],
                            title=info["specialname"],
                            imgurl=info["img"],
                            songcount=info["song_count"],
                            publishtime=int(
                                datetime.strptime(info["publish_time"], "%Y-%m-%d %H:%M:%S")
                                .replace(tzinfo=timezone(timedelta(hours=8)))
                                .astimezone(timezone.utc)
                                .timestamp(),
                            ),
                            author=info["nickname"],
                        )
                        for info in data["data"]["lists"]
                    ],
                    SearchInfo(
                        source=self.source,
                        keyword=keyword,
                        search_type=search_type,
                        page=page,
                    ),
                    (
                        start_index,
                        start_index + len(data["data"]["lists"]) - 1,
                        data["data"]["total"] if len(data["data"]["lists"]) == pagesize else start_index + len(data["data"]["lists"]),
                    ),
                )

            case _:
                raise NotImplementedError

    def get_songlist(self, songlist_info: SongListInfo) -> APIResultList[SongInfo]:
        match songlist_info.type:
            case SongListType.ALBUM:
                data = {
                    "pagesize": "2147483647",  # 不知道最大是多少,先这样算啦
                    "album_id": songlist_info.id,
                    "page": "1",
                }
                url = "http://openapi.kugou.com/kmr/v1/album_songlist"
                songs = self.request(url, {}, "album_song_list", "POST", json.dumps(data, indent=4))["data"]["songs"]
                return APIResultList(
                    [
                        SongInfo(
                            source=self.source,
                            id=str(info["base"]["album_audio_id"]),
                            hash=info["audio_info"]["hash"],
                            title=info["base"]["audio_name"].removesuffix(info["trans_param"].get("songname_suffix", "")),
                            subtitle=info["trans_param"].get("songname_suffix", ""),
                            artist=Artist(info["base"]["author_name"].split("、")),
                            album=info["album_info"]["album_name"],
                            duration=info["audio_info"]["duration"],
                            language=LANGUAGE_MAPPING.get(info["trans_param"].get("language"), Language.OTHER),
                        )
                        for info in songs
                    ],
                    songlist_info,
                    (0, len(songs) - 1, len(songs)),
                )
            case SongListType.SONGLIST:
                param = {
                    "specialid": songlist_info.id,
                    "need_sort": "1",
                    "module": "CloudMusic",
                    "pagesize": "-1",
                    "global_collection_id": songlist_info.id,
                    "page": "1",
                    "type": "0",
                }
                url = "https://pubsongscdn.kugou.com/v4/get_other_list_file"
                songs = self.request(url, param, "SongList")["data"]["info"]
                return APIResultList(
                    [
                        SongInfo(
                            source=self.source,
                            id=str(info["mixsongid"]),
                            hash=info["hash"],
                            title=info["name"].split(" - ")[1],
                            subtitle=info["remark"],
                            artist=Artist(singer["name"] for singer in info["singerinfo"] if singer["name"] != ""),
                            album=info["albuminfo"]["name"],
                            duration=info["timelen"],
                            language=LANGUAGE_MAPPING.get(info["trans_param"].get("language"), Language.OTHER),
                        )
                        for info in songs
                    ],
                    songlist_info,
                    (0, len(songs) - 1, len(songs)),
                )
            case _:
                raise NotImplementedError

    def get_lyrics(self, info: SongInfo | LyricInfo) -> Lyrics:
        if isinstance(info, SongInfo):
            infos = self.get_lyricslist(info)
            if not infos:
                msg = "没有找到歌词"
                raise LyricsNotFoundError(msg, info)
            info = infos[0]

        params = {
            "accesskey": info.accesskey,
            "charset": "utf8",
            "client": "mobi",
            "fmt": "krc",
            "id": info.id,
            "ver": "1",
        }
        url = "http://lyrics.kugou.com/download"
        data = self.request(url, params, "Lyric")
        # data['contenttype'] == 2 无法解密
        lyrics = Lyrics(info.songinfo)
        lyrics.tags, lyric = krc2dict(krc_decrypt(b64decode(data["content"])))
        lyrics.update(lyric)
        for key, lyric in lyrics.items():
            lyrics.types[key] = judge_lyrics_type(lyric)
        return lyrics

    def get_lyricslist(self, song_info: SongInfo) -> list[LyricInfo]:
        params = {
            "album_audio_id": song_info.id,
            "duration": song_info.duration,  # 毫秒
            "hash": song_info.hash,
            "keyword": f"{'、'.join(song_info.artist) if isinstance(song_info.artist, list) else (song_info.artist or '')} - {song_info.title}",
            "lrctxt": "1",
            "man": "no",
        }
        url = "https://lyrics.kugou.com/v1/search"
        data = self.request(url, params, "Lyric")
        return [
            LyricInfo(
                source=self.source,
                id=lyric["id"],
                accesskey=lyric["accesskey"],
                creator=lyric["nickname"],
                duration=lyric["duration"],
                score=lyric["score"],
                songinfo=song_info,
            )
            for lyric in data["candidates"]
        ]
