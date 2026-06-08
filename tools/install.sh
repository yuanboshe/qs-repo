#!/bin/bash

# @description Fixture: duplicate install basename and argument edge cases.
# @step Preserve an explicit empty string default over config.yaml defaults.
# @step Preserve self-reference argument declaration for recipe overrides.
# @platform linux/ubuntu>=22.04 linux/debian>=12
# @shell bash
# @requires bash
# @effects command-run file-write

# @arg Empty string default should override config.yaml.
EMPTY_VALUE=""

# @arg Self-reference has no template default but can be set by config or recipe.
SELF_REFERENCE_VALUE="{{.self_reference_value}}"

# @arg Unquoted assignment should keep the unquoted style after render.
INSTALL_MODE=auto

main() {
  echo "empty_value=${EMPTY_VALUE}"
  echo "self_reference_value=${SELF_REFERENCE_VALUE}"
  echo "install_mode=${INSTALL_MODE}"
}

main
