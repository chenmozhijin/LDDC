# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re


def get_last_release(repo: str) -> tuple[str, str]:
    """获取指定GitHub仓库的最新发布版本

    Args:
        repo (str): GitHub仓库地址

    Returns:
        tuple[str, str]: (版本号, body)

    """
    import httpx

    repo = repo.removeprefix("https://github.com/")
    if repo.count("/") != 1 or not re.fullmatch(r"^[A-Za-z_0-9\-]+$", repo.replace("/", "")):
        msg = "仓库地址不合法"
        raise ValueError(msg)
    latest_release = httpx.get(f"https://api.github.com/repos/{repo}/releases/latest").json()
    if "tag_name" in latest_release and "body" in latest_release:
        latest_version = latest_release["tag_name"]
        body = latest_release["body"]
        return latest_version, body
    msg = "获取最新版本失败"
    raise ValueError(msg)
