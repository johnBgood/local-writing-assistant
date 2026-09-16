#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -x .local-runtime/ollama ]; then
  export PATH="$PWD/.local-runtime:$PATH"
fi
if ! command -v ollama >/dev/null 2>&1; then
  printf 'Install Ollama from https://ollama.com/download/mac, launch it, then rerun this script.\n'
  exit 1
fi
if ! curl --silent --fail http://127.0.0.1:11434/api/tags >/dev/null; then
  printf 'Start the Ollama app or run ollama serve, then rerun this script.\n'
  exit 1
fi
ollama pull qwen3:4b
