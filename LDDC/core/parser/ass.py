# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import contextlib
import re

from LDDC.common.models import (
    FSLyricsData,
    FSLyricsLine,
    FSLyricsWord,
    FSMultiLyricsData,
    LyricsData,
    LyricsLine,
    LyricsType,
    LyricsWord,
    MultiLyricsData,
)

from .utils import judge_lyrics_type


def parse_ass_time(timestamp: str) -> int:
    """将ASS时间格式转换为毫秒"""
    if (match := re.match(r"(\d+):(\d+):(\d+)\.(\d{2})", timestamp)) is None:
        msg = f"无效的时间格式: {timestamp}"
        raise ValueError(msg)
    h, m, s, cs = map(int, match.groups())
    return ((h * 3600 + m * 60 + s) * 1000) + cs * 10


# 预编译所有正则表达式
_TAG_PATTERN = re.compile(
    r"(?P<style_block>{[^{}]*?})|"  # 非贪婪匹配样式块
    r"(?P<newline>\\[nN])|"  # 换行符
    r"(?P<escape>\\\\)|"  # 转义反斜杠
    r"(?P<char>.)",  # 普通字符
    flags=re.IGNORECASE,
)

_KARAOKE_PATTERN = re.compile(
    r"(\\kt(\d+))|"  # 基准时间标签
    r"(\\[kK][oOfF]?(\d+))|"  # 卡拉OK标签
    r"(\\\\)|"  # 转义反斜杠
    r"(\\[{}])|"  # 转义花括号
    r"(.)",  # 其他字符
    flags=re.IGNORECASE,
)


def parse_karaoke_tags(text: str) -> list[tuple[int, str]]:
    """解析ASS卡拉OK标签并返回(持续时间, 文本块)列表"""
    segments = []
    current_text = []
    current_duration = 0
    base_time = 0

    def commit_current() -> None:
        """提交当前累积的文本块"""
        nonlocal current_text, current_duration
        if current_text and current_duration > 0:
            segments.append((current_duration, "".join(current_text)))
            current_text.clear()
            current_duration = 0

    def handle_kt(val: str) -> None:
        """处理基准时间标签"""
        nonlocal base_time
        with contextlib.suppress(ValueError):
            base_time = int(val) * 10  # 转换为毫秒

    def handle_k(val: str) -> None:
        """处理卡拉OK持续时间标签"""
        nonlocal current_duration, base_time
        try:
            commit_current()  # 提交已当前累积的文本块
            current_duration = base_time + (int(val) * 10)
            base_time = 0
        except ValueError:
            pass  # 可添加日志输出

    def process_style_block(content: str) -> None:
        """处理样式块内的合法标签"""
        for match in _KARAOKE_PATTERN.finditer(content):
            groups = match.groups()
            kt_full, kt_val, k_tag, k_val, escape1, brace_escape, char = groups

            if kt_full:
                handle_kt(kt_val)
            elif k_tag:
                handle_k(k_val)
            elif escape1:
                current_text.append("\\")
            elif brace_escape:  # 新增转义花括号处理
                current_text.append(brace_escape[1])
            elif char:
                current_text.append(char)

    # 主解析逻辑
    for match in _TAG_PATTERN.finditer(text):
        group_dict = match.groupdict()

        if style_block := group_dict["style_block"]:
            process_style_block(style_block[1:-1])  # 去除花括号
        elif group_dict["newline"]:
            current_text.append("\n")
        elif group_dict["escape"]:
            current_text.append("\\")
        elif char := group_dict["char"]:
            current_text.append(char)
    if segments or current_duration:
        commit_current()
        return [(dur, txt) for dur, txt in segments if txt]
    return [(0, text)]  # 如果没有解析到任何段落，返回原始文本作为单个段落


# 预编译所有正则
_TITLE_RE = re.compile(r"^Title:\s*(.*?)\s*", re.MULTILINE | re.IGNORECASE)
_SECTION_RE = re.compile(r"^\[([^\]]+)\]\s*$", re.MULTILINE | re.IGNORECASE)


def parse_ass_dialogues(ass_content: str) -> tuple[list[tuple[FSLyricsLine, str]], dict[str, str]]:
    """解析ASS文件内容为dialogues数据"""
    tags = {}
    dialogues: list[tuple[FSLyricsLine, str]] = []

    if title_match := _TITLE_RE.search(ass_content):
        tags["title"] = title_match.group(1)

    # 段落分割逻辑
    sections = _SECTION_RE.split(ass_content)

    # 提取事件头处理逻辑
    def get_events_header() -> str:
        for i in range(1, len(sections), 2):
            if sections[i].lower() == "events":
                return sections[i + 1].strip()
        return ""

    events_header = get_events_header()
    if not events_header:
        return dialogues, tags

    # 获取格式字段
    def parse_format_fields(header: str) -> dict[str, int]:
        format_line = next((ln for ln in header.split("\n") if ln.lower().startswith("format:")), "")
        fields = [f.strip().lower() for f in format_line[len("Format:") :].split(",")]
        return {f: idx for idx, f in enumerate(fields)}

    field_map = parse_format_fields(events_header)
    if not all(k in field_map for k in ["start", "end", "style", "text"]):
        return dialogues, tags

    # 歌词行解析
    for line in events_header.splitlines():
        if not line.lower().startswith("dialogue:"):
            continue

        parts = [p.strip() for p in line[len("Dialogue:") :].split(",", maxsplit=len(field_map) - 1)]
        try:
            start = parse_ass_time(parts[field_map["start"]])
            end = parse_ass_time(parts[field_map["end"]])
            style = parts[field_map["style"]].lower()
            text = parts[field_map["text"]]
        except (IndexError, ValueError):
            continue

        # 加强时间处理
        words = []
        current_time = start
        total_duration = end - start

        for duration, text_block in parse_karaoke_tags(text):
            block_duration = total_duration if duration == 0 else min(duration, end - current_time)

            if block_duration <= 0:
                continue

            # 将整个文本块作为一个单词处理
            words.append(
                FSLyricsWord(
                    start=current_time,
                    end=current_time + block_duration,
                    text=text_block,
                ),
            )
            current_time += block_duration
        dialogues.append(
            (
                FSLyricsLine(start=start, end=end, words=words),
                style,
            ),
        )
    return dialogues, tags


def ass2fsmdata(ass_content: str) -> tuple[dict[str, str], FSMultiLyricsData]:
    """解析ASS文件内容为FSMultiLyricsData"""
    dialogues, tags = parse_ass_dialogues(ass_content)
    # 多语言处理逻辑
    styles = {style for _, style in dialogues}
    if "Script generated by LDDC" in ass_content and styles <= {"orig", "ts", "roma"}:
        lang_data = {
            lang: FSLyricsData(
                sorted(
                    [line for line, s in dialogues if s == lang],
                    key=lambda x: x.start,
                ),
            )
            for lang in styles
        }
        return tags, FSMultiLyricsData(lang_data)

    # 歌词行起始时间相同 ——> 不同语言类型
    datas_times: list[tuple[FSLyricsData, list[int]]] = []
    for line, _s in dialogues:
        for data, times in datas_times:
            if line.start not in times:
                data.append(line)
                times.append(line.start)
                break
        else:
            datas_times.append((FSLyricsData([line]), [line.start]))

    # 按时间排序
    for data, _times in datas_times:
        data.sort(key=lambda x: x.start)
    # 推测语言类型
    if not datas_times:
        return tags, FSMultiLyricsData({})
    if len(datas_times) == 1:
        return tags, FSMultiLyricsData({"orig": datas_times[0][0]})

    if len(datas_times) == 2:
        if judge_lyrics_type(datas_times[0][0]) == LyricsType.VERBATIM and judge_lyrics_type(datas_times[1][0]) == LyricsType.VERBATIM:
            return tags, FSMultiLyricsData({"roma": datas_times[0][0], "orig": datas_times[1][0]})
        return tags, FSMultiLyricsData({"orig": datas_times[0][0], "ts": datas_times[1][0]})
    return tags, FSMultiLyricsData({"roma": datas_times[0][0], "orig": datas_times[1][0], "ts": datas_times[2][0]})


def ass2mdata(ass_content: str) -> tuple[dict[str, str], MultiLyricsData]:
    tag, fsdata = ass2fsmdata(ass_content)
    return tag, MultiLyricsData(
        {
            lang: LyricsData(
                [LyricsLine(line.start, line.end, [LyricsWord(word.start, word.end, word.text) for word in line.words]) for line in fsdata[lang]],
            )
            for lang in fsdata
        },
    )


def ass2fsdata(ass_content: str) -> tuple[dict[str, str], FSLyricsData]:
    """解析ASS文件内容为FSLyricsData"""
    dialogues, tags = parse_ass_dialogues(ass_content)
    return tags, FSLyricsData([line for line, style in dialogues])


def ass2data(ass_content: str) -> tuple[dict[str, str], LyricsData]:
    """解析ASS文件内容为LyricsData"""
    dialogues, tags = parse_ass_dialogues(ass_content)
    return tags, LyricsData(
        [LyricsLine(line.start, line.end, [LyricsWord(word.start, word.end, word.text) for word in line.words]) for line, style in dialogues],
    )
