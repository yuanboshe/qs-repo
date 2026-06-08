#!/bin/bash
# @qs framework
set -euo pipefail

echo "strict framework start"
{{range $template := .templates}}
echo "===== strict {{$template.templateId}} ====="
{{$template.content}}

{{end}}
echo "strict framework end"
