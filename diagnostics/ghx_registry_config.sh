#!/bin/bash
# @qs template

# @description Print QS config, registry and GHX diagnostics without modifying global configuration.
# @step Resolve QS home, cache and project config paths from the current environment.
# @step Run qs doctor and qs ghx doctor in JSON mode when available.
# @step Optionally search a registry manifest to check registry discoverability.
# @platform linux/ubuntu>=22.04 linux/debian>=12 linux/alpine>=3.19 darwin
# @shell bash
# @requires bash
# @effects command-run
# @network github.com

# @arg QS executable used for diagnostics.
QS_BIN="qs"

# @arg QS home path to display when QS_HOME is not set.
QS_HOME_PATH="${HOME}/.qs"

# @arg Project config path to check from the current working directory.
QS_PROJECT_CONFIG=".qs/config.yaml"

# @arg Optional registry manifest source to search; leave empty to skip registry search.
QS_REGISTRY_SOURCE=""

# @arg Query used when a registry search is requested.
QS_DIAGNOSTIC_QUERY="qs"

print_path_state() {
  local label="$1"
  local path="$2"

  if [ -e "${path}" ]; then
    echo "${label}: ${path} (exists)"
  else
    echo "${label}: ${path} (missing)"
  fi
}

main() {
  local home repos files ghx runs global_config
  home="${QS_HOME:-${QS_HOME_PATH}}"
  repos="${QS_REPOS_DIR:-${home}/repos}"
  files="${QS_FILES_DIR:-${home}/files}"
  ghx="${home}/ghx"
  runs="${QS_RUNS_DIR:-${home}/runs}"
  global_config="${home}/config.yaml"

  if ! command -v "${QS_BIN}" >/dev/null 2>&1; then
    echo "qs executable not found: ${QS_BIN}" >&2
    return 1
  fi

  print_path_state "global_config" "${global_config}"
  print_path_state "project_config" "${QS_PROJECT_CONFIG}"
  print_path_state "repo_cache" "${repos}"
  print_path_state "file_cache" "${files}"
  print_path_state "ghx_cache" "${ghx}"
  print_path_state "runs_dir" "${runs}"

  echo "qs doctor:"
  "${QS_BIN}" doctor --json

  echo "qs ghx doctor:"
  "${QS_BIN}" ghx doctor --json

  if [ -n "${QS_REGISTRY_SOURCE}" ]; then
    echo "registry search: ${QS_REGISTRY_SOURCE}"
    "${QS_BIN}" search "${QS_DIAGNOSTIC_QUERY}" --registry "${QS_REGISTRY_SOURCE}" --json
  fi
}

main "$@"
