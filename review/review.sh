#!/usr/bin/env bash
# x-cmd-action/ai/review — AI PR code review
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
  echo "review: ERROR — x-cmd not installed at $HOME/.x-cmd.root/X" >&2
  exit 1
fi
. "$HOME/.x-cmd.root/X" || { echo "review: ERROR — failed to source x-cmd" >&2; exit 1; }
command -v x >/dev/null 2>&1 || { echo "review: ERROR — 'x' unavailable" >&2; exit 1; }

: "${PR_NUM:?PR_NUM required}"
: "${MAX_DIFF_LINES:=1500}"

echo "review: PR #$PR_NUM"

# ── 1. Fetch PR description + diff ──
PR_BODY=$(gh pr view "$PR_NUM" --repo "$GITHUB_REPOSITORY" --json body --jq '.body // ""' 2>/dev/null || echo "")

DIFF=$(gh pr diff "$PR_NUM" --repo "$GITHUB_REPOSITORY" 2>/dev/null) || {
  echo "review: failed to fetch diff for PR #$PR_NUM"
  exit 1
}
[ -n "$DIFF" ] || { echo "review: empty diff for PR #$PR_NUM"; exit 1; }

# ── 2. Delegate the review to `x ai review` (structured-review prompt
# is built in; stdin carries the PR description followed by the diff) ──
echo "review: calling x ai review..."
RC=0
RESPONSE=$( {
  printf 'Pull request #%s description:\n%s\n\n---\n\n' "$PR_NUM" "$PR_BODY"
  printf '%s\n' "$DIFF"
} | x ai review --max-lines "$MAX_DIFF_LINES" - ) || RC=$?
if [ "$RC" != "0" ] || [ -z "$RESPONSE" ]; then
  echo "review: AI review failed (rc=$RC) — see stderr output above"
  exit 1
fi

# ── 3. Post PR comment ──
COMMENT_BODY="🤖 **ai review**

$RESPONSE

---
<sub>Reviewed by [x-cmd-action/ai](https://github.com/x-cmd-action/ai) · review sub-command</sub>"

gh pr comment "$PR_NUM" --repo "$GITHUB_REPOSITORY" --body "$COMMENT_BODY" && \
  echo "review: posted PR comment"

echo "review: done"
