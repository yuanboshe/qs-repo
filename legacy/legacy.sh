#!/bin/bash

# @description Fixture: legacy arg and arg/template config compatibility.
# @step Read implicit self-reference args.
# @step Apply legacy/config.yaml and recipe overrides.
# @platform linux/ubuntu>=24.04 linux/debian>=12
# @shell bash
# @requires bash
# @effects command-run

LEGACY_COMMON="{{.legacy_common}}"
LEGACY_TEMPLATE="{{.legacy_template}}"
LEGACY_RECIPE="{{.legacy_recipe}}"

main() {
  echo "legacy_common=${LEGACY_COMMON}"
  echo "legacy_template=${LEGACY_TEMPLATE}"
  echo "legacy_recipe=${LEGACY_RECIPE}"
}

main
