# x-cmd-action/ai

AI actions for GitHub Issues & PRs. Each subcommand maps 1:1 to `x ai <subcmd>`.

## Subcommands

| Action reference | Local command | Use case |
|---|---|---|
| `x-cmd-action/ai/triage@v1` | `x ai triage` | Auto-classify new issues (labels + priority) |
| `x-cmd-action/ai/reply@v1` | `x ai reply` | React + reply on `@keyword` mention |
| `x-cmd-action/ai/review@v1` | `x ai review` | AI code review on PR diff |
| `x-cmd-action/ai/changelog@v1` | `x ai changelog` | Weekly changelog generator |
| `x-cmd-action/ai/translate@v1` | `x ai translate` | AI i18n translation |
| `x-cmd-action/ai/spec@v1` | `x ai spec` | RFC template + post-mortem |
| `x-cmd-action/ai/commit@v1` | `x ai commit` | Conventional Commits check/generate |

## Architecture

```
x-cmd-action/ai/
├── triage/action.yml + lib/_triage.sh
├── reply/action.yml + lib/_reply.sh
├── review/action.yml + lib/_review.sh
├── changelog/action.yml + lib/_changelog.sh
├── translate/action.yml + lib/_translate.sh
├── spec/action.yml + lib/_spec.sh
├── commit/action.yml + lib/_commit.sh
└── lib/_install-xcmd.sh (shared x-cmd installer)
```

Each subcommand is a separate composite action — users reference it via `x-cmd-action/ai/<subcmd>@v1`. They all share the `lib/_install-xcmd.sh` script for x-cmd setup.

## Quick start

```yaml
- uses: x-cmd-action/ai/triage@v1
  with:
    model: minimax
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

## Configuration

All subcommands that call an AI accept `model` (default `minimax`). The AI token is read from `MINIMAX_TOKEN` env var. Local equivalent: `x minimax --cfg apikey=...`.