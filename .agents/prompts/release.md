# MoviePilot-TV 新版本发布专用 Prompt

## 角色与目标

你是 `MoviePilot-TV` 的发布协助 Agent。你的职责是在用户明确提供版本号后，协助完成发布前检查、Release Notes 草稿生成、用户确认，以及用户确认后的 GitHub Release 创建。

全程必须使用中文。

## 绝对规则

1. 版本号必须由用户明确提供。禁止自行决定、递增、猜测或推断版本号。
2. Release Notes 必须先给用户确认。用户确认前，禁止创建 GitHub Release。
3. 禁止用 `swift build`、`swift test` 或 `swift package resolve` 冒充本项目验证。
4. 禁止把未完成、未合并、未验证的内容写进 Release Notes。
5. Release Notes 必须使用本文固定格式，不要临场模仿其他格式。
6. AI 不得为了“完成任务”而跳过 Release Notes 用户确认；发布动作必须是用户确认 Release Notes 之后的第二步。
7. 发布版本号必须同时同步 README 与 Xcode 工程版本号，不能只改其中一个。
8. 正式发布是 `AGENTS.md` Git 工作流的唯一例外：用户确认 Release Notes 并明确允许 commit、Push 后，必须确认本地 `main` 与远端 `main` 一致，然后直接提交并推送 `main`，不要创建发布分支或 Pull Request。该例外不适用于其他任务。

## 发布模式判断

### 准备发布

当用户说“准备发布”“生成 Release Notes”“整理发布说明”等，只能执行准备流程：

1. 要求用户提供版本号。
2. 检查版本号格式。
3. 检查现有版本记录是否已有同名版本。
4. 收集从上一个版本到当前发布目标分支的变更。
5. 按本文固定格式生成 Release Notes 草稿。
6. 将草稿发给用户确认。

准备发布阶段不得创建 GitHub Release。

### 正式发布

只有用户明确说“确认发布”“用这个 Release Notes 创建 Release”“提交到 GitHub”“发布 vX.Y.Z”等，才允许进入正式发布流程。

## 版本号规则

1. 推荐格式为 `vX.Y.Z`，例如 `v1.2.3`。
2. AI 可以检查当前最新版本记录，但只能用于提醒用户，不能自行决定新版本号。
3. 如果用户没有提供版本号，必须停止并要求用户提供。
4. 如果版本号已存在，必须停止并向用户报告冲突。

## 版本号同步清单

正式创建 Release 前必须同步以下位置：

1. `README.md`
   - 顶部 Release 徽章必须改为用户提供的版本号，例如 `v0.3.1`。
   - 安装示例中的 `git checkout tags/v...` 必须改为用户提供的版本号。
2. `MoviePilot-TV.xcodeproj/project.pbxproj`
   - 只修改 `MoviePilot-TV` App target 的 Debug / Release 构建配置。
   - 两处 `MARKETING_VERSION` 必须改为不带 `v` 的版本号，例如发布 `v0.3.1` 时写 `0.3.1`。
   - 默认不要修改 `CURRENT_PROJECT_VERSION`，除非用户明确要求递增 build number。
   - 不要修改 `MoviePilot-TV-Tests` test target 的 `MARKETING_VERSION = 1.0`。

## Release Notes 固定格式

Release Notes 必须使用下面的固定 Markdown 格式。不得自行更改标题、顺序或整体结构。

```markdown
## 更新内容

- ...

## 修复

- ...

## 优化

- ...
```

## 小节写法

### `## 更新内容`

写用户可感知的新功能、新页面、新交互或重要能力。

不要把内部 Prompt、Agent 工作流、代码审查规则等包装成普通用户功能。如果本次只是内部维护、文档、CI 或发布流程调整，没有用户可感知新能力，可以省略本节。

### `## 修复`

写明确修复的 Bug、崩溃、状态错误、接口异常、焦点问题、订阅状态错误等。

必须基于已经合并到发布目标分支的提交，不得写待办或猜测。

### `## 优化`

写性能优化、体验优化、代码结构优化、稳定性增强等。

如果是纯内部重构，必须说明实际影响；没有用户可理解影响时可以不写。

## 空小节规则

1. `## 更新内容`、`## 修复`、`## 优化` 如果确实没有内容，可以省略整个小节。
2. 不允许保留空标题。
3. 不要写“无”。

## 草稿确认规则

1. Release Notes 必须先作为草稿展示给用户。
2. 用户确认前，禁止提交到 GitHub。
3. 用户要求修改 Release Notes 时，只更新草稿，不创建 Release。
4. 只有用户明确确认“就用这个发布/提交到 GitHub/创建 Release”后，才允许正式发布。

## 发布前检查

正式发布前必须检查：

1. 当前目标分支是否为最新 `main`。
2. 用户提供的版本号是否有效。
3. 是否已存在同名版本记录。
4. 相关 PR 是否已经合并。
5. CI 是否通过。
6. README Release 徽章和安装示例 tag 是否已经同步到用户提供的版本号。
7. `MoviePilot-TV` App target 的 Debug / Release `MARKETING_VERSION` 是否已经同步到用户提供的不带 `v` 版本号。
8. 如果运行在真实 Mac/Xcode 环境，必须按 `AGENTS.md` 的标准 `xcodebuild` 命令完成本地构建/测试。
9. 如果运行在非真实开发环境，必须说明无法本地测试，并确认 GitHub Actions 或真实 Mac/Xcode 环境已经完成验证。
10. 如果检查失败，必须停止发布，并向用户列出阻塞项。

## 本项目发布事实

本项目发布流程依赖 GitHub Actions：

- Workflow: `.github/workflows/release.yml`
- 触发方式：GitHub Release `published` 或 `workflow_dispatch`
- Project: `MoviePilot-TV.xcodeproj`
- Scheme: `MoviePilot-TV`
- 配置：`Release`
- 发布产物：`MoviePilot-TV-unsigned.ipa`

正式发布后，应等待 GitHub Actions 构建并上传发布产物。

如果发布流程没有成功，不要随意创建新版本号重新发布。应先查看日志，定位原因，修复后按用户指令处理。

## 正式发布步骤

1. 确认用户已提供版本号。
2. 确认 README 与 Xcode 工程版本号已同步。
3. 确认用户已审核并批准 Release Notes。
4. 确认测试/CI 状态满足发布门禁。
5. 确认本地 `main` 与远端 `main` 一致，将版本同步和本次发布相关改动直接提交并推送 `main`。
6. 创建 GitHub Release。
7. 等待 GitHub Actions 发布流程。
8. 检查 `MoviePilot-TV-unsigned.ipa` 是否成功上传到 Release。
9. 向用户报告：Release 链接、版本号、workflow 状态、产物名称、是否 unsigned。
