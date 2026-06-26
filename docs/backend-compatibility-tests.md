# 后端兼容性测试

本文档说明如何用真实 MoviePilot 后端验证 TV 端兼容性。默认测试不会访问真实后端；需要运行真实后端兼容测试时，复制 `.env.compatibility.example` 为 `.env.compatibility`，填写后端地址、用户名和密码，然后运行 Xcode 测试。

```sh
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

这里默认关闭 XCTest 并行。未关闭时，Xcode 可能启动多个 `Clone N of Apple TV` 模拟器，把不同测试套件并行分发执行；真实后端兼容测试包含默认开启的副作用套件，串行运行更容易确认执行顺序、定位失败和避免误判。

真实后端巡检在 `Testing started` 后可能数分钟没有增量输出。图片巡检会扫描多个 TV 页面入口、实际下载海报/背景图/头像并等待 tvOS 解码；不要只因为短时间无输出就判断卡死，应等待用例结束或查看 `.xcresult` 中的测试摘要和失败详情。

## 兼容判定原则

真实后端兼容测试只验证 TV 端是否与 MoviePilot Web 前端和 MoviePilot 后端当前行为对齐，不用于替 MoviePilot 官方后端、Web 前端或第三方数据源兜底修 Bug。测试失败后应先判断 MP Web 等价行为：如果 MP Web 同样失败、同样不展示、或按前端逻辑本来就不会发起对应请求，则该问题应记录为上游对齐问题，不应要求 TV 端新增差异化容错。

图片巡检尤其要遵守这一点。TV 图片请求失败时，测试应按 MP Web 的图片 URL 规则生成等价请求；若 Web 等价请求也失败，或原始图片值为空、非可请求 URL，导致 Web 本来也没有可下载图片，则应计入 Web 对齐失败并继续。只有 MP Web 等价图片能正常获取，而 TV 端图片失败，才应判定为 TV 端兼容问题。

GitHub CI 没有真实后端账号，`ci.yml` 会显式跳过 `BackendCompatibilityReadOnlyTests` 和 `BackendCompatibilitySideEffectTests`。真实后端兼容测试应在本机或用户指定的带后端配置环境中运行。

## 真实后端只读套件

`.env.compatibility` 只用于真实 MoviePilot 后端的只读兼容性检查。已配置时，测试会登录后端并按 TV 端真实页面入口巡检：系统配置、仪表盘、站点/下载器/目录配置、订阅读取、媒体服务器最近添加、下载中任务、推荐货架、发现页、搜索、详情页、演员/人物和分季数据。未配置时，这组测试会自动跳过。

只读套件会把权限敏感接口拆成独立用例，避免一个管理员账号全通过后掩盖普通账号失败：

- `testReadOnlySystemEnvCompatibility` 单独验证 `/system/env`。
- `testReadOnlyDashboardCompatibility` 单独验证 `/dashboard/statistic`、`/dashboard/storage`、`/dashboard/downloader`。
- `testReadOnlySystemAndConfigurationCompatibility` 验证配置读取、站点、下载器和目录等 TV 页面入口；其中 `Storages`、`Directories`、`IndexerSites` 必须通过 `/system/setting/public/{key}` 读取，避免普通账号继续命中管理员配置接口。`MediaServers` 在当前 2.13.14 后端没有 public setting endpoint，仍按上游现有接口读取。

巡检采集到的海报、背景图、头像和媒体服务器图片都会实际下载，并在 tvOS XCTest 运行环境中用系统图片解码能力验证；如果后端改成 Apple TV 不支持的图片格式，即使 API 返回正常也会失败。测试也会检查图片代理 URL 是否把内层 query/fragment 正确保留，避免图片地址被外层参数截断。

这组测试不会新增订阅、删除订阅、添加下载、暂停/恢复下载、重置订阅、触发订阅搜索或执行整理任务。可选的 `MOVIEPILOT_COMPAT_METADATA_QUERY` / `MOVIEPILOT_COMPAT_METADATA_QUERIES` 只会调用元数据搜索和详情读取；如果搜索结果包含合集，还会继续读取合集详情。也可以用 `MOVIEPILOT_COMPAT_COLLECTION_ID` / `MOVIEPILOT_COMPAT_COLLECTION_IDS` 直接指定合集 ID。

默认还会检查标题识别、TMDB ID 识别、整理历史读取和订阅状态读取，以覆盖 TV 端现有后台能力。若要额外检查资源搜索兼容性，可配置 `MOVIEPILOT_COMPAT_RESOURCE_QUERY` / `MOVIEPILOT_COMPAT_RESOURCE_QUERIES` 或 `MOVIEPILOT_COMPAT_RESOURCE_MEDIA_ID` / `MOVIEPILOT_COMPAT_RESOURCE_MEDIA_IDS`；这只会调用资源搜索并解码结果，不会添加下载。`MOVIEPILOT_COMPAT_TEST_RESOURCE_SEARCH_STREAMS=true` 会额外检查资源搜索 SSE 流式接口，耗时更长，默认关闭。若要检查分季已入库状态，可设置 `MOVIEPILOT_COMPAT_CHECK_SEASON_AVAILABILITY=true`；该检查只读取媒体服务器状态，不会创建订阅。

如果在独立 worktree 中运行测试，可以用 `MOVIEPILOT_COMPAT_ENV_FILE=/absolute/path/.env.compatibility` 指向已有配置文件；命令行环境变量会覆盖配置文件中的同名值。

## 多账号兼容矩阵

如果配置了 `MOVIEPILOT_COMPAT_ADDITIONAL_USERNAMES`，真实后端兼容套件会在主账号之外，用额外账号重新执行同一套 `APIService` 调用路径。测试不会根据账号权限改走不同函数；普通账号失败时，日志会记录该账号的 `super_user` 和 `permissions`，用于判断失败是否来自后端权限收紧或 TV 端未适配。

`MOVIEPILOT_COMPAT_ADDITIONAL_PASSWORDS` 与额外用户名按顺序对应；本地确实共用密码时可以留空，测试会回退使用 `MOVIEPILOT_COMPAT_PASSWORD`。如果某个密码本身包含逗号，在同一行中把该逗号写成 `\,`，例如 `first-password,pa\,ssword` 会解析为两个密码 `first-password` 和 `pa,ssword`。模板文件中应填写自己的测试账号用户名和密码，不要复用示例值。

## 副作用套件

副作用测试默认开启。运行 `BackendCompatibilitySideEffectTests` 时，已配置真实后端的情况下会默认执行下面这些流程；如果某次兼容性检查不想跑某一项，可在 `.env.compatibility` 中把对应开关设为 `false`。

如果配置了额外账号，副作用套件也会用每个账号执行同一批流程；这会按账号重复触发真实后台动作。

- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_SEARCH=true`：取现有订阅列表中有 ID 和原始状态的条目，触发订阅搜索；执行后会把订阅恢复为原始状态，包括原本已暂停的 `state=S`。
- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_UPDATE=true`：读取现有订阅详情，然后用原详情原样保存一次，不修改参数。
- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_PAUSE_RESUME=true`：只取正在订阅的 `state=R` 条目，先暂停为 `S`，再恢复为 `R`；不会把原本已暂停的 `S` 条目恢复。
- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_RESET_SEARCH=true`：取现有订阅列表中有 ID 和原始状态的条目，重置订阅后立即触发同一条订阅搜索；执行后会把订阅恢复为原始状态，包括原本已暂停的 `state=S`。
- `MOVIEPILOT_COMPAT_TEST_MANUAL_REORGANIZE=true`：取整理历史第一页最近几条，按 TV 端 `ReorganizeForm` 编码后并发触发后台手动重新整理。
- `MOVIEPILOT_COMPAT_TEST_AI_REORGANIZE=true`：取整理历史第一页最近几条，批量触发 AI 重新整理，并检查返回的进度流。

这些测试不会新增订阅、删除订阅、添加下载、删除下载或删除整理历史。订阅重置、订阅搜索、暂停/恢复订阅、手动/AI 重新整理都会触发真实后台动作；只应在你接受这些影响的后端上运行副作用套件。

`MOVIEPILOT_COMPAT_SIDE_EFFECT_SUBSCRIPTION_LIMIT` 控制订阅测试取几条现有订阅，默认 `3`。`MOVIEPILOT_COMPAT_REORGANIZE_HISTORY_LIMIT` 控制整理测试取几条最近历史，默认 `2`。`MOVIEPILOT_COMPAT_REORGANIZE_CONCURRENT_COUNT` 控制手动重新整理的并发数量，默认 `2`。

## 新增测试的副作用规则

新增或修改真实后端兼容测试前，必须先判断它是否会改变真实后端状态或触发后台任务。只读套件只能读取、搜索并解码数据，不能调用订阅搜索、订阅 reset、订阅 update/delete、暂停/恢复、添加/删除下载、手动整理、AI 整理等接口。

如果确实需要覆盖有副作用的接口，必须放进 `BackendCompatibilitySideEffectTests` 或等价的显式副作用套件，并满足以下条件：提供独立环境变量开关；限制目标数量和选择条件；保存目标原始状态并在成功、失败和取消路径中尽力恢复；在本文件说明真实影响。不要把会改变用户个人后端状态的检查混进“只读”或普通全量测试说明里。

新增/删除订阅、下载任务增删改、删除整理历史等更强破坏性流程仍不在个人后端兼容套件内；如果后续要测，应使用可丢弃数据库、测试下载器和测试媒体目录的隔离 MoviePilot 后端。
