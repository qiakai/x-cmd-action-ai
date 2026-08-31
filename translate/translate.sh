#!/usr/bin/env bash
# x-cmd-action/ai/translate — AI i18n translation

set -euo errexit

: "${INPUT_MODEL:=minimax}"
: "${INPUT_SOURCE:?source file required}"
: "${INPUT_TARGET:?target language required}"
: "${INPUT_OUTPUT:-}"   # output file path; default: <source>.<lang>.<ext>

echo "translate: source=$INPUT_SOURCE target=$INPUT_TARGET model=$INPUT_MODEL"

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

# ── 3. Read source ──
SOURCE_CONTENT=$(cat "$INPUT_SOURCE")

# Truncate huge files to keep prompts sane.
SOURCE_LINES=$(printf '%s\n' "$SOURCE_CONTENT" | wc -l | tr -d ' ')
MAX=3000
if [ "$SOURCE_LINES" -gt "$MAX" ]; then
  echo "translate: WARNING — file is $SOURCE_LINES lines, truncating to $MAX"
  SOURCE_CONTENT=$(printf '%s\n' "$SOURCE_CONTENT" | head -n "$MAX")
  SOURCE_CONTENT="$SOURCE_CONTENT

(... truncated)"
fi

# ── 4. Build prompt ──
PROMPT=$(cat <<EOF
Translate the following file content to language code "$INPUT_TARGET".
Preserve Markdown formatting, code blocks (don't translate code), URLs, and proper nouns.
Keep technical terms (API, GitHub, JSON, etc.) in English if no standard translation exists.
Adapt culturally (e.g. "### Summary" in English becomes "### 概述" in zh-CN).

File: $INPUT_SOURCE
Target language: $INPUT_TARGET

Content:

\`\`\`
$SOURCE_CONTENT
\`\`\`

Output ONLY the translated content. No preamble, no commentary.
EOF
)

# ── 5. Call AI ──
echo "translate: calling $INPUT_MODEL..."
RESPONSE=$(printf '%s' "$PROMPT" | x ai request --model "$INPUT_MODEL" 2>&1) || {
  echo "translate: AI call failed: $RESPONSE"
  exit 1
}

# Strip AI's wrapping if it added ``` fences.
RESPONSE=$(printf '%s' "$RESPONSE" | sed -e 's/^```[a-zA-Z]*$//' -e 's/^```$//')

# ── 6. Write output ──
printf '%s\n' "$RESPONSE" > "$INPUT_OUTPUT"
echo "translate: written $(wc -l < "$INPUT_OUTPUT" | tr -d ' ') lines to $INPUT_OUTPUT"

echo "translate: done"