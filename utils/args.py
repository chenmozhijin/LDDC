import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--get-service-port", action='store_true', dest='get_service_port')
parser.add_argument("--not-show", action='store_false', dest='show')
args = parser.parse_args()
