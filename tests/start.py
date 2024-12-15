# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import sys

import pytest

sys.exit(pytest.main(["--cov=LDDC", "--cov-report=xml", "--cov-report=html", "--cov-report=term", "--not-clear-cache"]))
