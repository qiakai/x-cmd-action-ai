#!/usr/bin/env bash
# x-cmd-action/ai/commit — Conventional Commits check/generate (stub — TBD)

set -euo errexit

: "${INPUT_MODEL:=minimax}"
: "${INPUT_MODE:?mode required (check|generate)}"

echo "commit: mode=$INPUT_MODE (TODO: implement)"