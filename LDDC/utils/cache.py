# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from diskcache import Cache

from .paths import cache_dir

cache = Cache(cache_dir, sqlite_cache_size=512)
cache_version = 5
if "version" not in cache or cache["version"] != cache_version:
    cache.clear()
cache["version"] = cache_version
