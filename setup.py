import argparse
import time

import LDDC

parser = argparse.ArgumentParser()
parser.add_argument('--task', choices=['get_version', 'get_year'], required=True)
arg = parser.parse_args()

version = ".".join([i.split("-")[0] for i in LDDC.__version__.replace("v", "").split(".")])

year = time.strftime("%Y")
if year != '2024':
    year = "2024-" + year

match arg.task:
    case 'get_version':
        print()
    case 'get_year':
        print(year)
