#!/usr/bin/env bash
# x-cmd-action/ai/changelog — weekly changelog generator

set -euo errexit

: "${INPUT_MODEL:=minimax}"
: "${INPUT_DAYS:=7}"
: "${INPUT_OUTPUT:=comment}"   # comment | file
: "${INPUT_FILE:=CHANGELOG.md}"

echo "changelog: days=$INPUT_DAYS model=$INPUT_MODEL output=$INPUT_OUTPUT"

# ── 1. Compute since-date (N days ago, ISO 8601) ──
SINCE=$(date -u -v-"${INPUT_DAYS}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d "${INPUT_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)
echo "changelog: since=$SINCE"

# ── 2. Fetch closed issues (look back N days) ──
ISSUES=$(gh issue list \
  --repo "$GITHUB_REPOSITORY" \
  --state closed \
  --limit 200 \
  --json number,title,closedAt,labels \
  --jq "[.[] | select(.closedAt >= \"$SINCE\")] | sort_by(.closedAt) | reverse")

ISSUE_COUNT=$(printf '%s' "$ISSUES" | jq 'length')
echo "changelog: $ISSUE_COUNT closed issues in window"

# ── 3. Fetch merged PRs ──
PRS=$(gh pr list \
  --repo "$GITHUB_REPOSITORY" \
  --state merged \
  --limit 200 \
  --json number,title,mergedAt,labels \
  --jq "[.[] | select(.mergedAt >= \"$SINCE\")] | sort_by(.mergedAt) | reverse")

PR_COUNT=$(printf '%s' "$PRS" | jq 'length')
echo "changelog: $PR_COUNT merged PRs in window"

if [ "$ISSUE_COUNT" -eq 0 ] && [ "$PR_COUNT" -eq 0 ]; then
  echo "changelog: nothing to summarize"
  exit 0
fi

# ── 4. Build prompt ──
PROMPT=$(cat <<EOF
Generate a weekly changelog from the following closed issues and merged PRs.
Group by category: Features (feat), Fixes (fix), Performance (perf), Docs, Other.
For each entry: short one-liner describing the user-visible change.
End with a one-paragraph summary.

Window: last $INPUT_DAYS days (since $SINCE)

Closed Issues ($ISSUE_COUNT):
$ISSUES

Merged PRs ($PR_COUNT):
$PRS

Format:

# Changelog (last ${INPUT_DAYS} days)

## ✨ Features
- ...

## 🐛 Fixes
- ...

## ⚡ Performance
- ...

## 📝 Docs
- ...

## 🔧 Other
- ...

## Summary
<one paragraph>
EOF
)

# ── 5. Call AI ──
echo "changelog: calling $INPUT_MODEL..."
RESPONSE=$(printf '%s' "$PROMPT" | x ai request --model "$INPUT_MODEL" 2>&1) || {
  echo "changelog: AI call failed: $RESPONSE"
  exit 1
}

# ── 6. Output ──
case "$INPUT_OUTPUT" in
  file)
    echo "$RESPONSE" > "$INPUT_FILE"
    echo "changelog: written to $INPUT_FILE"
    ;;
  comment|*)
    # Post as a Discussion or issue comment.
    # For now, write to stdout — caller decides what to do.
    echo "$RESPONSE"
    ;;
esac

echo "changelog: done"