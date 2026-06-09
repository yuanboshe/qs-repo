#!/bin/bash
# @qs template

# @description Run a local QS smoke check against a repo, search index and recipe render output.
# @step Verify the qs executable is available.
# @step Inspect the repo as JSON.
# @step Search the repo through the local repo source.
# @step Render the recipe to a reviewable smoke output script.
# @platform linux/ubuntu>=22.04 linux/debian>=12 linux/alpine>=3.19 darwin
# @shell bash
# @requires bash dirname mkdir
# @effects command-run file-write

# @arg QS executable to use for the smoke check.
QS_BIN="qs"

# @arg Repo path inspected and searched by the smoke check.
QS_REPO_PATH="."

# @arg Recipe path rendered by the smoke check.
QS_RECIPE_PATH="./recipe.yaml"

# @arg Output path for the rendered smoke script.
QS_SMOKE_OUTPUT="_tmp/qs-smoke-rendered.sh"

# @arg Search query used to verify local repo discovery.
QS_SEARCH_QUERY="qs"

main() {
  if ! command -v "${QS_BIN}" >/dev/null 2>&1; then
    echo "qs executable not found: ${QS_BIN}" >&2
    return 1
  fi

  mkdir -p "$(dirname "${QS_SMOKE_OUTPUT}")"

  echo "QS version:"
  "${QS_BIN}" version

  echo "Inspecting repo ${QS_REPO_PATH}"
  "${QS_BIN}" inspect "${QS_REPO_PATH}" --json >/dev/null

  echo "Searching repo ${QS_REPO_PATH}"
  "${QS_BIN}" search "${QS_SEARCH_QUERY}" --repo "${QS_REPO_PATH}" --json >/dev/null

  echo "Rendering recipe ${QS_RECIPE_PATH} to ${QS_SMOKE_OUTPUT}"
  "${QS_BIN}" render "${QS_RECIPE_PATH}" -o "${QS_SMOKE_OUTPUT}" --ghx-shim=off
}

main "$@"
