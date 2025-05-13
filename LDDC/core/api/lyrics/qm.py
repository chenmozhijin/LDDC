# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: S311
import json
import random
import time
from base64 import b64encode
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Literal, overload

import httpx

from LDDC.common.exceptions import APIParamsError, APIRequestError
from LDDC.common.models import (
    APIResultList,
    Artist,
    Language,
    LyricInfo,
    Lyrics,
    QrcType,
    SearchInfo,
    SearchType,
    SongInfo,
    SongListInfo,
    SongListType,
    Source,
)
from LDDC.core.decryptor import qrc_decrypt
from LDDC.core.parser.qrc import qrc_str_parse
from LDDC.core.parser.utils import judge_lyrics_type

from .models import CloudAPI

SEARCH_TYPE_MAPPING = {
    SearchType.SONG: 0,
    SearchType.ARTIST: 1,
    SearchType.ALBUM: 2,
    SearchType.SONGLIST: 3,
}

LANGUAGE_MAPPING = {
    9: Language.INSTRUMENTAL,
    5: Language.ENGLISH,
    4: Language.KOREAN,
    3: Language.JAPANESE,
    1: Language.CHINESE,  # 粤语
    0: Language.CHINESE,  # 汉语
}


class QMAPI(CloudAPI):
    source = Source.QM
    supported_search_types = (SearchType.SONG, SearchType.ALBUM, SearchType.SONGLIST)

    def __init__(self) -> None:
        self.client = httpx.Client(
            headers={
                "cookie": "tmeLoginType=-1;",
                "content-type": "application/json",
                "accept-encoding": "gzip",
                "user-agent": "okhttp/3.14.9",
            },
            http2=True,
        )
        self.comm = {
            "ct": 11,
            "cv": "1003006",
            "v": "1003006",
            # "QIMEI36": ""
            # "QIMEI": "",
            "os_ver": "15",
            "phonetype": "24122RKC7C",  # REDMI K80 Pro https://mifirm.net/model/miro.ttt
            "rom": f"Redmi/miro/miro:15/AE3A.240806.005/OS2.0.10{random.choice(['5', '4', '2'])}.0.VOMCNXM:user/release-keys",
            # "aid"
            "tmeAppID": "qqmusiclight",
            "nettype": "NETWORK_WIFI",
            # "uid"
            # "sid"
            # "userip"
            "udid": "0",
        }
        self.inited = False
        self.init_lock = Lock()
        self.init()

    def init(self) -> None:
        with self.init_lock:
            if self.inited:
                return
            param = {"caller": 0, "uid": "0", "vkey": 0}
            data = self.request("GetSession", "music.getSession.session", param)
            self.comm = {
                **self.comm,
                "uid": data["session"]["uid"],
                "sid": data["session"]["sid"],
                "userip": data["session"]["userip"],
            }

    def request(self, method: str, module: str, param: dict) -> dict:
        """请求API

        Args:
            method (str): 请求方法
            module (str): 请求模块
            param (dict): 请求参数

        Returns:
            dict: 响应数据

        """
        if not self.inited and method != "GetSession":
            self.init()
        data = json.dumps(
            {
                "comm": self.comm,
                "request": {
                    "method": method,
                    "module": module,
                    "param": param,
                },
            },
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        domains = [
            # "lite.y.qq.com",
            # "u6.y.qq.com",
            # "shu6.y.qq.com",
            "u.y.qq.com",
        ]
        response = self.client.post(
            f"https://{random.choice(domains)}/cgi-bin/musicu.fcg",
            content=data,
        )
        response.raise_for_status()
        response_data = response.json()
        if response_data["code"] != 0 or response_data["request"]["code"] != 0:
            raise APIRequestError("qm API请求错误,错误码:" + str(response_data["code"] if response_data["code"] != 0 else response_data["request"]["code"]))
        return response_data["request"]["data"]

    def format_songinfos(self, songinfos: list) -> list[SongInfo]:
        return [
            SongInfo(
                source=self.source,
                id=str(info["id"]),
                mid=info["mid"],
                title=info["title"],
                subtitle=info["subtitle"],
                artist=Artist(singer["name"] for singer in info["singer"] if singer["name"] != ""),
                album=info["album"]["name"],
                duration=info["interval"] * 1000,
                language=LANGUAGE_MAPPING.get(info["language"], Language.OTHER),
            )
            for info in songinfos
        ]

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
        """搜索歌曲

        Args:
            keyword (str): 搜索关键词
            search_type (SearchType): 搜索类型
            page (int, optional): 页码. Defaults to 1.

        Returns:
            list[SongInfo] | list[SongListInfo]: 搜索结果

        """
        pagesize = 20
        param = {
            "search_id": str(random.randint(1, 20) * 18014398509481984 + random.randint(0, 4194304) * 4294967296 + round(time.time() * 1000) % 86400000),
            "remoteplace": "search.android.keyboard",
            "query": keyword,
            "search_type": SEARCH_TYPE_MAPPING[search_type],
            "num_per_page": pagesize,
            "page_num": page,
            "highlight": 0,
            "nqc_flag": 0,
            "page_id": 1,
            "grp": 1,
        }
        data = self.request(
            "DoSearchForQQMusicLite" if search_type != SearchType.ALBUM else "DoSearchForQQMusicDesktop",
            "music.search.SearchCgiService",
            param,
        )

        start_index = (page - 1) * pagesize
        match search_type:
            case SearchType.SONG:
                return APIResultList(
                    self.format_songinfos(data["body"]["item_song"]),
                    SearchInfo(
                        source=self.source,
                        keyword=keyword,
                        search_type=search_type,
                        page=page,
                    ),
                    (
                        start_index,
                        start_index + len(data["body"]["item_song"]) - 1,
                        data["meta"]["sum"] if len(data["body"]["item_song"]) == pagesize else start_index + len(data["body"]["item_song"]),
                    ),
                )

            case SearchType.ALBUM:
                return APIResultList(
                    [
                        SongListInfo(
                            source=self.source,
                            type=SongListType.ALBUM,
                            id=str(album["albumID"]),
                            mid=album["albumMID"],
                            title=album["albumName"],
                            imgurl=album["albumPic"],
                            songcount=album["song_count"],
                            publishtime=int(
                                datetime.strptime(album["publicTime"], "%Y-%m-%d")
                                .replace(tzinfo=timezone(timedelta(hours=8)))
                                .astimezone(timezone.utc)
                                .timestamp(),
                            ),
                            author=album["singerName"],
                        )
                        for album in data["body"]["album"]["list"]
                    ],
                    SearchInfo(
                        source=self.source,
                        keyword=keyword,
                        search_type=search_type,
                        page=page,
                    ),
                    (
                        start_index,
                        start_index + len(data["body"]["album"]["list"]) - 1,
                        data["meta"]["sum"] if len(data["body"]["album"]["list"]) == pagesize else start_index + len(data["body"]["album"]["list"]),
                    ),
                )

            # Lite版的结果处理
            #  return APIResultList(
            #          [
            #              SongListInfo(
            #                  source=self.source,
            #                  type=SongListType.ALBUM,
            #                  id=album["id"],
            #                  mid=album["albummid"],
            #                  title=album["name"],
            #                  imgurl=album["pic"],
            #                  songcount=None,
            #                  publishtime=int(
            #                      datetime.strptime(album["publish_date"], "%Y-%m-%d")
            #                      .replace(tzinfo=timezone(timedelta(hours=8)))
            #                      .astimezone(timezone.utc)
            #                      .timestamp(),
            #                  ),
            #                  author=album["singer"],
            #              )
            #              for album in data["body"]["item_album"]
            #          ],
            #          SearchInfo(
            #              source=self.source,
            #              keyword=keyword,
            #              search_type=search_type,
            #              page=page,
            #          ),
            #          (
            #              start_index,
            #              start_index + len(data["body"]["item_album"]) - 1,
            #              data["meta"]["sum"] if len(data["body"]["item_album"]) == pagesize else start_index + len(data["body"]["item_album"]),
            #          ),
            #      )

            case SearchType.SONGLIST:
                return APIResultList(
                    [
                        SongListInfo(
                            source=self.source,
                            type=SongListType.SONGLIST,
                            id=str(songlist["dissid"]),
                            title=songlist["dissname"],
                            imgurl=songlist["logo"],
                            songcount=songlist["songnum"],
                            publishtime=int(
                                datetime.strptime(songlist["createtime"], "%Y-%m-%d")
                                .replace(tzinfo=timezone(timedelta(hours=8)))
                                .astimezone(timezone.utc)
                                .timestamp(),
                            ),
                            author=songlist["nickname"],
                        )
                        for songlist in data["body"]["item_songlist"]
                    ],
                    SearchInfo(
                        source=self.source,
                        keyword=keyword,
                        search_type=search_type,
                        page=page,
                    ),
                    (
                        start_index,
                        start_index + len(data["body"]["item_songlist"]) - 1,
                        data["meta"]["sum"] if len(data["body"]["item_songlist"]) == pagesize else start_index + len(data["body"]["item_songlist"]),
                    ),
                )

            case _:
                raise NotImplementedError

    def get_songlist(self, songlist_info: SongListInfo) -> APIResultList[SongInfo]:
        match songlist_info.type:
            case SongListType.ALBUM:
                param = {"albumID": int(songlist_info.id), "order": 2, "begin": 0, "num": -1}
                songs = [song["songInfo"] for song in self.request("GetAlbumSongList", "music.musichallAlbum.AlbumSongList", param)["songList"]]
            case SongListType.SONGLIST:
                param = {
                    "disstid": int(songlist_info.id),
                    "dirid": 0,
                    "onlysonglist": 0,
                    "song_begin": 0,
                    "song_num": -1,
                    "userinfo": 1,
                    "pic_dpi": 800,
                    "orderlist": 1,
                }
                songs = self.request("CgiGetDiss", "srf_diss_info.DissInfoServer", param)["songlist"]
            case _:
                raise NotImplementedError
        return APIResultList(self.format_songinfos(songs), songlist_info, (0, len(songs) - 1, len(songs)))

    def get_lyrics(self, info: SongInfo) -> Lyrics:
        """获取歌词

        Args:
            info (SongInfo): 歌曲信息

        Returns:
            Lyrics: 歌词

        """
        if info.title is None or info.album is None or not info.id or info.duration is None:
            msg = "缺少必要参数"
            raise APIParamsError(msg)

        param = {
            "albumName": b64encode(info.album.encode()).decode(),
            "crypt": 1,
            "ct": 19,
            "cv": 2111,
            "interval": info.duration // 1000,  # 单位为秒
            "lrc_t": 0,
            "qrc": 1,
            "qrc_t": 0,
            "roma": 1,
            "roma_t": 0,
            "singerName": b64encode(str(info.artist).encode()).decode() if info.artist else b64encode(b"").decode(),
            "songID": int(info.id),
            "songName": b64encode(info.title.encode()).decode(),
            "trans": 1,
            "trans_t": 0,
            "type": 0,
        }

        response = self.request("GetPlayLyricInfo", "music.musichallSong.PlayLyricInfo", param)
        lyrics = Lyrics(info)
        for key, value in [("orig", "lyric"), ("ts", "trans"), ("roma", "roma")]:
            lrc = response[value]
            lrc_t = (response["qrc_t"] if response["qrc_t"] != 0 else response["lrc_t"]) if value == "lyric" else response[value + "_t"]
            if lrc != "" and lrc_t != "0":
                encrypted_lyric = lrc

                lyric = qrc_decrypt(encrypted_lyric, QrcType.CLOUD)

                if lyric is not None:
                    tags, lyric = qrc_str_parse(lyric)

                    if key == "orig":
                        lyrics.tags = tags

                    lyrics[key] = lyric
                    lyrics.types[key] = judge_lyrics_type(lyric)
        return lyrics

    def get_lyricslist(self, song_info: SongInfo) -> list[LyricInfo]:
        raise NotImplementedError
