#!/usr/bin/env bash
# x-cmd-action/ai/triage — AI issue triage

set -euo errexit

: "${INPUT_MODEL:=minimax}"
: "${INPUT_APPLY_LABELS:=true}"
: "${ISSUE_NUM:?ISSUE_NUM required}"

echo "triage: issue #$ISSUE_NUM model=$INPUT_MODEL"

# ── Gather comments (cap at 10) ──
COMMENTS=$(gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUM/comments?per_page=10" \
  --jq '[.[] | {user: .user.login, body: .body}]' 2>/dev/null || echo '[]')

# ── Build prompt ──
PROMPT=$(cat <<EOF
You are triaging a GitHub issue. Read it and output EXACTLY this format:

type: <bug|feature|question|docs|chore>
priority: <p0|p1|p2|p3>
area: <one-word area label>
labels: <comma-separated labels>
summary: <one-line summary>

Issue #$ISSUE_NUM: $ISSUE_TITLE

$ISSUE_BODY

Comments:
$COMMENTS
EOF
)

# ── Call AI ──
echo "triage: calling $INPUT_MODEL..."
RESPONSE=$(printf '%s' "$PROMPT" | x ai request --model "$INPUT_MODEL" 2>&1) || {
  echo "triage: AI call failed: $RESPONSE"
  exit 1
}

# ── Post comment ──
COMMENT_BODY=$(cat <<EOF
🤖 **ai triage** (\`$INPUT_MODEL\`)

\`\`\`
$RESPONSE
\`\`\`

<sub>Triaged by [x-cmd-action/ai](https://github.com/x-cmd-action/ai)</sub>
EOF
)

gh issue comment "$ISSUE_NUM" --body "$COMMENT_BODY"

# ── Apply labels if requested ──
if [ "$INPUT_APPLY_LABELS" = "true" ]; then
  LABELS=$(printf '%s' "$RESPONSE" | grep -E '^labels:' | sed 's/^labels:[[:space:]]*//' || echo "")
  if [ -n "$LABELS" ]; then
    # Convert comma-separated to gh CLI args
    LABEL_ARGS=""
    IFS=',' read -ra PARTS <<< "$LABELS"
    for l in "${PARTS[@]}"; do
      l_trim=$(printf '%s' "$l" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [ -n "$l_trim" ] && LABEL_ARGS="$LABEL_ARGS --label $l_trim"
    done
    # shellcheck disable=SC2086
    gh issue edit "$ISSUE_NUM" $LABEL_ARGS 2>/dev/null || \
      echo "triage: some labels not found, applied what existed"
  fi
fi

echo "triage: done"