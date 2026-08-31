#!/usr/bin/env bash
# x-cmd-action/ai/reply — react + reply on keyword match

set -euo errexit

: "${INPUT_KEYWORD:=@x}"
: "${INPUT_REACTION:=eyes}"
: "${INPUT_COMMENT:=👀 on it}"
: "${ISSUE_NUM:?ISSUE_NUM required}"

# ── Strict keyword match (word boundary) ──
KEYWORD_RE_ESCAPED=$(printf '%s' "$INPUT_KEYWORD" | sed 's/[][\.*^$()+?{|/]/\\&/g')
PATTERN="(^|[^a-zA-Z0-9_-])${KEYWORD_RE_ESCAPED}([^a-zA-Z0-9_-]|$)"

SHOULD_TRIGGER=false

case "${GITHUB_EVENT_NAME:-}" in
  issue_comment)
    if printf '%s' "${COMMENT_BODY:-}" | grep -qE "$PATTERN"; then
      SHOULD_TRIGGER=true
    fi
    ;;
  issues)
    if printf '%s' "${ISSUE_BODY:-}" | grep -qE "$PATTERN"; then
      SHOULD_TRIGGER=true
    fi
    ;;
esac

if [ "$SHOULD_TRIGGER" = false ]; then
  echo "reply: keyword '$INPUT_KEYWORD' not found (strict match), skipping"
  exit 0
fi

echo "reply: triggered on $GITHUB_EVENT_NAME for issue #$ISSUE_NUM"

TARGET_DESC="issue #$ISSUE_NUM"
REACTION_PATH="repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUM/reactions"

if [ -n "${COMMENT_ID:-}" ] && [ "${GITHUB_EVENT_NAME}" = "issue_comment" ]; then
  REACTION_PATH="repos/$GITHUB_REPOSITORY/issues/comments/$COMMENT_ID/reactions"
  TARGET_DESC="comment #$COMMENT_ID"
fi

echo "reply: target=$TARGET_DESC"

EXISTING=$(gh api "$REACTION_PATH" --jq "[.[] | select(.content == \"$INPUT_REACTION\")] | length" 2>/dev/null || echo 0)

if [ "${EXISTING:-0}" -gt 0 ]; then
  echo "reply: $TARGET_DESC already has :$INPUT_REACTION: (count=$EXISTING), skipping"
  exit 0
fi

gh api -X POST "$REACTION_PATH" \
  -f content="$INPUT_REACTION" 2>/dev/null && \
  echo "reply: added :$INPUT_REACTION: on $TARGET_DESC" || \
  echo "reply: failed to add reaction (may already exist)"

COMMENT_BODY="$INPUT_COMMENT

<sub>Replied by [x-cmd-action/ai](https://github.com/x-cmd-action/ai)</sub>"

gh issue comment "$ISSUE_NUM" --body "$COMMENT_BODY" && \
  echo "reply: posted reply"

echo "reply: done"