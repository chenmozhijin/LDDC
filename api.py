from __future__ import annotations

import json
import logging
import random
import string

import requests


class QMSearchType:
    SONG = 0
    ARTIST = 1
    ALBUM = 2
    SONGLIST = 3
    LYRIC = 7


def get_qrc(songid: str) -> str | requests.Response:
    params = {
        'version': '15',
        'miniversion': '82',
        'lrctype': '4',
        'musicid': songid,
    }
    try:
        response = requests.get('https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg',
                                params=params,
                                timeout=10)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logging.exception("请求qrc 歌词时错误")
        return str(e)
    else:
        logging.debug(f"请求qrc 歌词成功：{songid}, {response.text.strip()}")
    return response


def qm_search(keyword: str, search_type: QMSearchType) -> list | str:
    """
    搜索
    :param keyword:关键字
    :param search_type搜索类型
    :return: 搜索结果(list)或错误(str)
    """
    logging.debug(f"开始搜索：{keyword}, 类型为{search_type}")
    if search_type not in (QMSearchType.SONG, QMSearchType.ARTIST, QMSearchType.ALBUM, QMSearchType.SONGLIST):
        return f"搜索类型错误,类型为{search_type}"
    headers = {
        "Accept": "*/*",
        "Accept-Encoding": "gzip, deflate",
        "Accept-Language": "zh-CN",
        "User-Agent": "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)",
    }
    data = json.dumps({
        "comm": {
            "g_tk": 997034911,
            "uin": ''.join(random.sample(string.digits, 10)),
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
                "search_type": search_type,
            },
        },
    }, ensure_ascii=False).encode("utf-8")
    try:
        response = requests.post('https://u.y.qq.com/cgi-bin/musicu.fcg', headers=headers, data=data, timeout=3)
        response.raise_for_status()
        infos = response.json()['req_0']['data']['body']
        results = []
        match search_type:

            case QMSearchType.SONG:
                for song in infos['song']['list']:
                    # 处理艺术家
                    artist = ""
                    for singer in song['singer']:
                        if artist != "":
                            artist += "/"
                        artist += singer['name']
                    # 添加结果
                    results.append({
                        'id': song['id'],
                        'name': song['name'],
                        'subtitle': song['subtitle'],
                        'artist': artist,
                        'album': song['album']['name'],
                        'source': 'qm',
                    })

            case QMSearchType.ALBUM:
                for album in infos['album']['list']:
                    results.append({
                        'id': album['albumID'],
                        'name': album['albumName'],
                        'pic': album['albumPic'],  # 专辑封面
                        'count': album['song_count'],  # 歌曲数量
                        'time': album['publicTime'],
                        'artist': album['singerName'],
                        'source': 'qm',
                    })

            case QMSearchType.SONGLIST:
                for songlist in infos['songlist']['list']:
                    results.append({
                        'id': songlist['dissid'],
                        'name': songlist['dissname'],
                        'pic': songlist['imgurl'],  # 歌单封面
                        'count': songlist['song_count'],  # 歌曲数量
                        'source': 'qm',
                    })

            case QMSearchType.ARTIST:
                for artist in infos['singer']['list']:
                    results.append({
                        'id': artist['singerID'],
                        'name': artist['singerName'],
                        'pic': artist['singerPic'],  # 艺术家图片
                        'count': artist['songNum'],  # 歌曲数量
                        'source': 'qm',
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
