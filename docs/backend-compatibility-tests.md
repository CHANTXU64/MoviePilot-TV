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

GitHub CI 没有真实后端账号，`ci.yml` 会显式跳过 `BackendCompatibilityReadOnlyTests` 和 `BackendCompatibilitySideEffectTests`。真实后端兼容测试应在本机或用户指定的带后端配置环境中运行。

## 真实后端只读套件

`.env.compatibility` 只用于真实 MoviePilot 后端的只读兼容性检查。已配置时，测试会登录后端并按 TV 端真实页面入口巡检：系统配置、仪表盘、站点/下载器/目录配置、订阅读取、媒体服务器最近添加、下载中任务、推荐货架、发现页、搜索、详情页、演员/人物和分季数据。未配置时，这组测试会自动跳过。

巡检采集到的海报、背景图、头像和媒体服务器图片都会实际下载，并在 tvOS XCTest 运行环境中用系统图片解码能力验证；如果后端改成 Apple TV 不支持的图片格式，即使 API 返回正常也会失败。测试也会检查图片代理 URL 是否把内层 query/fragment 正确保留，避免图片地址被外层参数截断。

这组测试不会新增订阅、删除订阅、添加下载、暂停/恢复下载、重置订阅、触发订阅搜索或执行整理任务。可选的 `MOVIEPILOT_COMPAT_METADATA_QUERY` / `MOVIEPILOT_COMPAT_METADATA_QUERIES` 只会调用元数据搜索和详情读取；如果搜索结果包含合集，还会继续读取合集详情。也可以用 `MOVIEPILOT_COMPAT_COLLECTION_ID` / `MOVIEPILOT_COMPAT_COLLECTION_IDS` 直接指定合集 ID。

默认还会检查标题识别、TMDB ID 识别、整理历史读取和订阅状态读取，以覆盖 TV 端现有后台能力。若要额外检查资源搜索兼容性，可配置 `MOVIEPILOT_COMPAT_RESOURCE_QUERY` / `MOVIEPILOT_COMPAT_RESOURCE_QUERIES` 或 `MOVIEPILOT_COMPAT_RESOURCE_MEDIA_ID` / `MOVIEPILOT_COMPAT_RESOURCE_MEDIA_IDS`；这只会调用资源搜索并解码结果，不会添加下载。`MOVIEPILOT_COMPAT_TEST_RESOURCE_SEARCH_STREAMS=true` 会额外检查资源搜索 SSE 流式接口，耗时更长，默认关闭。若要检查分季已入库状态，可设置 `MOVIEPILOT_COMPAT_CHECK_SEASON_AVAILABILITY=true`；该检查只读取媒体服务器状态，不会创建订阅。

如果在独立 worktree 中运行测试，可以用 `MOVIEPILOT_COMPAT_ENV_FILE=/absolute/path/.env.compatibility` 指向已有配置文件；命令行环境变量会覆盖配置文件中的同名值。

## 副作用套件

副作用测试默认开启。运行 `BackendCompatibilitySideEffectTests` 时，已配置真实后端的情况下会默认执行下面这些流程；如果某次兼容性检查不想跑某一项，可在 `.env.compatibility` 中把对应开关设为 `false`。

- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_SEARCH=true`：取现有订阅列表最近几条，触发订阅搜索。
- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_UPDATE=true`：读取现有订阅详情，然后用原详情原样保存一次，不修改参数。
- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_PAUSE_RESUME=true`：只取正在订阅的 `state=R` 条目，先暂停为 `S`，再恢复为 `R`；不会把原本已暂停的 `S` 条目恢复。
- `MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_RESET_SEARCH=true`：取现有订阅列表最近几条，重置订阅后立即触发同一条订阅搜索。
- `MOVIEPILOT_COMPAT_TEST_MANUAL_REORGANIZE=true`：取整理历史第一页最近几条，按 TV 端 `ReorganizeForm` 编码后并发触发后台手动重新整理。
- `MOVIEPILOT_COMPAT_TEST_AI_REORGANIZE=true`：取整理历史第一页最近几条，批量触发 AI 重新整理，并检查返回的进度流。

这些测试不会新增订阅、删除订阅、添加下载、删除下载或删除整理历史。订阅重置、订阅搜索、暂停/恢复订阅、手动/AI 重新整理都会触发真实后台动作；只应在你接受这些影响的后端上运行副作用套件。

`MOVIEPILOT_COMPAT_SIDE_EFFECT_SUBSCRIPTION_LIMIT` 控制订阅测试取几条现有订阅，默认 `3`。`MOVIEPILOT_COMPAT_REORGANIZE_HISTORY_LIMIT` 控制整理测试取几条最近历史，默认 `2`。`MOVIEPILOT_COMPAT_REORGANIZE_CONCURRENT_COUNT` 控制手动重新整理的并发数量，默认 `2`。

新增/删除订阅、下载任务增删改、删除整理历史等更强破坏性流程仍不在个人后端兼容套件内；如果后续要测，应使用可丢弃数据库、测试下载器和测试媒体目录的隔离 MoviePilot 后端。
