#!/usr/bin/env bash
# x-cmd-action/ai/changelog — weekly changelog generator
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
  echo "changelog: ERROR — x-cmd not installed at $HOME/.x-cmd.root/X" >&2
  exit 1
fi
. "$HOME/.x-cmd.root/X" || { echo "changelog: ERROR — failed to source x-cmd" >&2; exit 1; }
command -v x >/dev/null 2>&1 || { echo "changelog: ERROR — 'x' unavailable" >&2; exit 1; }

: "${INPUT_DAYS:=7}"
: "${INPUT_OUTPUT:=comment}"   # comment | file
: "${INPUT_FILE:=CHANGELOG.md}"

echo "changelog: days=$INPUT_DAYS output=$INPUT_OUTPUT"

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
  --jq "[.[] | select(.closedAt >= \"$SINCE\")] | sort_by(.closedAt) | reverse" 2>/dev/null || echo '[]')

ISSUE_COUNT=$(printf '%s' "$ISSUES" | jq 'length' 2>/dev/null || echo 0)
echo "changelog: $ISSUE_COUNT closed issues in window"

# ── 3. Fetch merged PRs ──
PRS=$(gh pr list \
  --repo "$GITHUB_REPOSITORY" \
  --state merged \
  --limit 200 \
  --json number,title,mergedAt,labels \
  --jq "[.[] | select(.mergedAt >= \"$SINCE\")] | sort_by(.mergedAt) | reverse" 2>/dev/null || echo '[]')

PR_COUNT=$(printf '%s' "$PRS" | jq 'length' 2>/dev/null || echo 0)
echo "changelog: $PR_COUNT merged PRs in window"

if [ "$ISSUE_COUNT" -eq 0 ] && [ "$PR_COUNT" -eq 0 ]; then
  echo "changelog: nothing to summarize"
  exit 0
fi

# ── 4. Flatten to one line per change ──
CHANGE_LIST=$( {
  printf '%s' "$ISSUES" | jq -r '.[] | "- #\(.number) \(.title) (issue closed; labels: \([.labels[].name] | join(", ")))"' 2>/dev/null
  printf '%s' "$PRS" | jq -r '.[] | "- #\(.number) \(.title) (PR merged; labels: \([.labels[].name] | join(", ")))"' 2>/dev/null
} )

# ── 5. Delegate to `x ai changelog` (Keep-A-Changelog prompt is built
# in and accepts a mix of commits / closed issues / merged PRs) ──
echo "changelog: calling x ai changelog..."
RC=0
RESPONSE=$(printf '%s\n' "$CHANGE_LIST" | x ai changelog -) || RC=$?
if [ "$RC" != "0" ] || [ -z "$RESPONSE" ]; then
  echo "changelog: AI call failed (rc=$RC) — see stderr output above"
  exit 1
fi

# ── 6. Output ──
case "$INPUT_OUTPUT" in
  file)
    printf '%s\n' "$RESPONSE" > "$INPUT_FILE"
    echo "changelog: written to $INPUT_FILE"
    ;;
  comment|*)
    # Write to stdout — caller decides what to do with it.
    printf '%s\n' "$RESPONSE"
    ;;
esac

echo "changelog: done"
