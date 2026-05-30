#!/bin/bash

# @description Fixture: multi-level relative template ID without explicit repo name.
# @platform linux/ubuntu>=24.04 linux/debian>=12
# @shell bash
# @requires bash
# @effects command-run

# @arg Frontend value should be overridden by recipe.
FRONTEND_ONLY="template-frontend"

APP_ONLY="{{.app_only}}"
ROOT_ONLY="{{.root_only}}"

main() {
  echo "frontend_only=${FRONTEND_ONLY}"
  echo "app_only=${APP_ONLY}"
  echo "root_only=${ROOT_ONLY}"
}

main
