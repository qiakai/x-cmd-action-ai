# x-cmd-action/ai

AI actions for GitHub Issues & PRs(工单与 PR 的 AI 自动化)。每个子命令与本地 `x ai <subcmd>` **一一对应**。

## 概览

`x-cmd-action/ai` 是一个**单仓多子命令**仓库,每个子命令都是一个独立的 composite GitHub Action。核心设计原则:

> **本地优先。** 用户在本地能跑 `x ai triage`,那同样的逻辑在 CI 里也能跑——只是触发方式不同(手动 vs `issues: opened`)。

七个子命令共同构成一套 **IssueOps & DevProd 工具集**:

| Action 引用 | 本地命令 | 核心职责 |
|---|---|---|
| `x-cmd-action/ai/triage@v1` | `x ai triage` | 新 Issue 自动归类:类型 + 优先级 + 标签 |
| `x-cmd-action/ai/reply@v1` | `x ai reply` | 提到 `@关键字` 时自动反应 + 回复 |
| `x-cmd-action/ai/review@v1` | `x ai review` | 对 PR diff 做 AI 代码审查(安全 + 规范 + 摘要) |
| `x-cmd-action/ai/changelog@v1` | `x ai changelog` | 周报:从已关闭 Issue 与已合并 PR 自动汇总 |
| `x-cmd-action/ai/translate@v1` | `x ai translate` | Markdown / 多语言文件的 AI 翻译 |
| `x-cmd-action/ai/spec@v1` | `x ai spec` | RFC 模板自动填写 + 故障复盘自动提取 |
| `x-cmd-action/ai/commit@v1` | `x ai commit` | Conventional Commits 规范校验 / 生成 |

## 架构

```
x-cmd-action/ai/
├── triage/                  # AI 工单分拣
│   ├── action.yml
│   └── triage.sh
├── reply/                   # @关键字反应+回复
│   ├── action.yml
│   └── reply.sh
├── review/                  # AI PR 审查
│   ├── action.yml
│   └── review.sh
├── changelog/               # 周报
│   ├── action.yml
│   └── changelog.sh
├── translate/               # AI 多语言翻译
│   ├── action.yml
│   └── translate.sh
├── spec/                    # RFC + 故障复盘
│   ├── action.yml
│   └── spec.sh
├── commit/                  # Conventional Commits
│   ├── action.yml
│   └── commit.sh
└── .gitattributes
```

### 设计取舍

1. **单仓七子命令**。每个子命令在自己的子目录里有独立的 `action.yml`,用户直接 `uses: x-cmd-action/ai/<subcmd>@v1`,不用 `task: triage` 这种 discriminator 输入。

2. **平铺结构 — 不放 `lib/`**。每个子命令自包含:`action.yml` + 一个 shell 脚本。**唯一共享的依赖**(安装 x-cmd)被抽到独立的 composite action [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd) 里。

3. **`x-cmd-action/x-cmd` 是唯一的基础依赖**。每个子命令的第一步都是 `- uses: x-cmd-action/x-cmd@v1`,把 x-cmd 装到 `~/.x-cmd.root/`,后续 step 就能用 `x ai`, `x gh`, `x minimax`。

4. **纯 shell,无 Node.js**。脚本都是 POSIX `bash`。不用 `npm install`,冷启动快。

5. **AI token 走环境变量**。读 `MINIMAX_TOKEN` env var(由 `secrets.MINIMAX_TOKEN` 传入)。本地等价:`x minimax --cfg apikey=...`。

### 依赖图

```
x-cmd-action/ai/<subcmd>   ──┐
x-cmd-action/<其他>          ──┤── uses ──> x-cmd-action/x-cmd
                              │
                              └── uses ──> actions/checkout  (可选,需要读仓库文件时才用)
```

## 快速上手

### 新 Issue 自动分拣

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

### 提到 `@x` 自动反应 + 回复

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

### AI PR 审查

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

### 周报(定时)

```yaml
# .github/workflows/weekly-changelog.yml
name: weekly-changelog
on:
  schedule:
    - cron: '0 9 * * 1'  # 周一 9 点(UTC)
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

## 为什么单仓?

| 方案 | 优点 | 缺点 |
|---|---|---|
| **一仓一子命令**(例如 `x-cmd-action/ai-triage`) | 熟悉,每仓独立 release | 7 个仓、7 个 v1 tag、7 份 CI;x-cmd 要装 7 次 |
| **单仓子路径 action** ✅ 选用 | 一个 v1 tag、一份 CI;按 `uses:` 路径选用 | 命名不那么直观 |
| **单仓单 action + `task` 输入** | 仓布局最简 | 用户得写 `with: task: triage`;破坏与 `x ai triage` 的 1:1 映射 |

我们选子路径,因为**保留了本地与远程的 1:1 映射**——这是核心设计承诺。

## 配置

所有子命令接受 `model`(默认 `minimax`)。Token: `MINIMAX_TOKEN` 环境变量。换 provider 直接设 model input 为 `openai:gpt-4`、`anthropic:claude-fable-5` 等(由 `x ai request` 内部路由)。

## Tarball 体积优化

`.gitattributes` 排除:

```
.gitattributes    export-ignore
.github           export-ignore
*.md              export-ignore
```

`git archive`(被 `uses: x-cmd-action/ai/<subcmd>@v1` 使用)只打包:

```
triage/action.yml + triage/triage.sh
reply/action.yml + reply/reply.sh
...
```

每个子命令 ~16 KB。

## 协议

Apache-2.0. 见 [LICENSE](https://github.com/x-cmd-action/ai/blob/main/LICENSE)。