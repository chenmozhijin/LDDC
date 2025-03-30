# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import argparse
import sys


class Args:
    def __init__(self) -> None:
        self.get_service_port = False
        self.show = False

    def parse(self) -> None:
        parser = argparse.ArgumentParser()
        parser.add_argument("--get-service-port", action='store_true', dest='get_service_port')
        parser.add_argument("--not-show", action='store_false', dest='show')
        args = parser.parse_args()
        self.get_service_port = args.get_service_port
        self.show = args.show


args = Args()
main_module = sys.modules["__main__"]
if hasattr(main_module, 'name') and main_module.name == "LDDC":
    args.parse()
    running_lddc = True
else:
    running_lddc = False
