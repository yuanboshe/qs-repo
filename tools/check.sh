#!/bin/bash

# @description Fixture: template under a directory without local config.yaml.
# @step Confirm root config.yaml is still visible.
# @step Confirm no tools/config.yaml layer is required.
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
