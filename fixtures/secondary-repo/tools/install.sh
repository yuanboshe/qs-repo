#!/bin/bash

# @description Fixture: one-segment template reuse inside a secondary repo.
# @step Reuse secondary/tools after secondary/tools/check.sh.
# @shell bash

SECONDARY_INSTALL_MODE="{{.secondary_install_mode}}"

main() {
  echo "secondary_install_mode=${SECONDARY_INSTALL_MODE}"
}

main
