# AGENTS.md

本文件是 `MoviePilot-TV` 仓库的统一 AI 工作入口。它只负责说明通用约束、任务路由、运行验证和 Git 工作流；具体任务规则放在 `.agents/prompts/` 下的专项 Prompt 中。

## 项目背景

`MoviePilot-TV` 是基于 MoviePilot 前端（Web/Vue）架构向 Apple TV / tvOS 平台迁移的原生客户端项目，主要技术栈为 Swift、SwiftUI、tvOS Focus Engine 与 Apple 平台网络/状态管理体系。

与本项目相关的上游仓库默认位于同级目录：

```text
../MoviePilot-Frontend
../MoviePilot
```

如果任务涉及上游 Web 前端、后端接口或 TV 端逻辑对齐，必须优先确认相关目录存在且是合法 Git 仓库。

## 通用执行约束

1. 全程使用中文与用户沟通。
2. 不要无脑同时读取所有专项 Prompt；只读取当前任务需要的文件。
3. 专项 Prompt 是具体任务规则的单一事实来源，`AGENTS.md` 不重复解释专项 Prompt 内容。
4. 如果任务同时命中多个场景，先读取最核心的专项 Prompt，再按需补充读取其他文件。
5. 如果用户明确要求“只分析”“先检查”“不要修改”，只能审查、解释、提出建议，不要改代码、不要提交、不要开 PR。
6. 如果需要修改代码、配置、文档或工作流，必须遵守本文件的 Git 工作流。
7. 兼容任务的目标是与 MoviePilot 后端和 MoviePilot Web 前端当前行为对齐；真实后端测试出问题时，必须先判断 MP Web / 官方后端是否同样异常。若上游同样异常或 Web 本来也不发起对应请求，不要在 TV 端替 MoviePilot 官方兜底、修 Bug 或新增差异化容错，只记录为上游对齐问题。

## 任务路由

本节只决定“当前任务需要读取哪些文件”。不要为了保险一次性读取所有 Prompt。

| 用户意图 | 读取文件 |
| --- | --- |
| 最终联合审查、AI + 人工收尾审查、按 ReviewPlan 继续、继续审查下一个文件 | `.agents/prompts/final-review.md` + `.agents/ReviewPlan.md` |
| 普通 PR Review、检查最近提交、检查分支、临时检查某个文件 | 不读取专项 Prompt；直接查看对应 diff / 提交 / 源码 |
| 检查 `MoviePilot-Frontend` / `MoviePilot` 上游更新对 TV 端影响 | `.agents/prompts/frontend-update.md` + `.agents/ReviewPlan.md` |
| 准备发布、生成 Release Notes、创建 GitHub Release | `.agents/prompts/release.md` |
| 整理 Prompt、文档、工作流 | 读取被修改的相关文件；如新增专项 Prompt，同步更新本路由表 |

## 路由边界

1. `.agents/prompts/final-review.md` 只用于明确的最终联合审查；普通 PR Review、最近提交检查、分支检查不要读取它。
2. 如果用户意图不明确，先按普通只读调查处理；确认任务类型后再读取对应专项 Prompt。
3. 上游兼容更新分析必须确认 `../MoviePilot-Frontend` 和 `../MoviePilot` 存在且是合法 Git 仓库；如果用户只是临时排查某个运行 Bug，可以说明缺失仓库会降低判断完整性后继续分析。
4. 发布类任务必须读取 `.agents/prompts/release.md`；版本号必须由用户提供，Release Notes 必须先给用户确认。

## 运行环境与测试策略

AI 可能在不同执行环境中维护本仓库。开始修改前应先判断当前环境属于哪一类，并按对应规则执行。

### 0. 本项目标准验证命令

本项目是 Xcode tvOS App 工程，不是 Swift Package。**不要用 `swift build`、`swift test` 或 `swift package resolve` 当作有效验证**；这些命令无法代表 tvOS App 的真实构建结果，甚至可能完全没有覆盖 `MoviePilot-TV.xcodeproj`。

标准工程信息：

```text
Project: MoviePilot-TV.xcodeproj
Scheme: MoviePilot-TV
Platform: tvOS
```

真实 Mac/Xcode 环境中，本机优先使用 tvOS Simulator 做构建和测试，这更接近在 Xcode 里选择 Apple TV 模拟器后点击 Build/Test 的行为。

先检查工程、Xcode 与可用模拟器：

```bash
xcodebuild -version
xcodebuild -showsdks
xcodebuild -list -project "MoviePilot-TV.xcodeproj"
xcrun simctl list devices tvOS available
```

解析依赖：

```bash
xcodebuild -resolvePackageDependencies \
  -project "MoviePilot-TV.xcodeproj" \
  -scheme "MoviePilot-TV" \
  -skipPackagePluginValidation
```

本机完整构建（优先使用 tvOS Simulator，不要默认改成 `generic/platform=tvOS`）：

```bash
xcodebuild clean build \
  -project "MoviePilot-TV.xcodeproj" \
  -scheme "MoviePilot-TV" \
  -configuration Debug \
  -destination "platform=tvOS Simulator,name=Apple TV" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -skipPackagePluginValidation
```

本机测试：

```bash
xcodebuild test \
  -project "MoviePilot-TV.xcodeproj" \
  -scheme "MoviePilot-TV" \
  -configuration Debug \
  -destination "platform=tvOS Simulator,name=Apple TV" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -skipPackagePluginValidation
```

本机测试默认串行运行。不要移除 `-parallel-testing-enabled NO` 和 `-maximum-concurrent-test-simulator-destinations 1`，否则 XCTest 可能启动多个 `Clone N of Apple TV` 模拟器并并行执行不同测试套件。真实后端兼容测试尤其应串行执行，方便控制副作用套件的执行顺序和排查失败来源。

真实后端兼容测试在 `Testing started` 后可能数分钟没有增量输出，尤其是图片巡检会实际扫描 TV 页面入口、下载图片并用 tvOS 解码。不要因为短时间无输出就判断 `xcodebuild test` 卡死；至少等待单个用例的合理超时窗口，或读取 `.xcresult` 中的测试摘要和失败详情后再下结论。

真实后端兼容测试可能包含副作用。新增或修改任何会访问真实 MoviePilot 后端的测试前，必须先明确它是否会改变真实数据或触发后台动作，包括但不限于订阅搜索、订阅 reset、暂停/恢复订阅、保存订阅、手动/AI 重新整理、添加/删除下载或订阅。默认优先写只读测试；确实需要副作用测试时，必须放在 `BackendCompatibilitySideEffectTests` 或等价的显式副作用套件中，提供独立开关，限制目标范围，记录目标对象原始状态，并在成功、失败和取消路径中尽力恢复原状态。不要在用户个人后端上用“全量测试”名义新增隐式副作用。

如果本机没有名为 `Apple TV` 的 tvOS Simulator，先用下面命令列出可用模拟器，并选择一个可用 tvOS 目标替换 `-destination`，同时在回复或提交说明中写清楚实际使用的目标：

```bash
xcrun simctl list devices tvOS available
```

`generic/platform=tvOS` 属于 CI/设备归档风格的编译检查，可能触发本机 SDK、runtime 或设备支持校验；它可以作为 GitHub Actions 或额外设备构建检查使用，但不要用它替代本机 Simulator 构建/测试。

如果仓库后续新增了脚本或 GitHub Actions 修改了标准命令，应优先同步本节，保持本地验证命令与 CI/真实可运行命令一致。

### 1. 真实开发环境（Mac + Xcode）

满足以下条件时，视为真实开发环境：

- 运行在 macOS。
- 已安装 Xcode / Command Line Tools。
- 能执行 `xcodebuild`。
- 能访问本仓库完整工作区与必要的 Apple 平台 SDK。

在真实开发环境中：

1. 只要修改了代码、配置、文档或工作流，提交前都必须运行完整验证流程。
2. 对 Swift / tvOS 代码修改，提交前必须至少运行上方【本项目标准验证命令】中的依赖解析、Simulator 完整构建和测试。
3. 对文档或 Prompt 修改，也应运行仓库可用的轻量检查；如果没有适用检查，必须说明“文档-only 变更，无可运行测试”。
4. 测试失败时禁止提交，除非用户明确要求保留失败状态用于审查，并且提交说明中必须写清楚失败命令与失败原因。
5. Commit 前必须在最终回复或提交说明中列出实际运行过的命令和结果。
6. 只运行 `swift build`、只运行 `swift test`、只运行依赖解析、只打开 Xcode 不构建，都不能视为通过验证。

### 2. 非真实开发环境（无 Xcode、只读代码平台、GitHub API、网页编辑器、Linux 容器等）

满足以下任一情况时，视为非真实开发环境：

- 不在 macOS 上运行。
- 没有 Xcode / Apple 平台 SDK。
- 不能执行 `xcodebuild`。
- 只能通过 GitHub API、网页编辑器或受限容器修改文件。

在非真实开发环境中：

1. 可以进行代码、文档、Prompt 或工作流修改，但必须明确说明当前环境无法运行本地 Xcode 构建/测试。
2. 不要求在每次提交前本地跑完整测试，因为环境本身不具备真实 tvOS 构建能力。
3. 合并前必须通过 GitHub Actions、真实 Mac/Xcode 环境或用户指定的测试流程完成验证。
4. PR 描述或最终回复中必须写清楚“未本地运行测试”的原因，以及合并前需要补跑的测试。
5. 不要把“无法运行测试”伪装成“测试通过”。
6. 不要在非真实环境中用 `swift build` 冒充本项目验证；这比不跑测试更误导。

### 3. 合并前要求

无论修改来自哪种环境，合并前都必须满足：

1. 相关构建/测试流程已经通过，或用户明确接受未通过/未运行的风险。
2. 如果是非真实开发环境提交的变更，必须在 GitHub 或真实 Mac/Xcode 环境补跑测试。
3. 除非用户明确要求合并，并且相关构建/测试已经通过，否则不要直接合并 PR。

## Git 工作流

对本仓库进行任何代码、配置、文档或工作流修改时，必须遵守：

1. 禁止在未获得用户明确允许的情况下执行 `git commit`、`git push` 或创建 Pull Request；其中私自创建 PR 属于严重违规。用户要求“写好”“整理好”“提交到 GitHub”不足以自动推导为允许 commit/push/开 PR，必须先单独确认。
2. 禁止直接向 `main` 分支提交任何修改。
3. 每次开始修改前，必须基于最新 `main` 创建独立分支。
4. AI 创建的分支名必须使用 `ai/xxx` 格式，例如：
   - `ai/add-github-actions-ci`
   - `ai/fix-paginator-loading-state`
   - `ai/refactor-media-preloader`
   - `ai/update-readme`
5. Commit Message 必须使用以下格式：

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

6. 用户明确允许创建 PR 时，修改完成后再创建 Pull Request 让用户审查。
7. 除非用户明确要求合并，并且相关构建/测试已经通过，否则不要直接合并 PR。

## 文档维护规则

1. `.agents/prompts/` 下的专项 Prompt 是具体任务的单一事实来源。
2. `.agents/ReviewPlan.md` 是收尾联合审查的进度与跨文件副作用记录。
3. `AGENTS.md` 只维护入口、路由、通用项目约束和 Git 工作流。
4. 如果新增专项 Prompt，应同步更新本文件的任务路由表。
5. 如果修改专项 Prompt 的行为规则，应优先修改 `.agents/prompts/` 对应文件，再检查本文件是否需要更新路由描述。
