# x-cmd-action/ai

AI actions for GitHub Issues & PRs. Each subcommand maps 1:1 to `x ai <subcmd>`.

## Overview

`x-cmd-action/ai` is a **single repository** that exposes **seven sub-commands**, each
addressable as its own composite GitHub Action. The design principle:

> **Local-first.** If a user can run `x ai triage` on their laptop, the same workflow
> should run in CI with zero changes — only the trigger changes (manual vs `issues: opened`).

The seven sub-commands together form an **IssueOps & DevProd toolkit**:

| Action reference | Local command | Core job |
|---|---|---|
| `x-cmd-action/ai/triage@v1` | `x ai triage` | Auto-classify new issues: type + priority + labels |
| `x-cmd-action/ai/reply@v1` | `x ai reply` | React + reply when `@keyword` is mentioned |
| `x-cmd-action/ai/review@v1` | `x ai review` | AI code review on PR diff (security + style + summary) |
| `x-cmd-action/ai/changelog@v1` | `x ai changelog` | Weekly community update from closed issues + merged PRs |
| `x-cmd-action/ai/translate@v1` | `x ai translate` | AI i18n translation for Markdown / locale files |
| `x-cmd-action/ai/spec@v1` | `x ai spec` | RFC template fill-in + post-mortem extraction |
| `x-cmd-action/ai/commit@v1` | `x ai commit` | Conventional Commits check / generate |

## Architecture

```
x-cmd-action/ai/
├── triage/                  # AI issue triage
│   ├── action.yml
│   └── triage.sh
├── reply/                   # React + reply on @keyword
│   ├── action.yml
│   └── reply.sh
├── review/                  # AI PR code review
│   ├── action.yml
│   └── review.sh
├── changelog/               # Weekly changelog
│   ├── action.yml
│   └── changelog.sh
├── translate/               # AI i18n
│   ├── action.yml
│   └── translate.sh
├── spec/                    # RFC + post-mortem
│   ├── action.yml
│   └── spec.sh
├── commit/                  # Conventional Commits
│   ├── action.yml
│   └── commit.sh
└── .gitattributes
```

### Design choices

1. **One repo, seven sub-commands.** Each sub-command lives in its own subdirectory
   with its own `action.yml`. This gives users a clean `uses:` reference
   (`x-cmd-action/ai/triage@v1`) without forcing them to pass a discriminator
   input (`task: triage`).

2. **Flat structure — no `lib/`.** Each sub-command is self-contained: an
   `action.yml` and exactly one shell script. Sharing is avoided by extracting
   the only common dependency (`x-cmd` install) into a **separate composite action**:
   [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd).

3. **`x-cmd-action/x-cmd` is the single base dependency.** Every sub-command's
   first step is `- uses: x-cmd-action/x-cmd@v1`. This action installs `x-cmd`
   into `~/.x-cmd.root/` and sources `X` so the rest of the steps have access
   to `x ai`, `x gh`, `x minimax`, etc.

4. **Pure shell, no Node.js.** All scripts are POSIX `bash`. No `npm install`,
   no dependency tree, fast cold-start.

5. **AI token via env, not action input.** The token is read from
   `MINIMAX_TOKEN` env var (passed via `secrets.MINIMAX_TOKEN`). Local equivalent:
   `x minimax --cfg apikey=...`.

### Dependency graph

```
x-cmd-action/ai/<subcmd>   ──┐
x-cmd-action/<other>        ──┤── uses ──> x-cmd-action/x-cmd
                              │
                              └── uses ──> actions/checkout  (optional, only when repo files needed)
```

## Quick start

### Triage new issues

```yaml
# .github/workflows/triage.yml
name: triage
on:
  issues:
    types: [opened]
jobs:
  triage:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - uses: x-cmd-action/ai/triage@v1
        with:
          model: minimax
          apply-labels: 'true'
        env:
          MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### React + reply on `@x`

```yaml
# .github/workflows/aireply.yml
name: aireply
on:
  issue_comment:
    types: [created]
  issues:
    types: [opened]
concurrency:
  group: aireply-bot
  cancel-in-progress: false
jobs:
  reply:
    if: github.event.sender.type != 'Bot'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - uses: x-cmd-action/ai/reply@v1
        with:
          keyword: '@x'
          reaction: eyes
          comment: '👀 on it'
```

### AI PR review

```yaml
# .github/workflows/ai-review.yml
name: ai-review
on:
  pull_request:
    types: [opened, synchronize]
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: x-cmd-action/ai/review@v1
        env:
          MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### Weekly changelog (cron)

```yaml
# .github/workflows/weekly-changelog.yml
name: weekly-changelog
on:
  schedule:
    - cron: '0 9 * * 1'  # Mon 9am UTC
  workflow_dispatch:
jobs:
  changelog:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: x-cmd-action/ai/changelog@v1
        with:
          days: 7
        env:
          MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

## Why a single repo?

| Approach | Pros | Cons |
|---|---|---|
| **One repo per sub-command** (e.g. `x-cmd-action/ai-triage`) | Familiar; one repo per release | 7 repos, 7 v1 tags, 7 CI; install x-cmd 7 times |
| **One repo, sub-path actions** ✅ this | One v1 tag, one CI; user picks by `uses:` path | Slightly less obvious naming |
| **One repo, single action + `task` input** | Simplest repo layout | Users pass `with: task: triage`; breaks 1:1 with `x ai triage` |

We chose the sub-path approach because it preserves **1:1 mapping** between
local (`x ai triage`) and remote (`x-cmd-action/ai/triage@v1`), which is the
core design promise.

## Configuration

All sub-commands accept `model` (default `minimax`). Token: `MINIMAX_TOKEN`
env var. To use a different provider, run `x minimax --cfg ...` once after
install, or set the model input to `openai:gpt-4`, `anthropic:claude-fable-5`,
etc. (provider routing handled by `x ai request`).

## Tarball policy

`.gitattributes` strips:

```
.gitattributes    export-ignore
.github           export-ignore
*.md              export-ignore
```

So `git archive` (used by `uses: x-cmd-action/ai/<subcmd>@v1`) ships only:

```
triage/action.yml + triage/triage.sh
reply/action.yml + reply/reply.sh
...
```

Nothing else. ~16 KB per sub-command.

## License

Apache-2.0. See [LICENSE](https://github.com/x-cmd-action/ai/blob/main/LICENSE).