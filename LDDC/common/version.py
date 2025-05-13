# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

"""版本信息与处理模块"""

__version__ = "v0.9.1"
import re
from typing import Literal


def parse_version(version: str) -> tuple[int, int, int, str, str]:
    """将语义化版本字符串解析为主版本号、次版本号、修订号、先行版本号和版本编译信息。"""
    pattern = r'^v?(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)(?:-(?P<prerelease>[0-9A-Za-z\-.]+))?(?:\+(?P<build>[0-9A-Za-z\-.]+))?$'
    match = re.match(pattern, version)
    if not match:
        msg = f"Invalid version format: {version}"
        raise ValueError(msg)

    major, minor, patch = int(match.group('major')), int(match.group('minor')), int(match.group('patch'))
    prerelease = match.group('prerelease')
    build = match.group('build')

    return major, minor, patch, prerelease, build


def compare_identifiers(id1: str, id2: str) -> Literal[-1, 0, 1]:
    """比较单个先行版本号标识符,支持数值和非数值比较。

    返回值:
    - 1: 如果 id1 > id2
    - -1: 如果 id1 < id2
    - 0: 如果 id1 == id2
    """
    if id1.isdigit() and id2.isdigit():
        num1, num2 = int(id1), int(id2)
        if num1 > num2:
            return 1
        if num1 < num2:
            return -1
        return 0
    if id1.isdigit():
        return -1  # 数字标识符优先级低于非数字标识符
    if id2.isdigit():
        return 1   # 非数字标识符优先级高于数字标识符
    if id1 > id2:
        return 1
    if id1 < id2:
        return -1
    return 0


def compare_versions(version1: str, version2: str) -> Literal[-1, 0, 1]:
    """比较两个语义化版本号,包括主版本号、次版本号、修订号和先行版本号。

    返回值:
    - 1: 如果 version1 > version2
    - -1: 如果 version1 < version2
    - 0: 如果 version1 == version2
    """
    v1 = parse_version(version1)
    v2 = parse_version(version2)

    # 比较主版本号、次版本号和修订号
    for i in range(3):
        if v1[i] != v2[i]:
            return (v1[i] > v2[i]) - (v1[i] < v2[i])  # type: ignore[]

    # 比较先行版本号(prerelease),空的先行版本号比任何非空先行版本号优先级高
    if v1[3] is None and v2[3] is None:
        return 0
    if v1[3] is None:
        return 1
    if v2[3] is None:
        return -1

    id1 = v1[3].split('.')
    id2 = v2[3].split('.')

    for sub_id1, sub_id2 in zip(id1, id2, strict=False):
        result = compare_identifiers(sub_id1, sub_id2)
        if result != 0:
            return result

    # 确保返回值在 -1, 0, 1 之间
    if len(id1) > len(id2):
        return 1
    if len(id1) < len(id2):
        return -1
    return 0
