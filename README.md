# x-cmd-action/ai

> AI toolkit for GitHub Issues & PRs — seven sub-commands, each maps 1:1 to `x ai <subcmd>`. Pure shell, no Node.js. Triggered by GitHub events.

[中文文档](./README.cn.md)

## What it is

A **single repository** that exposes seven AI sub-commands. Each sub-command is a separate composite GitHub Action referenceable by path:

```
x-cmd-action/ai/triage@v1       →  x ai triage
x-cmd-action/ai/reply@v1        →  x ai reply
x-cmd-action/ai/review@v1       →  x ai review
x-cmd-action/ai/changelog@v1    →  x ai changelog
x-cmd-action/ai/translate@v1    →  x ai translate
x-cmd-action/ai/spec@v1         →  x ai spec
x-cmd-action/ai/commit@v1       →  x ai commit
```

The design principle: **local-first.** If you can run `x ai triage` on your laptop, the same logic runs in CI — only the trigger changes (manual vs `issues: opened`).

The seven sub-commands together form an **IssueOps & DevProd** matrix:

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
└── .gitattributes           # tarball stripping
```

### Design choices

1. **One repo, seven sub-commands.** Each sub-command lives in its own subdirectory with its own `action.yml`. Users reference it via `x-cmd-action/ai/<subcmd>@v1` — no `task:` discriminator input that would break the 1:1 mapping with `x ai <subcmd>`.

2. **Flat structure — no `lib/`.** Each sub-command is self-contained: `action.yml` + exactly one shell script. The only common dependency (installing `x-cmd`) is extracted into a separate composite action: [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd).

3. **`x-cmd-action/x-cmd` is the single base dependency.** Every sub-command's first step is `- uses: x-cmd-action/x-cmd@v1`. It installs `x-cmd` into `~/.x-cmd.root/` and sources `X` so subsequent steps have access to `x ai`, `x gh`, `x minimax`, etc.

4. **`x-cmd-action/this-repo` provides git context for `gh`.** Because the `gh` CLI requires a working git repository context for many of its sub-commands, every sub-command's second step is `- uses: x-cmd-action/this-repo@v1` (a pure-shell clone of the current repository into `$GITHUB_WORKSPACE`).

5. **Pure shell, no Node.js.** All scripts are POSIX `bash`. No `npm install`, no dependency tree, fast cold-start. The tarball per sub-command is ~16 KB.

6. **AI token via env, not action input.** The token is read from `MINIMAX_TOKEN` env var (passed via `secrets.MINIMAX_TOKEN`). Local equivalent: `x minimax --cfg apikey=...`.

### Dependency graph

```
x-cmd-action/ai/<subcmd>@v1
  ├── uses → x-cmd-action/x-cmd@v1          # install x-cmd
  ├── uses → x-cmd-action/this-repo@v1       # clone current repo for gh context
  └── uses → secrets.MINIMAX_TOKEN (env)     # only sub-commands that call an LLM
```

## Sub-command details

### `ai/triage` — AI issue triage

Triggered on `issues: opened`. Reads the issue body + comments, asks the AI for `type` / `priority` / `area` / `labels` / `summary`, posts the result as a comment, and (if `apply-labels: true`) applies the suggested labels.

```yaml
- uses: x-cmd-action/ai/triage@v1
  with:
    model: minimax         # or openai:gpt-4, anthropic:claude-fable-5, ...
    apply-labels: 'true'   # or 'false' to comment only
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

| Input | Default | Description |
|---|---|---|
| `model` | `minimax` | AI model identifier (provider routing handled by `x ai request`) |
| `apply-labels` | `true` | Apply suggested labels automatically; set to `false` to comment only |

### `ai/reply` — react + reply on keyword

Triggered on `issue_comment: created` and `issues: opened`. When a configurable keyword (default `@x`) appears with **strict word-boundary** matching (so `@x-cmd` doesn't trigger), adds a reaction and posts a reply.

```yaml
- uses: x-cmd-action/ai/reply@v1
  with:
    keyword: '@x'
    reaction: eyes          # eyes | rocket | +1 | heart | laugh | hooray | ...
    comment: '👀 on it'
```

| Input | Default | Description |
|---|---|---|
| `keyword` | `@x` | Trigger keyword. Word-boundary matched (`@x` won't match `@x-cmd`) |
| `reaction` | `eyes` | Reaction name (see [GitHub API](https://docs.github.com/en/rest/reactions/reactions-about-issue-comment)) |
| `comment` | `👀 on it` | Reply comment body |

**Dedupe:** per-target reaction. If the triggering comment/issue already has the configured reaction, the action is a no-op. Prevents spam if the same comment is re-edited or the same issue is mentioned multiple times.

**Concurrency-safe:** the action does not manage concurrency itself — that's the caller's job (use `concurrency: cancel-in-progress: false` with `queue: single` default for single in-flight + single pending).

### `ai/review` — AI PR code review

Triggered on `pull_request: opened` / `synchronize`. Reads the PR diff via `gh pr diff`, asks the AI for security / style / suggestions / summary, posts a structured comment on the PR.

Diffs larger than 1500 lines are truncated (configurable via `max-diff-lines`) to keep prompts sane.

```yaml
- uses: actions/checkout@v4
  with: { fetch-depth: 0 }
- uses: x-cmd-action/ai/review@v1
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/changelog` — weekly changelog generator

Triggered on `schedule: cron` (recommended weekly: Mon 9am UTC). Collects issues closed in the last N days + PRs merged, asks the AI to group them into `Features / Fixes / Performance / Docs / Other`, writes the result.

`output: file` writes to `CHANGELOG.md` (configurable); `output: comment` writes to stdout (caller's responsibility).

```yaml
on:
  schedule:
    - cron: '0 9 * * 1'   # Mon 9am UTC
jobs:
  changelog:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: x-cmd-action/ai/changelog@v1
        with:
          days: 7
          output: file      # or 'comment'
        env:
          MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/translate` — AI i18n translation

Reads a Markdown file, asks the AI to translate to a target language, writes the result. Markdown-aware — code blocks are preserved (not translated), URLs and proper nouns are kept. Files larger than 3000 lines are truncated.

Useful for `README.md → README.cn.md` workflows.

```yaml
- uses: x-cmd-action/ai/translate@v1
  with:
    source: README.md
    target: zh           # ISO 639-1 code
    # output: README.zh.md   # optional, default: <stem>.<target>.<ext>
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/spec` — RFC templates & post-mortems

Two modes:

- `rfc` — auto-fill an RFC template from a feature request issue. The AI reads the issue + labels, produces a structured RFC document with Summary / Motivation / Detailed Design / Alternatives / Drawbacks / Open Questions sections.
- `postmortem` — extract a structured post-mortem from a closed bug issue. The AI reads the issue + comments (which usually contain debugging + fix discussion), produces Summary / Timeline / Root Cause / Detection / Resolution / Lessons Learned / Action Items.

```yaml
- uses: x-cmd-action/ai/spec@v1
  with:
    mode: rfc            # or 'postmortem'
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/commit` — Conventional Commits

Two modes:

- `check` — validate that commits in the current branch (vs `origin/main`) conform to [Conventional Commits](https://www.conventionalcommits.org/). Fails the workflow by default if any commits don't conform (`fail-on-invalid: false` to make it advisory).
- `generate` — write a commit message from the staged (or unstaged) diff using the AI.

Pairs naturally with `ai/changelog` — the cleaner the commit history, the better the auto-generated changelog.

```yaml
- uses: x-cmd-action/ai/commit@v1
  with:
    mode: check          # or 'generate'
    fail-on-invalid: 'true'   # check mode only
```

## Comparison: why sub-path actions instead of `task:` input?

| Approach | Pros | Cons |
|---|---|---|
| **One repo per sub-command** (e.g. `x-cmd-action/ai-triage`) | Familiar; one repo per release | 7 repos, 7 v1 tags, 7 CI configs; x-cmd installed 7 times |
| **One repo, sub-path actions** ✅ this | One v1 tag, one CI; users pick by `uses:` path; preserves `x ai <subcmd>` mapping | Slightly less obvious naming |
| **One repo, single action + `task` input** | Simplest repo layout | Users pass `with: task: triage`; breaks 1:1 with `x ai triage` |

We chose the sub-path approach because it preserves the **1:1 mapping** between local (`x ai triage`) and remote (`x-cmd-action/ai/triage@v1`), which is the core design promise.

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
review/action.yml + review/review.sh
changelog/action.yml + changelog/changelog.sh
translate/action.yml + translate/translate.sh
spec/action.yml + spec/spec.sh
commit/action.yml + commit/commit.sh
```

Each sub-command tarball is ~16 KB.

## Status

All seven sub-commands are **implemented** as of v1:

| Sub-command | Implementation |
|---|---|
| `triage` | Calls `x ai request` with structured prompt (type/priority/area/labels/summary), applies labels |
| `reply` | Strict word-boundary keyword match, per-target reaction dedupe (no AI token required) |
| `review` | Fetches PR diff via `gh pr diff`, asks AI for security/style/suggestions/summary, posts as PR comment |
| `changelog` | Collects closed issues + merged PRs in last N days, AI groups by feat/fix/perf/docs |
| `translate` | Reads file, AI i18n translation (Markdown-aware, preserves code blocks) |
| `spec` | RFC template fill-in (mode=rfc) or post-mortem extraction (mode=postmortem) from issue + comments |
| `commit` | Conventional Commits check (regex against commit log) or AI generate from staged diff |

All AI sub-commands require `MINIMAX_TOKEN` env (or equivalent `x <provider> --cfg apikey=...` config).

## License

Apache-2.0. See [`LICENSE`](LICENSE).

## Related

- [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd) — install x-cmd on a GitHub runner.
- [`x-cmd-action/this-repo`](https://github.com/x-cmd-action/this-repo) — pure-shell `actions/checkout` alternative.
- [`x-cmd-action/checkout`](https://github.com/x-cmd-action/checkout) — pure-shell `actions/checkout` alternative.
- [`x-cmd-action/.github`](https://github.com/x-cmd-action/.github) — org profile + roadmap.