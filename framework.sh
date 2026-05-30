#!/bin/bash
set -euo pipefail

{{range $template := .templates}}
echo "===== {{$template.templateId}} ====="
{{$template.content}}

{{end}}
