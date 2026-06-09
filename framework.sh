#!/bin/bash
# @qs framework
set -euo pipefail

{{range $template := .templates}}
echo
echo "===== {{$template.templateId}} ====="
{{$template.content}}
{{end}}
