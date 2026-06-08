#!/bin/bash

# @step Read platform and shell metadata from parent config.yaml files.
# @step Read requires and effects from apps/backend/config.yaml.
# @step Verify apps/backend/config.yaml clears inherited network metadata.

# @arg Metadata note inherited from apps/backend/config.yaml.
METADATA_NOTE="{{.metadata_note}}"

main() {
  echo "metadata_note=${METADATA_NOTE}"
}

main
