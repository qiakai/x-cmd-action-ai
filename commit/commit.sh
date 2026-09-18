#!/usr/bin/env bash
# x-cmd-action/ai/commit — Conventional Commits check/generate
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
  echo "commit: ERROR — x-cmd not installed at $HOME/.x-cmd.root/X" >&2
  exit 1
fi
. "$HOME/.x-cmd.root/X" || { echo "commit: ERROR — failed to source x-cmd" >&2; exit 1; }
command -v x >/dev/null 2>&1 || { echo "commit: ERROR — 'x' unavailable" >&2; exit 1; }

: "${INPUT_MODE:?mode required (check|generate)}"
: "${INPUT_COMMIT_LIMIT:=50}"   # max commits to check in check mode
: "${INPUT_FAIL_ON_INVALID:=true}"

echo "commit: mode=$INPUT_MODE"

case "$INPUT_MODE" in
  check)
    # ── Validate commits in current branch vs main ──
    COMMITS=$(git log "origin/main..HEAD" --pretty=format:"%H|%s" --max-count="$INPUT_COMMIT_LIMIT" 2>/dev/null || \
              git log "main..HEAD" --pretty=format:"%H|%s" --max-count="$INPUT_COMMIT_LIMIT" 2>/dev/null || \
              echo "")

    if [ -z "$COMMITS" ]; then
      echo "commit: no commits to check"
      exit 0
    fi

    # ── Pattern: Conventional Commits ──
    # type(scope)?: subject
    PATTERN='^(feat|fix|docs|style|refactor|perf|test|chore|build|ci|revert)(\([a-zA-Z0-9_-]+\))?!?: .+'

    INVALID=0
    INVALID_LIST=""
    while IFS='|' read -r hash subject; do
      if ! printf '%s' "$subject" | grep -qE "$PATTERN"; then
        INVALID=$((INVALID + 1))
        INVALID_LIST="${INVALID_LIST}- ${hash:0:7}: ${subject}
"
        echo "commit: INVALID: ${hash:0:7}: $subject"
      else
        echo "commit: OK: ${hash:0:7}: $subject"
      fi
    done <<< "$COMMITS"

    # ── Optional: delegate invalid-commit suggestions to `x ai commit --check` ──
    if [ -n "${INPUT_REVIEW_INVALID:-}" ] && [ "$INVALID" -gt 0 ]; then
      echo "commit: calling x ai commit --check for suggestions..."
      RC=0
      REVIEW=$(x ai commit --check --limit "$INPUT_COMMIT_LIMIT" 2>/dev/null) || RC=$?
      if [ "$RC" != "0" ] || [ -z "$REVIEW" ]; then
        echo "commit: AI suggestions unavailable (rc=$RC), continuing with raw invalid list"
        REVIEW=""
      fi

      COMMENT_BODY="🤖 **ai commit review**

**$INVALID of $(printf '%s' "$COMMITS" | wc -l | tr -d ' ') commits don't follow Conventional Commits.**

Invalid commits:
\`\`\`
$INVALID_LIST
\`\`\`
${REVIEW:+AI-suggested rewrites:
\`\`\`
$REVIEW
\`\`\`
}"

      gh issue comment "${INPUT_PR_NUM:-}" --repo "$GITHUB_REPOSITORY" --body "$COMMENT_BODY" 2>/dev/null || \
        echo "commit: failed to post review comment (no PR_NUM?)"
    fi

    echo "commit: $INVALID invalid commits found"

    if [ "$INVALID" -gt 0 ] && [ "$INPUT_FAIL_ON_INVALID" = "true" ]; then
      echo "commit: failing due to invalid commits"
      exit 1
    fi
    ;;

  generate)
    # ── Generate commit message from staged diff ──
    DIFF=$(git diff --cached 2>/dev/null || git diff 2>/dev/null || echo "")

    if [ -z "$DIFF" ]; then
      echo "commit: no staged changes"
      exit 1
    fi

    # ── Delegate to `x ai commit --generate --full` (full-message
    # template is built in) ──
    echo "commit: calling x ai commit --generate --full..."
    RC=0
    RESPONSE=$(x ai commit --generate --full) || RC=$?
    if [ "$RC" != "0" ] || [ -z "$RESPONSE" ]; then
      echo "commit: AI call failed (rc=$RC) — see stderr output above"
      exit 1
    fi

    # Trim leading/trailing whitespace.
    RESPONSE=$(printf '%s' "$RESPONSE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    echo "$RESPONSE" > "$GITHUB_OUTPUT_FILE" 2>/dev/null || echo "$RESPONSE"
    echo "commit: generated: $(printf '%s' "$RESPONSE" | head -1)"
    ;;

  *)
    echo "commit: invalid mode '$INPUT_MODE' (expected: check|generate)"
    exit 1
    ;;
esac

echo "commit: done"
