#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export OLLAMA_HOST=127.0.0.1:11434
export OLLAMA_NO_CLOUD=1
export OLLAMA_NOHISTORY=1
if [ -x .local-runtime/ollama ]; then
  export OLLAMA_MODELS="$PWD/.local-runtime/models"
  exec .local-runtime/ollama serve
fi
exec ollama serve
