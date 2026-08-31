#!/usr/bin/env bash
# x-cmd-action/ai/review — AI PR code review (stub — TBD)

set -euo errexit

: "${INPUT_MODEL:=minimax}"
: "${PR_NUM:?PR_NUM required}"

echo "review: PR #$PR_NUM model=$INPUT_MODEL (TODO: implement)"