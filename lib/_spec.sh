#!/usr/bin/env bash
# x-cmd-action/ai/spec — RFC template / post-mortem extractor (stub — TBD)

set -euo errexit

: "${INPUT_MODEL:=minimax}"
: "${INPUT_MODE:?mode required (rfc|postmortem)}"
: "${ISSUE_NUM:?ISSUE_NUM required}"

echo "spec: mode=$INPUT_MODE issue=#$ISSUE_NUM (TODO: implement)"