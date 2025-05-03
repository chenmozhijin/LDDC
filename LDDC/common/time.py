# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
def time2ms(m: int | str, s: int | str, ms: int | str) -> int:
    """时间转毫秒"""
    if isinstance(ms, str) and len(ms) == 2:  # 同时支持两位和三位毫秒
        ms += "0"
    return (int(m) * 60 + int(s)) * 1000 + int(ms)


def get_divmod_time(ms: int) -> tuple[int, int, int, int]:
    """将毫秒数分解为小时、分钟、秒和毫秒"""
    total_s, ms = divmod(ms, 1000)
    h, remainder = divmod(total_s, 3600)
    return h, *divmod(remainder, 60), ms


def ms2formattime(ms: int) -> str:
    """将毫秒数格式化为MM:SS.ms(三位毫秒)"""
    _h, m, s, ms = get_divmod_time(ms)
    return f"{int(m):02d}:{int(s):02d}.{int(ms):03d}"

def ms2roundedtime(ms: int) -> str:
    """将毫秒数格式化为MM:SS.ms(四舍五入到两位毫秒)"""
    # 四舍五入到最近的十毫秒
    rounded_total_ms = round(ms / 10) * 10
    h, m, s, rounded_ms = get_divmod_time(rounded_total_ms)
    total_m = h * 60 + m  # 合并小时到分钟
    ms_two_digit = rounded_ms // 10  # 转换为两位毫秒
    return f"{total_m:02d}:{s:02d}.{ms_two_digit:02d}"
