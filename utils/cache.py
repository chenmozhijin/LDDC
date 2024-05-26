import os
import sys

from diskcache import Cache

match sys.platform:
    case "linux" | "darwin":
        cache_dir = os.path.expanduser("~/.config/LDDC/cache")
    case _:
        cache_dir = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "cache")
cache = Cache(cache_dir)
cache_version = 5
if "version" not in cache or cache["version"] != cache_version:
    cache.clear()
cache["version"] = cache_version
