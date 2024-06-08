from diskcache import Cache

from .paths import cache_dir

cache = Cache(cache_dir)
cache_version = 5
if "version" not in cache or cache["version"] != cache_version:
    cache.clear()
cache["version"] = cache_version
