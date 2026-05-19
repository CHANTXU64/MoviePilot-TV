# AGENTS.md

本文件是 `MoviePilot-TV` 仓库的统一 AI 工作入口。它不替代 `.agents/prompts/` 下的专项 Prompt，而是负责先判断任务类型，再路由到对应 Prompt，避免每次都把所有规则一次性塞进上下文。

## 项目背景

`MoviePilot-TV` 是基于 MoviePilot 前端（Web/Vue）架构向 Apple TV / tvOS 平台迁移的原生客户端项目，主要技术栈为 Swift、SwiftUI、tvOS Focus Engine 与 Apple 平台网络/状态管理体系。

与本项目相关的上游前端仓库默认位于同级目录：

```text
../MoviePilot-Frontend
```

如果任务涉及 Web 前端与 TV 端逻辑对齐，必须优先确认该目录存在且是合法 Git 仓库。

## 总体使用原则

1. 全程使用中文与用户沟通。
2. 先判断任务类型，再读取对应 `.agents/prompts/` Prompt。
3. 不要无脑同时读取所有专项 Prompt；只有任务需要时才加载对应文件。
4. 专项 Prompt 中的规则优先级高于本文件的泛化说明。
5. 如果任务同时命中多个类型，先读取最核心的专项 Prompt，再按需补充读取其他 Prompt。
6. 如果用户明确要求“只分析”“先检查”“不要修改”，只能审查、解释、提出建议，不要改代码、不要提交、不要开 PR。
7. 如果需要修改代码、配置、文档或工作流，必须遵守本文件的 Git 工作流。

## Prompt 目录

专项 Prompt 统一放在：

```text
.agents/prompts/
```

当前包含：

- `.agents/prompts/code-review.md`：深度代码审查 Prompt。
- `.agents/prompts/frontend-update.md`：上游前端更新影响分析 Prompt。

## 任务路由表

| 用户任务特征 | 必读 Prompt | 处理方式 |
| --- | --- | --- |
| 审查某个 Swift / SwiftUI / tvOS 文件、组件或最近提交；要求“认真检查”“深度审查”“有没有问题” | `.agents/prompts/code-review.md` | 进入深度代码审查模式。先读 `ReviewPlan.md`，必要时对齐 `../MoviePilot-Frontend`，首次报告只列问题不直接改。 |
| 分析 MoviePilot-Frontend 上游版本更新、检查前端最新变更对 TV 端影响、做版本兼容评估 | `.agents/prompts/frontend-update.md` | 进入前端更新影响分析模式。先确认 `../MoviePilot-Frontend`，再对比当前兼容版本与最新前端版本，输出结构化影响报告和行动计划。 |
| 用户要求实现、修复、重构 tvOS 功能，但没有明确说只分析 | 先按任务性质读取 `.agents/prompts/code-review.md`，如涉及上游前端逻辑再补充 `.agents/prompts/frontend-update.md` | 先理解现有代码与跨端逻辑，再修改。修改前必须基于最新 `main` 创建 `ai/...` 分支。 |
| 用户要求整理、更新项目文档、Prompt、工作流说明 | 本文件 + 相关专项 Prompt | 只整理入口或文档时，不要改变专项 Prompt 原意；应尽量通过引用/路由保留单一事实来源。 |
| 用户任务无法归类 | 先读本文件，不急着读专项 Prompt | 简要说明不确定点，优先做只读调查；一旦判断任务类型，再加载对应专项 Prompt。 |

## 路由细则

### 1. 代码审查类任务

命中示例：

- “检查这个文件”
- “认真看最近一次提交”
- “这个分支有没有问题”
- “深度审查某个 ViewModel / Service / SwiftUI View”

执行规则：

1. 必须读取 `.agents/prompts/code-review.md`。
2. 必须优先读取 `ReviewPlan.md`，同步历史审查进度和跨文件副作用。
3. 如果审查对象依赖 `ReviewPlan.md` 中记录过副作用的组件，必须打开对应源码核对，不能只凭备注判断。
4. 对核心业务逻辑、网络请求、模型解析等内容，必须按专项 Prompt 要求检索 `../MoviePilot-Frontend` 的对应实现。
5. 初次报告只列问题、风险和位置，不要直接给修改代码，除非用户明确要求修复。

### 2. 前端上游更新影响分析任务

命中示例：

- “看看前端最新版本 TV 端要不要跟”
- “MoviePilot-Frontend 更新了什么，TV 端有没有影响”
- “检查 README 里的兼容版本是不是要更新”

执行规则：

1. 必须读取 `.agents/prompts/frontend-update.md`。
2. 必须确认 `../MoviePilot-Frontend` 存在且是合法 Git 仓库；不存在时停止并提示用户补齐。
3. 必须读取当前项目 `README.md` 中的兼容版本说明。
4. 必须结合 `ReviewPlan.md` 理解 TV 端当前架构状态。
5. 输出应包含版本跨度、API/模型影响、TV 端适配建议、行动计划和文档更新建议。

### 3. 实现与修复类任务

当用户要求实际改代码时：

1. 先根据任务类型读取对应专项 Prompt。
2. 先做最小必要调查，明确变更范围。
3. 优先保持实现简单，避免把小功能过度工程化。
4. 涉及后端或官方前端尚不存在的能力时，不要擅自扩展成复杂跨端架构；应尊重当前 TV 端的小范围功能定位。
5. 修改完成后运行可用的构建、测试或静态检查；若无法运行，必须说明原因。

## Git 工作流

对本仓库进行任何代码、配置、文档或工作流修改时，必须遵守：

1. 禁止直接向 `main` 分支提交任何修改。
2. 每次开始修改前，必须基于最新 `main` 创建独立分支。
3. AI 创建的分支名必须使用 `ai/xxx` 格式，例如：
   - `ai/add-github-actions-ci`
   - `ai/fix-paginator-loading-state`
   - `ai/refactor-media-preloader`
   - `ai/update-readme`
4. Commit Message 必须使用以下格式：

```text
[AI] <type>/<scope>: <summary>
```

其中：

- `<type>` 使用 `feat`、`fix`、`chore`、`refactor`、`test`、`docs` 等常见类型。
- `<scope>` 简短描述修改范围，例如 `ci`、`paginator`、`preloader`、`tests`、`readme`。
- `<summary>` 简洁说明本次修改内容，中文或英文均可。

示例：

```text
[AI] feat/ci: add GitHub Actions build and test workflow
[AI] fix/paginator: prevent stale load result from updating items
[AI] chore/tests: add paginator lifecycle test coverage
[AI] refactor/preloader: start detail tasks before image prefetch timeout
[AI] docs/readme: update installation instructions
```

5. 修改完成后，优先创建 Pull Request 让用户审查。
6. 除非用户明确要求合并，并且相关构建/测试已经通过，否则不要直接合并 PR。

## 文档维护规则

1. `.agents/prompts/` 下的专项 Prompt 是具体任务的单一事实来源。
2. `AGENTS.md` 只维护入口、路由、通用项目约束和 Git 工作流。
3. 如果新增专项 Prompt，应同步更新本文件的任务路由表。
4. 如果修改专项 Prompt 的行为规则，应优先修改 `.agents/prompts/` 对应文件，再检查本文件是否需要更新路由描述。
