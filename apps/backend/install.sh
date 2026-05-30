#!/bin/bash

# @description Fixture: full template ID, multi-level config, template default and recipe overrides.
# @platform linux/ubuntu>=24.04 linux/debian>=12
# @shell bash
# @requires bash
# @effects command-run

# @arg Template default should override shared from config.yaml.
SHARED="template-shared"

# @arg Template default should override backend config.
TEMPLATE_ONLY="template-default"

# @arg Template default should be overridden by recipe template-level value.
RECIPE_OVERRIDE="template-default"

ROOT_ONLY="{{.root_only}}"
APP_ONLY="{{.app_only}}"
BACKEND_ONLY="{{.backend_only}}"
DIR_ONLY="{{.dir_only}}"
REPO_ONLY="{{.repo_only}}"

main() {
  echo "shared=${SHARED}"
  echo "root_only=${ROOT_ONLY}"
  echo "app_only=${APP_ONLY}"
  echo "backend_only=${BACKEND_ONLY}"
  echo "dir_only=${DIR_ONLY}"
  echo "repo_only=${REPO_ONLY}"
  echo "template_only=${TEMPLATE_ONLY}"
  echo "recipe_override=${RECIPE_OVERRIDE}"
}

main
