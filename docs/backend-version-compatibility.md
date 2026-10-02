# MoviePilot 后端版本兼容维护

## 目标和边界

从 v3.0.4 起维护兼容，但不承诺区间内每个精确版本都完成验证。版本登记、请求合同和验证证据分开：

- `MoviePilotVersion` 识别官方稳定三段数字版本和正整数热修订，例如 `v3.0.10 < v3.0.10-1 < v3.0.10-2 < v3.1.0`。不截断 beta、metadata、未知后缀；无法识别单独提示。
- `BackendCompatibilityRegistry` 稀疏登记精确版本。低于下限、区间内未登记、高于最新登记、无法识别、已登记但证据未完成是不同状态。未登记版本列出比它新的全部登记项及限制；高于最新登记建议更新客户端。
- `BackendContractProfile` 只选择已知协议分界，不等于完整支持声明。v3.0.4–v3.0.10 使用旧 lookup 合同，v3.0.10-1–v3.1.0 使用新合同；中间未登记版本仍显示未验证。功能修复可以在同一 profile 内有独立边界，fork 在 v3.0.5 修复。
- 精确已登记版本仍可正常使用已实现能力；尚未实测会明确告知，不把全部功能锁住。未登记/超出范围继续沿用共享请求并保留严格响应校验，属于尽力使用，不是兼容承诺。

不为每个版本复制 APIService 或 Model。已有结构相同的 DTO 共用；只在确定差异处选择适配。运行时不请求 `/openapi.json`，v3.1.0 默认关闭 API 文档不影响连接探测。

## 登记与证据

| 精确后端标签 | 固定后端 commit | 配套前端 | 当前差异和限制 |
| --- | --- | --- | --- |
| v3.0.4 | e195cc164fc8ff869ffee0ea44a49c7ec475310c | v3.0.4 | fork 可能已创建却响应校验失败，事前阻止；lookup 仅非 TMDB 且有标题/年份的影视可跨源回退 |
| v3.0.5 | ce3489ae75ff06119f076550f72df57e6f92a6bf | v3.0.5 | fork 响应恢复有效 ID；lookup 仍为旧合同 |
| v3.0.10-1 | 0aa857173f77de31c7c8d9d2e12052d99f37bcc1 | v3.0.10 | lookup 扩展到 TMDB 与无年份影视，未命中不在客户端模拟后端查询 |
| v3.1.0 | 31537bb89dddd3813037c05c4ed0fb939c885813 | v3.1.0 | 整理预览增加 source_storage/source_item，跨存储相同路径不可去重掉 |

三类运行时证据分别记录：

1. `sourceReview`：上述标签及配套 Web 的 TV 可达端点、订阅公开可写字段、分类引用、fork、lookup 和整理预览源码合同已审查
2. `fixtureValidation`：必须记录 Swift fixture/URLProtocol 测试实际执行结果；当前云端没有 Swift/Xcode，暂为 pending。测试代码存在不算测试通过
3. `liveValidation`：必须记录确切后端版本、环境、日期、只读/副作用范围和实际结果；本次未连接真实 MoviePilot 实例，全部 pending

本次另外执行了隔离的 Python 源码模型/响应序列化验证，其原始证据在 [compatibility-evidence/manifest.json](compatibility-evidence/manifest.json)。该检查实际加载官方 schema 与 ResponseAPIRouter，但使用本地无害计数器替代创建订阅，不启动 MoviePilot、不登录、不访问数据库，也不代表 Swift 或真实实例验收。v3.0.4 返回本地 500 且计数器已增加；v3.0.5、v3.0.10-1、v3.1.0 返回有效 ID。fixture 的来源、固定 commit、SHA256、Python/依赖版本均随文件保存。

主要上游证据：

- [fork 响应模型修复](https://github.com/jxxghp/MoviePilot/commit/2e2a037eb81d1b8f1fd1bcbf3bdf2c945429e776)
- [v3.0.4 订阅公共写入 schema](https://github.com/jxxghp/MoviePilot/blob/e195cc164fc8ff869ffee0ea44a49c7ec475310c/app/schemas/subscribe.py)
- [v3.0.10-1 lookup 合同](https://github.com/jxxghp/MoviePilot/blob/0aa857173f77de31c7c8d9d2e12052d99f37bcc1/app/api/endpoints/subscribe.py)
- [v3.1.0 整理预览 schema](https://github.com/jxxghp/MoviePilot/blob/31537bb89dddd3813037c05c4ed0fb939c885813/app/schemas/transfer.py)

## 生产调用与写回

`APIService.settings.BACKEND_VERSION` 是运行时输入，复用现有会话 owner 和 epoch。切账号、退出、切服务器会失效设置；同账号续期可沿用设置，前台刷新后重新检查版本警告。fork 在没有可解析版本时先读取公开设置，检查会话未变再继续；已知旧版在 POST 前拒绝，不尝试失败后重新创建。

`BackendAPIContract` 只产生 lookup 参数和 fork 能力说明。删除前的精确身份查询永远关闭元数据回退，不因新版扩大读取回退范围而扩大删除目标。fork 能力说明通过原有弹窗反馈展示，不重做页面。

`Subscribe` 作为统一业务模型，`SubscriptionWriteDTO` 单独构造公共写体：

- 两端标签的 Subscribe schema 相同，不伪造版本字段差异
- 保存稳定分类 ID、search_interval、音乐约束等正式可写字段；系统状态、owner、计数、洗版运行优先级等不写回
- 稀疏缺键保持省略，已读取 null 原样保持，显式清空发送 null；用户清空多选项发送 []，0 保持 0
- 仅保存键存在性与用户编辑意图，不保留整个原始 JSON；字符串原值不被 trim 改写
- 分类路径未编辑时保留稳定 ID；改路径时省略旧 ID，避免它覆盖用户修改；显式清空 ID 依官方语义清空分类
- 详情必须返回与请求匹配的正 ID，避免稀疏展示降级掩盖错误 mutation 身份

3.1.0 预览响应的新字段是可选投影，旧响应仍能解码。去重身份由存储域、来源、目标和结果组成，优先 source_storage，再用 source_item.storage；未提供存储域时保持旧版语义。

## 更新一个版本

1. 取目标后端精确标签和 `version.py` 中的配套前端标签，记录固定 commit；不要用前端独立 HEAD
2. 比较 TV 实际使用的接口、返回字段、权限和编辑写回。相同合同复用 profile；发生真实差异才扩展 adapter/DTO
3. 加入稀疏登记记录，分别填写三类证据。不能因版本号较新、源码相同、编译通过或 OpenAPI 可访问就写成实测通过
4. 加 fixtures 和生产入口 URLProtocol 回归：至少原样保存、单字段修改、清空、合法稀疏项、错误成功体、版本分界、切服及迟到结果
5. 更新登记 revision、限制、README、相应测试和本说明。警告确认 ID 包含登记证据/限制指纹，证据有变化会重新提示
6. 在 Mac/Xcode 执行仓库完整 Simulator 构建/测试，记录具体命令和目标。真实后端测试按 `docs/backend-compatibility-tests.md` 独立 opt-in；个人后端副作用测试不能自动启用

可重跑的隔离源码检查（只在信任的官方源码 clone 上执行）：

```sh
python3 -m venv .venv-contract
.venv-contract/bin/python -m pip install -r scripts/compatibility/requirements.txt
.venv-contract/bin/python scripts/compatibility/probe_contracts.py \
  --backend-repo /path/to/MoviePilot \
  --output docs/compatibility-evidence \
  --tags v3.0.4 v3.0.5 v3.0.10-1 v3.1.0
```

## 当前验收状态

云端实际通过：官方 schema/本地响应序列化探针、`python3 -m unittest discover -s scripts/tests -p 'test_backend_contract_probe.py'`（4 项证据回归）、JSON 证据可解析、`git diff --check`。探针会产生 Starlette 关于未来 HTTPX 迁移的弃用提示，不影响本次断言。

未运行：Swift 编译、XCTest、tvOS Simulator、真实 MoviePilot 实例。合并前必须在 Mac/Xcode 补跑标准完整构建与测试；没有真实后端配置时应保持 liveValidation pending，不能改成 verified。
