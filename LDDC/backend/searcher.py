# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from typing import Any

import requests

from LDDC.utils.cache import cache
from LDDC.utils.enum import SearchType, Source

from .api import (
    kg_search,
    ne_search,
    qm_search,
)


def search(keyword: str,
           search_type: SearchType,
           source: Source,
           info: dict[str, str | int] | None = None,
           page: int = 1) -> list[dict[str, Any]]:

    cache_key = (search_type, source, keyword, info, page)
    results = cache.get(cache_key)
    if results is not None and isinstance(results, list):
        return results
    results = []
    error = Exception

    for _i in range(3):
        try:
            match source:
                case Source.QM:
                    if search_type != SearchType.LYRICS and keyword is not None:
                        results = qm_search(keyword, search_type, page)
                    else:
                        raise NotImplementedError

                case Source.NE:
                    if search_type != SearchType.LYRICS and keyword is not None:
                        results = ne_search(keyword, search_type, page)
                    else:
                        raise NotImplementedError

                case Source.KG:
                    if search_type == SearchType.LYRICS and info:
                        results = kg_search(keyword=keyword, info=info, search_type=SearchType.LYRICS)
                        results = [{**info, **item, "duration": info["duration"]} for item in results]
                    elif search_type != SearchType.LYRICS:
                        results = kg_search(keyword=keyword, search_type=search_type, page=page)
                    else:
                        raise NotImplementedError

                case _:
                    raise NotImplementedError

        except (requests.Timeout, requests.RequestException) as e:  # noqa: PERF203
            error = e
            continue
        else:
            break
    else:
        raise error

    if results:
        cache.set(cache_key, results, 216000)
    return results
