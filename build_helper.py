# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import argparse
import time

from LDDC.utils.version import __version__, parse_version

parser = argparse.ArgumentParser()
parser.add_argument('--task', choices=['get_version', 'get_year'], required=True)
arg = parser.parse_args()

num_version = ".".join(str(i) for i in parse_version(__version__)[:3])

year = time.strftime("%Y")
if year != '2024':
    year = "2024-" + year

match arg.task:
    case 'get_version':
        print(__version__)
    case 'get_num_version':
        print(num_version)
    case 'get_year':
        print(year)
