#!/bin/bash

# @description Fixture: template under a directory without local config.yaml.
# @platform linux/ubuntu>=24.04 linux/debian>=12
# @shell bash
# @requires bash
# @effects command-run

ROOT_ONLY="{{.root_only}}"
SHARED="{{.shared}}"

main() {
  echo "root_only=${ROOT_ONLY}"
  echo "shared=${SHARED}"
}

main
