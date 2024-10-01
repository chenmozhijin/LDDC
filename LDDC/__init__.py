# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from .backend.fetcher import get_lyrics
from .backend.searcher import search
from .utils.version import __version__

__all__ = ["get_lyrics", "search", "__version__"]
__author__ = "沉默の金"
__license__ = "GPL-3.0-only"
__copyright__ = "Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>"
