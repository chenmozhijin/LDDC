# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import re
from difflib import SequenceMatcher

symbol_map = {
    '（': '(',
    '）': ')',
    '：': ':',
    '！': '!',
    '？': '?',
    '／': '/',
    '＆': '&',
    '＊': '*',
    '＠': '@',
    '＃': '#',
    '＄': '$',
    '％': '%',
    '＼': '\\',
    '｜': '|',
    '＝': '=',
    '＋': '+',
    '－': '-',
    '＜': '<',
    '＞': '>',
    '［': '[',
    '］': ']',
    '｛': '{',
    '｝': '}',
}


def unified_symbol(text: str) -> str:
    text = text.strip()
    for k, v in symbol_map.items():
        text = text.replace(k, v)
    return re.sub(r"\s", " ", text)


def text_difference(text1: str, text2: str) -> float:
    if text1 == text2:
        return 1.0
    # 计算编辑距离
    differ = SequenceMatcher(lambda x: x == " ", text1, text2)
    return differ.ratio()


def list_max_difference(list1: list[str | list[str]], list2: list[str | list[str]], filter_empty: bool = True) -> float:
    """计算两个列表中字符串的最大相似度"""
    def list_str_max_difference(l1: list[str], l2: list[str]) -> float:
        if filter_empty:
            # 过滤掉空字符串
            l1 = [item for item in l1 if item]
            l2 = [item for item in l2 if item]
        return max(text_difference(text1, text2) for text1 in l1 for text2 in l2)

    list1 = [[item] if not isinstance(item, list) else item for item in list1]
    list2 = [[item] if not isinstance(item, list) else item for item in list2]

    if len(list1) >= len(list2) > 0:
        scores = [(i1, i2, list_str_max_difference(l1, l2)) for i1, l1 in enumerate(list1) for i2, l2 in enumerate(list2)]

    elif len(list2) >= len(list1) > 0:
        scores = [(i2, i1, list_str_max_difference(l2, l1)) for i2, l2 in enumerate(list2) for i1, l1 in enumerate(list1)]
    else:
        return 0.0

    scores.sort(key=lambda x: x[2], reverse=True)

    total_score = 0.0
    used_i1, used_i2 = set(), set()

    for i1, i2, score in scores:
        if i1 not in used_i1 and i2 not in used_i2:
            used_i1.add(i1)
            used_i2.add(i2)
            total_score += score
            if len(used_i1) == len(list1) or len(used_i2) == len(list2):
                break

    return total_score / max(len(list1), len(list2))


def artist_str2list(artist: str) -> tuple[list[str], list[set[str]]]:
    """将歌手字符串转换为列表

    :param artist: 歌手字符串
    :return: 歌手列表 ([组织名,...], [[歌手名, 歌手别名],...])
    """
    if all(len(s) == 1 for s in artist.split(" ")):
        artist = "".join(artist.split(" "))

    # 匹配特定样式
    artist = artist.strip().replace('·', '・').replace('（', '(').replace('）', ')').replace('：', ':')

    if "・" in artist and re.search(r"[Cc][Vv][.:]", artist):  # 包含"・"与"CV:"的
        # 组织名(角色1・角色2...)/CV:歌手1・歌手2...
        matched: re.Match[str] | None = re.search(r"^(?P<group>.*)\s?\((?P<characters>.+)\)/[Cc][Vv][.:]\s?(?P<songers>.+)$", artist)
        if matched and "・" in matched.group("characters") and "・" in matched.group("songers"):
            characters = [unified_symbol(c) for c in matched.group("characters").split("・")]
            songers = [unified_symbol(s) for s in matched.group("songers").split("・")]
            if len(characters) == len(songers):
                return [matched.group("group")], [list({c, s}) for c, s in zip(characters, songers)]  # noqa: B905

        # 组织名1(角色1・角色2...CV:歌手1・歌手2...)/组织名2(角色3・角色4...CV:歌手3・歌手4...)/...
        split_result = artist.split("/")
        artists = []
        groups = []
        for splited in split_result:
            matched: re.Match[str] | None = re.search(r"^(?P<group>.*)\s?\((?P<characters>.+)[Cc][Vv][.:](?P<songers>.+)\)$", splited)
            if matched and "・" in matched.group("characters") and "・" in matched.group("songers"):
                characters = [unified_symbol(c) for c in matched.group("characters").split("・")]
                songers = [unified_symbol(s) for s in matched.group("songers").split("・")]
                if len(characters) == len(songers):
                    artists.extend([list({c, s}) for c, s in zip(characters, songers, strict=False)])
                    groups.append(matched.group("group"))
                else:
                    break
        else:
            return groups, artists

        artists = None
        matched = None

    if artist.count("(") == artist.count(")") in [1, 2]:
        # 组织名(歌手名)
        matched: re.Match[str] | None = re.search(r"^(?P<group>.*)\s?\(+(?P<songers>[^)]+)\)+$", artist)
        if matched:
            split_result = re.split(r"[,、・]", matched.group("songers"))
            if len(split_result) > 1:
                return [matched.group("group")], [[unified_symbol(s)] for s in split_result]

    # 组织名 ...
    groups = []
    artists_str = None
    matched: re.Match[str] | None = re.search(r"^(?P<group>.*[^&])\s(?P<artist_str>[^(&a-zA-Z].*)$", artist)
    if matched:
        groups = [matched.group("group")]
        artist = matched.group("artist_str")

    # 以"."分隔("."有时可能表示"・")
    splited = re.split(r"(\))\.", artist)
    if len(splited) > 1 and (len(splited) + 1) % 2 == 0:
        artists_str = []
        for i, s in enumerate(splited):
            if i % 2 == 0:
                artists_str.append(unified_symbol(s))
            else:
                artists_str[-1] += s

    # 以","或"、"或"/"或"\"或"&"分隔
    splited = re.split(r"[,、/\\&]", artist)
    if len(splited) > 1:
        artists_str = [unified_symbol(s) for s in splited]

    if artists_str is None:
        artists_str = [unified_symbol(artist)]

    artists = []
    for artist_str in artists_str:
        matched = re.search(r"^(?P<songer1>.*)\s?feat\.(?P<character>.*)\s?\((?P<songer2>.*)\)$", artist_str)
        if matched:
            artists.append([unified_symbol(matched.group("songer1"))])
            artists.append(list({matched.group("songer2").strip(), matched.group("character").strip()}))
            continue

        # 歌手名(歌手别名)或角色名(歌手名)
        matched = re.search(r"^(?P<name1>.*)\s?\((?:[Cc][Vv][.:]|[Vv][Oo][.:])?(?P<name2>.*)\)$", artist_str)
        if matched:
            artists.append(list({matched.group("name1").strip(), matched.group("name2").strip()}))
            continue

        artists.append([artist_str])

    return groups, artists


def calculate_artist_score(artist1: str | list, artist2: str | list) -> float:
    score = 0
    artists = [artist1, artist2]
    for i, artist in enumerate(artists):
        if isinstance(artist, list):
            for a in artist:
                if re.search(r"[)(:]", a):
                    # 说明不是纯粹的歌手名
                    artists[i] = artist_str2list("/".join(artist))
                    break
        elif isinstance(artist, str):
            artists[i] = artist_str2list(artist)

    is_list = [i for i in range(len(artists)) if isinstance(artists[i], list)]
    if len(is_list) == 0:
        # 都是组织名+歌手名

        # 计算底分
        score = list_max_difference(artists[0][0] + artists[0][1], artists[1][0] + artists[1][1])
        if score == 1:
            return 100
        score = max(score, text_difference("".join(artists[0][0] + artists[0][1]), "".join(artists[1][0] + artists[1][1])))
        if (not artists[0][1] and artists[0][0] and artists[1][0]) or (not artists[1][1] and artists[1][0] and artists[0][0]):
            # 只有组织名
            score = max(score, list_max_difference(artists[0][1], artists[1][1]) * 0.6)
        elif artists[0][1] and artists[1][1]:
            # 都有歌手名
            score = max(score, list_max_difference(artists[0][1], artists[1][1]))

    elif len(is_list) == 2:
        # 两个都是列表
        score = max(list_max_difference(artists[0], artists[1]), text_difference("".join(artists[0]), "".join(artists[1])))

    else:
        list_index = is_list[0]
        tuple_index = 1 if is_list[0] == 0 else 0

        # 计算底分
        score = list_max_difference(artists[list_index], artists[tuple_index][0] + artists[tuple_index][1])
        if score == 1:
            return 100
        score = max(score, list_max_difference(artists[list_index], artists[tuple_index][1]))
        if score == 1:
            return 100
        score = max(score, text_difference("".join(artists[list_index]), "".join(artists[tuple_index][0] + [a for sl in artists[tuple_index][1] for a in sl])))

        if len(artists[list_index]) == 1 and artists[tuple_index][0]:
            score = max(score, list_max_difference(artists[list_index], artists[tuple_index][0]) * 0.6)

    return max(score * 100, 0)


TITLE_TAG_PATTERN = re.compile(r"|".join([r"[-<(\[～]([～\]^)>-]*)[～\]^)>-]",  # noqa: FLY002
                                          r"(\w+ ?(?:(?:solo |size )?ver(?:sion)?\.?|size|style|mix(?:ed)?|edit(?:ed)?|版|solo))",
                                          r"(纯音乐|inst\.?(?:rumental)|off ?vocal(?: ?[Vv]er.)?)"]))


def calculate_title_score(title1: str, title2: str) -> float:
    def get_tags(not_same: str) -> tuple[list, str]:
        """获取标签

        :param not_same: 两个标题不同的部分
        """
        not_same_tags: list[tuple[str, str, str, str]] = TITLE_TAG_PATTERN.findall(not_same)
        not_same_tags: list[str] = [item.strip() for tup in not_same_tags for item in tup if item]  # 去除空字符串与符号
        not_same_other = re.sub(r"|".join(not_same_tags) + r"|[-><)(\]\[～]", "", not_same)  # 获取非tags部分

        # 统一一些tags
        for i, tag in enumerate(not_same_tags):
            tag_ = re.sub(r"ver(?:sion)?\.?", "ver", tag)
            tag_ = re.sub(r"伴奏|纯音乐|inst\.?(?:rumental)|off ?vocal(?: ?[Vv]er.)?", "inst", tag_)
            tag_ = tag_.replace("mixed", "mix").replace("edited", "edit")
            tag_ = re.sub(r"(solo|mix|edit|style|size) ver", r"\1", tag_)
            tag_ = re.sub("(?:tv|anime) ?(?:サイズ|size)?(?: ?edit)?(?: ?ver)?", "tv size", tag_)
            not_same_tags[i] = tag_

        return not_same_tags, not_same_other

    title1, title2 = unified_symbol(title1).lower(), unified_symbol(title2).lower()
    if title1 == title2:
        return 100

    score0 = max(text_difference(title1, title2), 0) * 100  # 计算文本相似度得到的分数
    same_begin = ""  # 开头相同的字符串

    for i, text1 in enumerate(title1):
        if len(title2) > i and text1 == title2[i]:
            same_begin += text1
        else:
            break

    if same_begin in (title1, title2) or not same_begin:
        return score0

    not_same1_tags, not_same1_other = get_tags(title1[len(same_begin):])
    not_same2_tags, not_same2_other = get_tags(title2[len(same_begin):])

    # 计算tags相似度
    tag1_no_match = []
    tag2_no_match = not_same2_tags
    for tag1 in not_same1_tags:
        if tag1 in not_same2_tags:
            # tag匹配
            tag2_no_match.remove(tag1)
        elif re.search(r"(?:solo|mix|edit|style|size|edit|inst)$", tag1):
            # 普通标签
            tag1_no_match.append(tag1)
        elif tag1 in not_same2_other:
            not_same1_other += tag1

    for tag2 in tag2_no_match:
        if not re.search(r"(?:solo|mix|edit|style|size|edit|inst)$", tag2) and tag2 in not_same1_other:
            not_same2_other += tag2
            tag2_no_match.remove(tag2)

    kp = len(same_begin) / ((len(not_same1_other) + len(not_same2_other)) / 2 + len(same_begin))
    score1 = 100 * kp + max(text_difference(not_same1_other, not_same2_other), 0) * (1 - kp)

    if not tag1_no_match and not tag2_no_match:
        return max(score1 * 0.7 + 30, score0)

    score2, score3 = 0, 0
    if tag1_no_match and tag2_no_match:
        for tag1 in tag1_no_match:
            score2 += max([text_difference(tag1, tag2) for tag2 in tag2_no_match]) * (30 / len(tag1_no_match))

        for tag2 in tag2_no_match:
            score3 += max([text_difference(tag1, tag2) for tag1 in tag1_no_match]) * (30 / len(tag2_no_match))

    return max(score1 * 0.7 + max(score2, score3), score0)
