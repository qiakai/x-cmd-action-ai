#!/usr/bin/env bash
# x-cmd-action/ai/translate — AI i18n translation
#
# NO set -e / set -u / pipefail: x-cmd source-loads `x` as a shell
# function that may `exit 1` internally — strict modes get the script
# killed by sourced functions instead of surfacing errors. Explicit
# checks and ${VAR:-defaults} are used instead.

# Resolve action dir robustly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${ACTION_PATH:=$SCRIPT_DIR}"

# The x-cmd-action/x-cmd step only installs x-cmd onto disk; each `run`
# step is a fresh shell, so the `x` function must be sourced here.
if [ ! -f "$HOME/.x-cmd.root/X" ]; then
  echo "translate: ERROR — x-cmd not installed at $HOME/.x-cmd.root/X" >&2
  exit 1
fi
. "$HOME/.x-cmd.root/X" || { echo "translate: ERROR — failed to source x-cmd" >&2; exit 1; }
command -v x >/dev/null 2>&1 || { echo "translate: ERROR — 'x' unavailable" >&2; exit 1; }

: "${INPUT_SOURCE:?source file required}"
: "${INPUT_TARGET:?target language required}"
: "${INPUT_OUTPUT:=}"   # output file path; default: <source>.<lang>.<ext>

echo "translate: source=$INPUT_SOURCE target=$INPUT_TARGET"

# ── 1. Validate source file ──
if [ ! -f "$INPUT_SOURCE" ]; then
  echo "translate: source file not found: $INPUT_SOURCE"
  exit 1
fi

# ── 2. Compute output path ──
if [ -z "$INPUT_OUTPUT" ]; then
  DIR=$(dirname "$INPUT_SOURCE")
  BASE=$(basename "$INPUT_SOURCE")
  EXT="${BASE##*.}"
  STEM="${BASE%.*}"
  INPUT_OUTPUT="$DIR/$STEM.$INPUT_TARGET.$EXT"
fi

echo "translate: output=$INPUT_OUTPUT"

# ── 3. Delegate to `x ai translate` (Markdown/code-preserving prompt is
# built in). Cap huge inputs at 3000 lines to keep prompts sane. ──
MAX=3000
TOTAL_LINES=$(wc -l < "$INPUT_SOURCE" | tr -d ' ')
if [ "$TOTAL_LINES" -gt "$MAX" ]; then
  echo "translate: WARNING — file is $TOTAL_LINES lines, truncating to $MAX"
fi

echo "translate: calling x ai translate..."
RC=0
RESPONSE=$(head -n "$MAX" "$INPUT_SOURCE" | x ai translate --to "$INPUT_TARGET" --from auto -) || RC=$?
if [ "$RC" != "0" ] || [ -z "$RESPONSE" ]; then
  echo "translate: AI call failed (rc=$RC) — see stderr output above"
  exit 1
fi

# ── 4. Write output ──
printf '%s\n' "$RESPONSE" > "$INPUT_OUTPUT"
echo "translate: written $(wc -l < "$INPUT_OUTPUT" | tr -d ' ') lines to $INPUT_OUTPUT"

echo "translate: done"
