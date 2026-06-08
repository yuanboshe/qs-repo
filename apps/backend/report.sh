#!/bin/bash

# @description Fixture: one-segment template ID reuses previous repo and template directory.
# @step Reuse apps/backend context from the previous template ID.
# @step Print recipe-level report mode override.
# @platform linux/ubuntu>=24.04 linux/debian>=12
# @shell bash
# @requires bash
# @effects command-run

# @arg Report mode should be overridden by recipe template-level value.
REPORT_MODE="template-report"

SHARED="{{.shared}}"
BACKEND_ONLY="{{.backend_only}}"

main() {
  echo "report_mode=${REPORT_MODE}"
  echo "shared=${SHARED}"
  echo "backend_only=${BACKEND_ONLY}"
}

main
