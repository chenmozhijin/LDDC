# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import logging
import random
import re
import time
from base64 import b64decode
from enum import Enum

import requests
from bs4 import BeautifulSoup


def get_latest_version() -> tuple[bool, str]:
    try:
        latest_release = requests.get("https://api.github.com/repos/chenmozhijin/LDDC/releases/latest", timeout=5).json()
    except Exception as e:
        logging.exception("获取最新版本信息时错误")
        return False, str(e)
    else:
        if "tag_name" in latest_release:
            latest_version = latest_release["tag_name"]
            return True, latest_version
        return False, "获取最新版本信息失败"


class SearchType(Enum):
    SONG = 0
    ARTIST = 1
    ALBUM = 2
    SONGLIST = 3
    LYRICS = 7


class Source(Enum):
    QM = 0
    KG = 1

    # 定义 Source 类的序列化方法
    def __json__(self, obj: any) -> str:
        if isinstance(obj, Source):
            return str(obj.name)
        msg = f"Object of type {obj.__class__.__name__} is not JSON serializable"
        raise TypeError(msg)


json.JSONEncoder.default = Source.__json__


QMD_headers = {
    "Accept": "*/*",
    "Accept-Encoding": "gzip, deflate",
    "Accept-Language": "zh-CN",
    "User-Agent": "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)",
}


def qmsonglist2result(songlist: list, list_type: str | None = None) -> list:
    results = []
    for song in songlist:
        info = song["songInfo"] if list_type == "album" else song
        # 处理艺术家
        artist = ""
        for singer in info['singer']:
            if artist != "":
                artist += "/"
            artist += singer['name']
        results.append({
            'id': info['id'],
            'mid': info['mid'],
            'title': info['title'],
            'subtitle': info['subtitle'],
            'artist': artist,
            'album': info['album']['name'],
            'duration': info['interval'],
            'source': Source.QM,
        })
    return results


def kgsonglist2result(songlist: list, list_type: str = "search") -> list:
    results = []

    for song in songlist:
        match list_type:
            case "songlist":
                title = song['filename'].split("-")[1].strip()
                artist = song['filename'].split("-")[0].strip()
                album = ""
            case "search":
                title = song['songname']
                album = song['album_name']
                artist = song['singername']
        results.append({
            'hash': song['hash'],
            'title': title,
            'subtitle': "",
            'duration': song['duration'],
            'artist': artist,
            'album': album,
            'language': song['trans_param'].get('language', ''),
            'source': Source.KG,
        })
    return results


def get_qrc(songid: str) -> str | requests.Response:
    params = {
        'version': '15',
        'miniversion': '82',
        'lrctype': '4',
        'musicid': songid,
    }
    try:
        response = requests.get('https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg',
                                headers=QMD_headers,
                                params=params,
                                timeout=10)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logging.exception("请求qrc 歌词时错误")
        return str(e)
    else:
        logging.debug(f"请求qrc 歌词成功：{songid}, {response.text.strip()}")
    return response


def qm_get_lyric(mid: str) -> tuple[str | None, str | None] | str:
    url = 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg'
    headers = {
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
        'Referer': 'https://y.qq.com/',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 13_3_1 like Mac OS X; zh-CN) AppleWebKit/537.51.1 ('
        'KHTML, like Gecko) Mobile/17D50 UCBrowser/12.8.2.1268 Mobile AliApp(TUnionSDK/0.1.20.3) ',
    }
    params = {
        '_': int(time.time()),
        'cv': '4747474',
        'ct': '24',
        'format': 'json',
        'inCharset': 'utf-8',
        'outCharset': 'utf-8',
        'notice': '0',
        'platform': 'yqq.json',
        'needNewCode': '1',
        'g_tk': '5381',
        'songmid': mid,
    }
    try:
        response = requests.get(url, params=params, headers=headers, timeout=10)
        response.raise_for_status()
        response_json = response.json()
        if 'lyric' not in response_json or 'trans' not in response_json:
            return f'获取歌词失败, code: {response_json["code"]}'
        orig_base64 = response_json['lyric']
        ts_base64 = response_json['trans']
        orig = b64decode(orig_base64).decode("utf-8") if orig_base64 else None
        ts = b64decode(ts_base64).decode("utf-8") if ts_base64 else None
    except Exception as e:
        logging.exception("请求歌词时错误")
        return str(e)
    else:
        logging.debug(f"请求歌词成功, orig: {orig}, ts: {ts}")
        return orig, ts


def qm_search(keyword: str, search_type: SearchType) -> list | str:
    """
    搜索
    :param keyword:关键字
    :param search_type搜索类型
    :return: 搜索结果(list)或错误(str)
    """
    logging.debug(f"开始搜索：{keyword}, 类型为{search_type}")
    if search_type not in (SearchType.SONG, SearchType.ARTIST, SearchType.ALBUM, SearchType.SONGLIST):
        return f"搜索类型错误,类型为{search_type}"
    data = json.dumps({
        "comm": {
            "g_tk": 997034911,
            "uin": random.randint(1000000000, 9999999999),  # noqa: S311
            "format": "json",
            "inCharset": "utf-8",
            "outCharset": "utf-8",
            "notice": 0,
            "platform": "h5",
            "needNewCode": 1,
            "ct": 23,
            "cv": 0,
        },
        "req_0": {
            "method": "DoSearchForQQMusicDesktop",
            "module": "music.search.SearchCgiService",
            "param": {
                "num_per_page": "20",
                "page_num": "1",
                "query": keyword,
                "search_type": search_type.value,
            },
        },
    }, ensure_ascii=False).encode("utf-8")
    try:
        response = requests.post('https://u.y.qq.com/cgi-bin/musicu.fcg', headers=QMD_headers, data=data, timeout=3)
        response.raise_for_status()
        infos = response.json()['req_0']['data']['body']
        results = []
        match search_type:

            case SearchType.SONG:
                results = qmsonglist2result(infos['song']['list'])

            case SearchType.ALBUM:
                for album in infos['album']['list']:
                    results.append({
                        'id': album['albumID'],
                        'mid': album['albumMID'],
                        'name': album['albumName'],
                        'pic': album['albumPic'],  # 专辑封面
                        'count': album['song_count'],  # 歌曲数量
                        'time': album['publicTime'],
                        'artist': album['singerName'],
                        'source': Source.QM,
                    })

            case SearchType.SONGLIST:
                for songlist in infos['songlist']['list']:
                    results.append({
                        'id': songlist['dissid'],
                        'name': songlist['dissname'],
                        'pic': songlist['imgurl'],  # 歌单封面
                        'count': songlist['song_count'],  # 歌曲数量
                        'time': songlist['createtime'],
                        'creator': songlist['creator']['name'],
                        'source': Source.QM,
                    })

            case SearchType.ARTIST:
                for artist in infos['singer']['list']:
                    results.append({
                        'id': artist['singerID'],
                        'name': artist['singerName'],
                        'pic': artist['singerPic'],  # 艺术家图片
                        'count': artist['songNum'],  # 歌曲数量
                        'source': Source.QM,
                    })
    except requests.HTTPError as e:
        logging.exception("请求搜索数据时错误")
        return str(e)
    except requests.RequestException as e:
        logging.exception("请求搜索数据时错误")
        return str(e)
    except json.JSONDecodeError as e:
        logging.exception("解析搜索结果时错误")
        return str(e)
    except Exception as e:
        logging.exception("未知错误")
        return str(e)
    else:
        logging.info("搜索成功")
        logging.debug(f"搜索结果：{json.dumps(results, ensure_ascii=False, indent=4)}")
        return results


def qm_get_album_song_list(album_mid: str) -> list | str:
    data = json.dumps({
        "comm": {
            "cv": 4747474,
            "ct": 24,
            "format": "json",
            "inCharset": "utf-8",
            "outCharset": "utf-8",
            "notice": 0,
            "platform": "yqq.json",
            "needNewCode": 1,
            "uin": random.randint(1000000000, 9999999999),  # noqa: S311
            "g_tk_new_20200303": 708550273,
            "g_tk": 708550273,
        },
        "req_1": {
            "module": "music.musichallAlbum.AlbumSongList",
            "method": "GetAlbumSongList",
            "param": {"albumMid": album_mid, "begin": 0, "num": -1, "order": 2},
        },
    }, ensure_ascii=False).encode("utf-8")
    try:
        response = requests.post("https://u.y.qq.com/cgi-bin/musicu.fcg", headers=QMD_headers, data=data, timeout=10)
        response.raise_for_status()
        response_json = response.json()
        album_song_list = response_json["req_1"]["data"]["songList"]
        results = qmsonglist2result(album_song_list, "album")
        if response_json['req_1']['data']['totalNum'] != len(results):
            logging.error("获取到的歌曲数量与实际数量不一致")
            return "专辑歌曲获取不完整"

    except requests.HTTPError as e:
        logging.exception("请求专辑数据时错误")
        return str(e)
    except requests.RequestException as e:
        logging.exception("请求专辑数据时错误")
        return str(e)
    except json.JSONDecodeError as e:
        logging.exception("解析专辑数据时错误")
        return str(e)
    except Exception as e:
        logging.exception("未知错误")
        return str(e)
    else:
        logging.info("获取专辑信息成功")
        logging.debug(f"获取结果：{json.dumps(results, ensure_ascii=False, indent=4)}")
        return results


def qm_get_songlist_song_list(songlist_id: str) -> str | list:
    params = {
        '_webcgikey': 'uniform_get_Dissinfo',
        '_': int(time.time() * 1000),
    }
    data = {
        "comm": {
            "g_tk": 5381,
            "uin": "",
            "format": "json",
            "inCharset": "utf-8",
            "outCharset": "utf-8",
            "notice": 0,
            "platform": "h5",
            "needNewCode": 1,
        },
        "req_0": {
            "module": "music.srfDissInfo.aiDissInfo",
            "method": "uniform_get_Dissinfo",
            "param": {
                "disstid": int(songlist_id),
                "enc_host_uin": "",
                "tag": 1,
                "userinfo": 1,
                "song_begin": 0,
                "song_num": -1,
            },
        },
    }

    url = 'https://u.y.qq.com/cgi-bin/musicu.fcg'

    try:
        response = requests.post(url, headers=QMD_headers, params=params, json=data, timeout=20)
        response.raise_for_status()
        response_json = response.json()
        songlist = response_json['req_0']['data']['songlist']
        results = qmsonglist2result(songlist)
        if response_json['req_0']['data']['total_song_num'] != len(results):
            return "获取歌曲列表失败, 返回的歌曲数量与实际数量不一致"
    except requests.exceptions.RequestException as e:
        print(f"获取歌单失败 {e}")
        return str(e)
    else:
        logging.info(f"获取歌单成功, 数量: {len(results)}")
        logging.debug(f"获取歌单成功,获取结果: {results}")
        return results


def kg_search(info: str | dict, search_type: SearchType, page: int = 1) -> str | list:
    if isinstance(info, str):
        keyword = info
    elif isinstance(info, dict):
        keyword = info.get("keyword")
        duration = info.get("duration")
        hash_ = info.get("hash")
    match search_type:
        case SearchType.SONG:
            url = "http://msearchcdn.kugou.com/api/v3/search/song"
            params = {
                "showtype": "14",
                "highlight": "",
                "pagesize": "30",
                "tag_aggr": "1",
                "tagtype": "全部",
                "plat": "0",
                "sver": "5",
                "keyword": keyword,
                "correct": "1",
                "api_ver": "1",
                "version": "9108",
                "page": page,
                "area_code": "1",
                "tag": "1",
                "with_res_tag": "1",
            }
        case SearchType.SONGLIST:
            url = "http://mobilecdnbj.kugou.com/api/v3/search/special"
            params = {
                "version": "9108",
                "highlight": "",
                "keyword": keyword,
                "pagesize": "20",
                "filter": "0",
                "page": page,
                "sver": "2",
                "with_res_tag": "1",
            }
        case SearchType.ALBUM:
            url = "http://msearch.kugou.com/api/v3/search/album"
            params = {
                "version": "9108",
                "iscorrection": "1",
                "highlight": "",
                "plat": "0",
                "keyword": keyword,
                "pagesize": "20",
                "page": "1",
                "sver": "2",
                "with_res_tag": "1",
            }
        case SearchType.LYRICS:
            url = "http://lyrics.kugou.com/search"
            params = {
                "ver": 1,
                "man": "yes",
                "client": "pc",
                "keyword": keyword,
                "duration": duration,
                "hash": hash_,
            }
    try:
        response = requests.get(url, params=params, timeout=3)
        response.raise_for_status()
        if search_type == SearchType.LYRICS:
            response_json = response.json()
        else:
            response_json = json.loads(re.findall(r"<!--KG_TAG_RES_START-->(.*)<!--KG_TAG_RES_END-->", response.text, re.DOTALL)[0])
        match search_type:
            case SearchType.SONG:
                results = kgsonglist2result(response_json['data']['info'])
            case SearchType.SONGLIST:
                results = []
                for songlist in response_json['data']['info']:
                    name_soup = BeautifulSoup(songlist['specialname'], 'html.parser')
                    results.append({
                        'id': songlist['specialid'],
                        'name': name_soup.get_text(),
                        'pic': songlist['imgurl'],  # 歌单封面
                        'count': songlist['songcount'],  # 歌曲数量
                        'time': songlist['publishtime'],
                        'creator': songlist['nickname'],
                        'source': Source.KG,
                    })
            case SearchType.ALBUM:
                results = []
                for album in response_json['data']['info']:
                    results.append({
                        'id': album['albumid'],
                        'name': album['albumname'],
                        'pic': album['imgurl'],  # 专辑封面
                        'count': album['songcount'],  # 歌曲数量
                        'time': album['publishtime'],
                        'artist': album['singername'],
                        'source': Source.KG,
                    })
            case SearchType.LYRICS:
                results = []
                for lyric in response_json['candidates']:
                    results.append({
                        "id": lyric['id'],
                        "accesskey": lyric['accesskey'],
                        "duration": lyric['duration'],
                        "creator": lyric['nickname'],
                        "score": lyric['score'],
                        "source": Source.KG,
                    })
    except Exception as e:
        logging.exception("搜索时错误")
        return str(e)
    else:
        logging.debug(f"搜索结果：{json.dumps(results, ensure_ascii=False, indent=4)}")
        return results


def kg_get_songlist(listid: str | int, list_type: str) -> str | list:
    if list_type not in ["album", "songlist"]:
        return "错误的list_type"

    match list_type:
        case "album":
            url = "http://mobilecdn.kugou.com/api/v3/album/song"
            params = {
                "version": "9108",
                "albumid": listid,
                "plat": "0",
                "pagesize": "-1",
                "area_code": "1",
                "page": "1",
                "with_res_tag": "1",
            }

        case "songlist":
            url = "http://mobilecdn.kugou.com/api/v3/special/song"
            params = {
                "version": "9108",
                "specialid": listid,
                "plat": "0",
                "pagesize": "-1",
                "area_code": "1",
                "page": "1",
                "with_res_tag": "1",
            }
    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        response_json = json.loads(re.findall(r"<!--KG_TAG_RES_START-->(.*)<!--KG_TAG_RES_END-->", response.text, re.DOTALL)[0])
        results = kgsonglist2result(response_json['data']['info'], "songlist")
    except Exception as e:
        logging.exception("获取歌曲列表数据时错误")
        return str(e)
    else:
        logging.info("获取歌曲列表数据成功")
        return results


def get_krc(lyrsicid: str | int, access_key: str) -> str | list:
    url = "https://lyrics.kugou.com/download"
    params = {
        "ver": 1,
        "client": "pc",
        "id": lyrsicid,
        "accesskey": access_key,
        "fmt": "krc",
        "charset": "utf8",
    }
    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        response_json = response.json()
        krc = b64decode(response_json['content'])
    except Exception as e:
        logging.exception("获取歌词数据时错误")
        return str(e)
    else:
        logging.info("获取歌词数据成功")
        return krc
