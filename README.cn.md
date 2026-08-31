# x-cmd-action/ai

> 面向 GitHub Issues 与 PR 的 AI 工具集 — 七个子命令,每个与本地 `x ai <subcmd>` 一一对应。纯 shell,无 Node.js,由 GitHub 事件触发。

[English](./README.md)

## 这是什么

一个**单仓多子命令**仓库,每个子命令是一个独立的 composite GitHub Action,通过路径引用:

```
x-cmd-action/ai/triage@v1       →  x ai triage
x-cmd-action/ai/reply@v1        →  x ai reply
x-cmd-action/ai/review@v1       →  x ai review
x-cmd-action/ai/changelog@v1    →  x ai changelog
x-cmd-action/ai/translate@v1    →  x ai translate
x-cmd-action/ai/spec@v1         →  x ai spec
x-cmd-action/ai/commit@v1       →  x ai commit
```

设计原则:**本地优先**。你在本地能跑 `x ai triage`,那同样的逻辑在 CI 里也能跑——只是触发方式不同(手动 vs `issues: opened`)。

七个子命令共同构成一套 **IssueOps & DevProd** 工具集:

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
└── .gitattributes           # tarball 体积优化
```

### 设计取舍

1. **单仓七子命令**。每个子命令在自己的子目录里有独立的 `action.yml`,用户直接 `uses: x-cmd-action/ai/<subcmd>@v1`,不需要 `task: triage` 这种 discriminator 输入,保持与 `x ai <subcmd>` 的 1:1 映射。

2. **平铺结构 — 不放 `lib/`**。每个子命令自包含:`action.yml` + 一个 shell 脚本。**唯一共享的依赖**(安装 x-cmd)被抽到独立的 composite action [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd) 里。

3. **`x-cmd-action/x-cmd` 是唯一的基础依赖**。每个子命令的第一步都是 `- uses: x-cmd-action/x-cmd@v1`,把 x-cmd 装到 `~/.x-cmd.root/`,后续 step 就能用 `x ai`, `x gh`, `x minimax`。

4. **`x-cmd-action/this-repo` 提供 `gh` 所需的 git context**。`gh` CLI 的很多子命令需要工作在一个 git 仓库里,所以每个子命令的第二步是 `- uses: x-cmd-action/this-repo@v1`(用纯 shell 把当前仓库 clone 到 `$GITHUB_WORKSPACE`)。

5. **纯 shell,无 Node.js**。脚本都是 POSIX `bash`。不用 `npm install`,冷启动快。每个子命令的 tarball 仅约 16 KB。

6. **AI token 走环境变量**。读 `MINIMAX_TOKEN` env var(由 `secrets.MINIMAX_TOKEN` 传入)。本地等价:`x minimax --cfg apikey=...`。

### 依赖图

```
x-cmd-action/ai/<subcmd>@v1
  ├── uses → x-cmd-action/x-cmd@v1          # 安装 x-cmd
  ├── uses → x-cmd-action/this-repo@v1       # clone 当前仓库,给 gh 用
  └── uses → secrets.MINIMAX_TOKEN (env)     # 仅调用 LLM 的子命令需要
```

## 子命令详解

### `ai/triage` — AI Issue 分拣

`issues: opened` 触发。读 Issue 正文 + 评论,问 AI 要 `type` / `priority` / `area` / `labels` / `summary`,作为 comment 发出来,如果 `apply-labels: true` 就同时贴标签。

```yaml
- uses: x-cmd-action/ai/triage@v1
  with:
    model: minimax         # 或 openai:gpt-4, anthropic:claude-fable-5, ...
    apply-labels: 'true'   # 'false' 只评论不贴标签
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

| Input | 默认 | 说明 |
|---|---|---|
| `model` | `minimax` | AI 模型标识(provider 路由由 `x ai request` 处理) |
| `apply-labels` | `true` | 自动贴建议的标签;`false` 只发评论 |

### `ai/reply` — @关键字反应 + 回复

`issue_comment: created` 与 `issues: opened` 触发。当**严格词边界匹配**到关键字(默认 `@x`,所以 `@x-cmd` 不会误触)时,加 reaction 并发回复。

```yaml
- uses: x-cmd-action/ai/reply@v1
  with:
    keyword: '@x'
    reaction: eyes          # eyes | rocket | +1 | heart | laugh | hooray | ...
    comment: '👀 on it'
```

| Input | 默认 | 说明 |
|---|---|---|
| `keyword` | `@x` | 触发关键字。词边界匹配(`@x` 不会匹配 `@x-cmd`) |
| `reaction` | `eyes` | reaction 名(见 [GitHub API](https://docs.github.com/en/rest/reactions/reactions-about-issue-comment)) |
| `comment` | `👀 on it` | 回复正文 |

**去重**:per-target reaction。如果目标 comment/issue 已经有这个 reaction,直接 no-op。同一个 comment 被反复编辑也不会 spam。

**并发安全**:action 自己不管并发,需要调用方配 `concurrency: cancel-in-progress: false`(默认 `queue: single`,单 in-flight + 单 pending)。

### `ai/review` — AI PR 代码审查 *(占位)*

`pull_request: opened` / `synchronize` 触发。读 PR diff,跑安全 + 规范审查,发结构化评论。**暂未实现** — 当前只校验输入、报 `TODO: implement`。等 `x ai review` 在命令行稳定,这里就调过去。

```yaml
- uses: actions/checkout@v4
  with: { fetch-depth: 0 }
- uses: x-cmd-action/ai/review@v1
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/changelog` — 周报生成器 *(占位)*

`schedule: cron` 触发。收集过去 N 天关闭的 Issue + 合并的 PR,问 AI 按 `feat / fix / perf / docs` 分组,输出 changelog。

```yaml
on:
  schedule:
    - cron: '0 9 * * 1'   # 周一 9 点(UTC)
jobs:
  changelog:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: x-cmd-action/ai/changelog@v1
        with:
          days: 7
        env:
          MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/translate` — AI 多语言翻译 *(占位)*

读一个 Markdown 文件,问 AI 翻译到目标语言,写出去。常用于 `README.md → README.cn.md`。

```yaml
- uses: x-cmd-action/ai/translate@v1
  with:
    source: README.md
    target: zh
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/spec` — RFC 模板 + 故障复盘 *(占位)*

两种模式:`rfc`(从 feature request issue 自动填 RFC 模板)和 `postmortem`(从已关闭 bug issue 提取结构化复盘)。

```yaml
- uses: x-cmd-action/ai/spec@v1
  with:
    mode: rfc   # 或 'postmortem'
  env:
    MINIMAX_TOKEN: ${{ secrets.MINIMAX_TOKEN }}
```

### `ai/commit` — Conventional Commits *(占位)*

两种模式:`check`(校验当前分支 commit message 是否符合规范)与 `generate`(从 staged diff 写 commit message)。跟 `ai/changelog` 是天生搭档 — commit 历史越干净,自动 changelog 越好。

```yaml
- uses: x-cmd-action/ai/commit@v1
  with:
    mode: check   # 或 'generate'
```

## 选型对比:为什么用子路径 action 而不是 `task:` 输入?

| 方案 | 优点 | 缺点 |
|---|---|---|
| **一仓一子命令**(例如 `x-cmd-action/ai-triage`) | 熟悉,每仓独立 release | 7 个仓、7 个 v1 tag、7 份 CI;x-cmd 要装 7 次 |
| **单仓子路径 action** ✅ 选用 | 一个 v1 tag、一份 CI;按 `uses:` 路径选用;保持 `x ai <subcmd>` 映射 | 命名没那么直观 |
| **单仓单 action + `task` 输入** | 仓布局最简 | 用户得写 `with: task: triage`;破坏与 `x ai triage` 的 1:1 映射 |

我们选子路径,因为**保留了本地与远程的 1:1 映射**——这是核心设计承诺。

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
review/action.yml + review/review.sh
changelog/action.yml + changelog/changelog.sh
translate/action.yml + translate/translate.sh
spec/action.yml + spec/spec.sh
commit/action.yml + commit/commit.sh
```

每个子命令 tarball ~16 KB。

## 实现进度

- ✅ `triage` — 已实现(调用 `x ai request` 跑结构化 prompt)
- ✅ `reply` — 已实现(不需要 AI token;确定性 reaction + reply)
- ⏳ `review`、`changelog`、`translate`、`spec`、`commit` — 占位(只校验输入、报 `TODO: implement`)

每个占位都会在对应 `x ai <subcmd>` 命令行稳定后变成真实现。

## 协议

Apache-2.0. 见 [`LICENSE`](LICENSE)。

## 相关

- [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd) — 在 GitHub runner 上装 x-cmd。
- [`x-cmd-action/this-repo`](https://github.com/x-cmd-action/this-repo) — `actions/checkout` 的纯 shell 替代。
- [`x-cmd-action/checkout`](https://github.com/x-cmd-action/checkout) — `actions/checkout` 的纯 shell 替代。
- [`x-cmd-action/.github`](https://github.com/x-cmd-action/.github) — 组织主页 + 路线图。