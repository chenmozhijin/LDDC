# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import random
import re
import time
from base64 import b64decode, b64encode
from typing import Any

import requests

from utils.enum import SearchType, Source
from utils.error import LyricsRequestError
from utils.logger import DEBUG, logger

from .decryptor.eapi import (
    eapi_params_encrypt,
    eapi_response_decrypt,
    get_cache_key,
)


def get_latest_version() -> tuple[bool, str, str]:
    try:
        latest_release = requests.get("https://api.github.com/repos/chenmozhijin/LDDC/releases/latest", timeout=5).json()
    except Exception as e:
        logger.exception("获取最新版本信息时错误")
        return False, str(e), ""
    else:
        if "tag_name" in latest_release:
            latest_version = latest_release["tag_name"]
            body = latest_release["body"]
            return True, latest_version, body
        return False, f"获取最新版本信息失败, 响应: {latest_release}", ""


def logging_json_default(obj: Any) -> str:
    if hasattr(obj, '__json__'):
        return obj.__json__()
    msg = f"Type {type(obj).__name__} not serializable"
    raise TypeError(msg)


QMD_headers = {
    "Accept": "*/*",
    "Accept-Encoding": "gzip, deflate",
    "Accept-Language": "zh-CN",
    "User-Agent": "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)",
}


NeteaseCloudMusic_headers = {
    "Accept": "*/*",
    "Content-Type": "application/x-www-form-urlencoded",
    "MG-Product-Name": "music",
    "Nm-GCore-Status": "1",
    "Origin": "orpheus://orpheus",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko)"
                  " Chrome/35.0.1916.157 NeteaseMusicDesktop/2.9.7.199711 Safari/537.36",
    "Accept-Encoding": "gzip,deflate",
    "Accept-Language": "en-us,en;q=0.8",
    "Cookie": "os=pc; osver=Microsoft-Windows-10--build-22621-64bit; appver=2.9.7.199711; channel=netease; WEVNSM=1.0.0; WNMCID=slodmo.1709434129796.01.0;",
}


def nesonglist2result(songlist: list) -> list:
    results = []
    for song in songlist:
        info = song
        # 处理艺术家
        artist = [singer['name'] for singer in info['ar'] if singer['name'] != ""]
        results.append({
            'id': info['id'],
            'title': info['name'],
            'subtitle': info['alia'][0] if info['alia'] else "",
            'artist': artist,
            'album': info['al']['name'],
            'duration': round(info['dt'] / 1000),
            'source': Source.NE,
        })
    return results


def _eapi_request(path: str, params: dict) -> dict:
    """eapi接口请求

    :param path: 请求的路径
    :param params: 请求参数
    :param method: 请求方法
    :return dict: 请求结果
    """
    encrypted_params = eapi_params_encrypt(path.replace("eapi", "api").encode(), params)
    headers = NeteaseCloudMusic_headers.copy()
    # headers.update({"Content-Length": str(len(params))})
    url = "https://music.163.com" + path
    response = requests.post(url, headers=headers, data=encrypted_params, timeout=4)
    response.raise_for_status()
    data = eapi_response_decrypt(response.content)
    return json.loads(data)


def eapi_get_params_header() -> str:
    return json.dumps({
        "os": "pc",
        "appver": "2.9.7.199711",
        "deviceId": "",
        "requestId": str(random.randint(10000000, 99999999)),  # noqa: S311
        "clientSign": "",
        "osver": "Microsoft-Windows-10--build-22621-64bit",
        "Nm-GCore-Status": "1",
    }, ensure_ascii=False, separators=(',', ':'))


def ne_search(keyword: str, search_type: SearchType, page: str | int = 1) -> list:
    """网易云音乐搜索

    :param keyword:关键字
    :param search_type搜索类型
    :param page页码(从1开始)
    :return: 搜索结果(list)或错误(str)
    """
    match search_type:
        case SearchType.SONG:
            param_type = "1"
        case SearchType.ALBUM:
            param_type = "10"
        case SearchType.ARTIST:
            param_type = "100"
        case SearchType.SONGLIST:
            param_type = "1000"
        case SearchType.LYRICS:
            param_type = "1006"

    params = {
        "hlpretag": '<span class="s-fc2">',
        "hlposttag": "</span>",
        "type": param_type,
        "queryCorrect": "true",
        "s": keyword,
        "offset": str((int(page) - 1) * 20),
        "total": "true",
        "limit": "20",
        "e_r": True,
        "header": eapi_get_params_header(),
    }
    data = _eapi_request("/eapi/cloudsearch/pc", params)
    if 'result' not in data:
        return []
    match search_type:
        case SearchType.SONG:
            if 'songs' not in data['result']:
                return []
            results = nesonglist2result(data['result']['songs'])
        case SearchType.ALBUM:
            if 'albums' not in data['result']:
                return []
            results = []
            for album in data['result']['albums']:
                results.append({
                    'id': album['id'],
                    'name': album['name'],
                    'pic': album['picUrl'],  # 专辑封面
                    'count': album['size'],  # 歌曲数量
                    'time': time.strftime('%Y-%m-%d', time.localtime(album['publishTime'] // 1000)),
                    'artist': album['artists'][0]["name"] if album['artists'] else "",
                    'source': Source.NE,
                })
        case SearchType.SONGLIST:
            if 'playlists' not in data['result']:
                return []
            results = []
            for songlist in data['result']['playlists']:
                results.append({
                    'id': songlist['id'],
                    'name': songlist['name'],
                    'pic': songlist['coverImgUrl'],  # 歌单封面
                    'count': songlist['trackCount'],  # 歌曲数量
                    'time': "",
                    'creator': songlist['creator']['nickname'],
                    'source': Source.NE,
                })
    logger.info("搜索成功")
    if logger.level <= DEBUG:
        logger.debug("搜索结果: %s", json.dumps(results, default=logging_json_default, ensure_ascii=False, indent=4))
    return results


def ne_get_lyrics(songid: str | int) -> dict:
    params = {
        "os": "pc",
        "id": str(songid),
        "lv": "-1",
        "kv": "-1",
        "tv": "-1",
        "rv": "-1",
        "yv": "1",
        "showRole": "true",
        "cp": "true",
        "e_r": True,
    }
    try:
        data = _eapi_request("/eapi/song/lyric", params)
    except Exception as e:
        logger.exception("请求歌词失败")
        msg = f"请求歌词失败: {e}"
        raise LyricsRequestError(msg) from e
    return data


def ne_get_songlist(listid: str | int, list_type: str) -> str | list:
    if list_type not in ["album", "songlist"]:
        return "错误的list_type"

    params = {
        'id': str(listid),
        'e_r': True,
        'header': eapi_get_params_header(),
    }
    match list_type:
        case "album":
            path = "/eapi/album/v3/detail"
            params.update({'cache_key': get_cache_key(f"id={listid!s}")})
        case "songlist":
            path = "/eapi/playlist/v4/detail"
            params.update({"n": '500', 's': '0'})
            params.update({'cache_key': get_cache_key(f'e_r=true&id={listid!s}&n=500&s=0')})

    try:
        data = _eapi_request(path, params)
        match list_type:
            case "album":
                count = data['album']['size']
                results = nesonglist2result(data['songs'])
            case "songlist":
                count = data['playlist']['trackCount']
                results = nesonglist2result(data['playlist']['tracks'])
        if count > 500 and list_type == "songlist":
            path = "/eapi/v3/song/detail"
            songidss = [info["id"] for i, info in enumerate(data['playlist']['trackIds']) if i >= 500]
            chunked_songidss = [songidss[i:i + 500] for i in range(0, len(songidss), 500)]
            for songids in chunked_songidss:
                params = {
                    'c': json.dumps([{"id": songid, "v": 0} for songid in songids], ensure_ascii=False, separators=(',', ':')),
                    'e_r': True,
                    'header': eapi_get_params_header(),
                }
                for _i in range(3):
                    try:
                        data = _eapi_request(path, params)
                        results.extend(nesonglist2result(data['songs']))
                    except Exception:
                        logger.exception("网易云音乐接口请求失败")
                        continue
                    break

        if count != len(results):
            logger.error("获取到的歌曲数量与实际数量不一致,预期: %s, 实际: %s", count, len(results))
            return "歌曲列表获取不完整"

    except Exception as e:
        logger.exception("网易云音乐接口请求失败")
        return str(e)
    return results


def qmsonglist2result(songlist: list, list_type: str | None = None) -> list:
    results = []
    for song in songlist:
        info = song["songInfo"] if list_type == "album" else song
        # 处理艺术家
        artist = [singer['name'] for singer in info['singer'] if singer['name'] != ""]
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


def qm_get_lyrics(title: str, artist: list[str], album: str, id_: int, duration: int) -> dict | str:
    """获取歌词

    :param title: 歌曲名
    :param artist: 艺术家
    :param album: 专辑名
    :param id_: 歌曲id
    :param duration: 歌曲时长
    :return: 歌词信息
    """
    base64_album_name = b64encode(album.encode()).decode()
    base64_singer_name = b64encode(artist[0].encode()).decode() if artist else b64encode(b"").decode()
    base64_song_name = b64encode(title.encode()).decode()

    data = json.dumps({
        "comm": {
            "_channelid": "0",
            "_os_version": "6.2.9200-2",
            "authst": "",
            "ct": "19",
            "cv": "1942",
            "patch": "118",
            "psrf_access_token_expiresAt": 0,
            "psrf_qqaccess_token": "",
            "psrf_qqopenid": "",
            "psrf_qqunionid": "",
            "tmeAppID": "qqmusic",
            "tmeLoginType": 0,
            "uin": "0",
            "wid": "0",
        },
        "music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": {
            "method": "GetPlayLyricInfo",
            "module": "music.musichallSong.PlayLyricInfo",
            "param": {
                "albumName": base64_album_name,
                "crypt": 1,
                "ct": 19,
                "cv": 1942,
                "interval": duration,
                "lrc_t": 0,
                "qrc": 1,
                "qrc_t": 0,
                "roma": 1,
                "roma_t": 0,
                "singerName": base64_singer_name,
                "songID": id_,
                "songName": base64_song_name,
                "trans": 1,
                "trans_t": 0,
                "type": 0,
            },
        },
    }, ensure_ascii=False).encode("utf-8")
    try:
        response = requests.post('https://u.y.qq.com/cgi-bin/musicu.fcg', headers=QMD_headers, data=data, timeout=10)
        response.raise_for_status()
        response_data: dict = response.json()['music.musichallSong.PlayLyricInfo.GetPlayLyricInfo']['data']
    except Exception as e:
        logger.exception("请求歌词失败")
        msg = f"请求歌词失败: {e}"
        raise LyricsRequestError(msg) from e
    else:
        if logger.level <= DEBUG:
            logger.debug("请求qm歌词成功：%s, %s}", id_, json.dumps(response_data, default=logging_json_default, ensure_ascii=False, indent=4))
        return response_data


def qm_search(keyword: str, search_type: SearchType, page: int | str = 1) -> list:
    """QQ音乐搜索

    :param keyword:关键字
    :param search_type搜索类型
    :param page页码(从1开始)
    :return: 搜索结果(list)或错误(str)
    """
    if search_type not in (SearchType.SONG, SearchType.ARTIST, SearchType.ALBUM, SearchType.SONGLIST):
        msg = f"搜索类型错误,类型为{search_type}"
        raise ValueError(msg)
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
                "num_per_page": 20,
                "page_num": int(page),
                "query": keyword,
                "search_type": search_type.value,
            },
        },
    }, ensure_ascii=False).encode("utf-8")
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
    logger.info("搜索成功")
    if logger.level <= DEBUG:
        logger.debug("搜索结果: %s", json.dumps(results, default=logging_json_default, ensure_ascii=False, indent=4))
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
            logger.error("获取到的歌曲数量与实际数量不一致")
            return "专辑歌曲获取不完整"

    except requests.HTTPError as e:
        logger.exception("请求专辑数据时错误")
        return str(e)
    except requests.RequestException as e:
        logger.exception("请求专辑数据时错误")
        return str(e)
    except json.JSONDecodeError as e:
        logger.exception("解析专辑数据时错误")
        return str(e)
    except Exception as e:
        logger.exception("未知错误")
        return str(e)
    else:
        logger.info("获取专辑信息成功")
        if logger.level <= DEBUG:
            logger.debug("获取结果: %s", json.dumps(results, default=logging_json_default, ensure_ascii=False, indent=4))
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
        logger.exception("获取歌单失败")
        return str(e)
    else:
        logger.info("获取歌单成功, 数量: %s", len(results))
        logger.debug("获取歌单成功,获取结果: %s", results)
        return results


def kgsonglist2result(songlist: list, list_type: str = "search") -> list:
    results = []

    for song in songlist:
        match list_type:
            case "songlist":
                title = song['filename'].split("-")[1].strip()
                artist = song['filename'].split("-")[0].strip().split("、")
                album = ""
            case "search":
                title = song['songname']
                album = song['album_name']
                artist = song['singername'].split("、")
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


def kg_search(keyword: str, search_type: SearchType, info: dict | None = None, page: int = 1) -> list[dict[str, Any]]:
    """酷狗音乐搜索

    :param info:关键字
    :param info:关键字
    :param search_type搜索类型
    :param page页码(从1开始)
    :return: 搜索结果(list)或错误(str)
    """
    domain = random.choice(["mobiles.kugou.com", "msearchcdn.kugou.com", "mobilecdnbj.kugou.com", "msearch.kugou.com"])  # noqa: S311

    match search_type:
        case SearchType.SONG:
            url = f"http://{domain}/api/v3/search/song"
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
            url = f"http://{domain}/api/v3/search/special"
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
            url = f"http://{domain}/api/v3/search/album"
            params = {
                "version": "9108",
                "iscorrection": "1",
                "highlight": "",
                "plat": "0",
                "keyword": keyword,
                "pagesize": "20",
                "page": page,
                "sver": "2",
                "with_res_tag": "1",
            }
        case SearchType.LYRICS:
            if not info:
                msg = "错误: 缺少参数info"
                raise ValueError(msg)
            url = "http://lyrics.kugou.com/search"
            params = {
                "ver": 1,
                "man": "yes",
                "client": "pc",
                "keyword": keyword,
                "duration": info["duration"],
                "hash": info["hash"],
            }
        case _:
            msg = f"错误: 未知搜索类型{search_type!s}"
            raise ValueError(msg)
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
                results.append({
                    'id': songlist['specialid'],
                    'name': songlist['specialname'],
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
    if logger.level <= DEBUG:
        logger.debug("搜索结果：%s", json.dumps(results, default=logging_json_default, ensure_ascii=False, indent=4))
    return results


def kg_get_songlist(listid: str | int, list_type: str) -> str | list:
    if list_type not in ["album", "songlist"]:
        return "错误的list_type"

    domain = random.choice(["mobiles.kugou.com", "msearchcdn.kugou.com", "mobilecdnbj.kugou.com", "msearch.kugou.com"])  # noqa: S311
    match list_type:
        case "album":
            url = f"http://{domain}/api/v3/album/song"
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
            url = f"http://{domain}/api/v3/special/song"
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
        logger.exception("获取歌曲列表数据时错误")
        return str(e)
    else:
        logger.info("获取歌曲列表数据成功")
        return results


def kg_get_lyrics(lyrsicid: str | int, access_key: str) -> bytes:
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
        logger.exception("请求歌词失败")
        msg = f"请求歌词失败: {e}"
        raise LyricsRequestError(msg) from e
    else:
        logger.info("获取歌词数据成功")
        return krc
