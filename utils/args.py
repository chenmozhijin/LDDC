# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--get-service-port", action='store_true', dest='get_service_port')
parser.add_argument("--not-show", action='store_false', dest='show')
args = parser.parse_args()
