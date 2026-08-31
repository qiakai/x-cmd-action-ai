#!/usr/bin/env bash
# x-cmd-action/ai/review — AI PR code review

set -euo errexit

: "${INPUT_MODEL:=minimax}"
: "${PR_NUM:?PR_NUM required}"
: "${MAX_DIFF_LINES:=1500}"

echo "review: PR #$PR_NUM model=$INPUT_MODEL"

# ── 1. Fetch PR diff ──
DIFF=$(gh pr diff "$PR_NUM" --repo "$GITHUB_REPOSITORY" 2>/dev/null) || {
  echo "review: failed to fetch diff for PR #$PR_NUM"
  exit 1
}

# Truncate huge diffs to keep prompts sane.
DIFF_LINES=$(printf '%s' "$DIFF" | wc -l)
if [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
  echo "review: diff is $DIFF_LINES lines, truncating to $MAX_DIFF_LINES"
  DIFF=$(printf '%s' "$DIFF" | head -n "$MAX_DIFF_LINES")
  DIFF="$DIFF

(... truncated, $DIFF_LINES total lines)"
fi

# ── 2. Fetch PR description + comments ──
PR_BODY=$(gh pr view "$PR_NUM" --repo "$GITHUB_REPOSITORY" --json body --jq '.body // ""')

# ── 3. Build prompt ──
PROMPT=$(cat <<EOF
You are reviewing a GitHub Pull Request. Output a structured review.

PR #$PR_NUM:
$PR_BODY

Diff:
\`\`\`diff
$DIFF
\`\`\`

Format your response EXACTLY as:

## Overall
<one-line verdict: LGTM | NEEDS WORK | BLOCKING>

## Security
<bullet list of security issues, or 'No issues found.'>

## Style
<bullet list of style issues, or 'No issues found.'>

## Suggestions
<bullet list of optional improvements, or 'None.'>

## Summary
<2-3 line summary of the change>
EOF
)

# ── 4. Call AI ──
echo "review: calling $INPUT_MODEL..."
RESPONSE=$(printf '%s' "$PROMPT" | x ai request --model "$INPUT_MODEL" 2>&1) || {
  echo "review: AI call failed: $RESPONSE"
  exit 1
}

# ── 5. Post PR comment ──
COMMENT_BODY=$(cat <<EOF
🤖 **ai review** (\`$INPUT_MODEL\`)

$RESPONSE

---
<sub>Reviewed by [x-cmd-action/ai](https://github.com/x-cmd-action/ai) · review sub-command</sub>
EOF
)

gh pr comment "$PR_NUM" --repo "$GITHUB_REPOSITORY" --body "$COMMENT_BODY"

echo "review: posted PR comment"

# ── 6. Optional: store to mneme for future retrieval ──
# (only if MNEME_KEY is provided)
if [ -n "${MNEME_KEY:-}" ]; then
  echo "review: storing to mneme (key=$MNEME_KEY)"
  # Future: integrate with x-cmd-action/mneme@v1
fi

echo "review: done"