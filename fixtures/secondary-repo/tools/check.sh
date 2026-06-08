#!/bin/bash
# @qs template

# @description Fixture: secondary repo template for multi-repo recipes.
# @step Prove a recipe can select templates from a second repo path.
# @shell bash

SECONDARY_VALUE="{{.secondary_value}}"

main() {
  echo "secondary_value=${SECONDARY_VALUE}"
}

main
