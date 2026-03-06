# MoviePilot-TV

<p align="center">
  <a href="https://github.com/jxxghp/MoviePilot"><img src="https://img.shields.io/badge/MoviePilot-v2.9.13-darkviolet?style=flat-square" alt="MoviePilot Backend Version"></a>
  <img src="https://img.shields.io/badge/platform-tvOS_17%2B-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift-orange.svg?style=flat-square" alt="Language">
  <img src="https://img.shields.io/badge/UI-SwiftUI-blue.svg?style=flat-square" alt="UI Framework">
  <a href="https://github.com/CHANTXU64/MoviePilot-TV/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-CC0--1.0-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/CHANTXU64/MoviePilot-TV/issues"><img src="https://img.shields.io/github/issues/CHANTXU64/MoviePilot-TV?style=flat-square" alt="GitHub issues"></a>
</p>

基于 Swift 和 SwiftUI 开发的 **MoviePilot** Apple TV 原生客户端。为大屏幕和 Siri Remote 遥控器交互而设计。

## 界面预览

<p align="center">
  <img src="screenshots/HomePage.png" alt="首页" width="32%"/>
  <img src="screenshots/RecommendPage.png" alt="推荐页" width="32%"/>
  <img src="screenshots/ExplorePage.png" alt="探索页" width="32%"/>
  <img src="screenshots/MediaDetailPage.png" alt="详情页" width="32%"/>
  <img src="screenshots/MediaDetailPage2.png" alt="详情页2" width="32%"/>
  <img src="screenshots/PersonDetailPage.png" alt="演职员详情页" width="32%"/>
  <img src="screenshots/SubscribeSeason.png" alt="订阅设置" width="32%"/>
  <img src="screenshots/SearchPage.png" alt="搜索页" width="32%"/>
  <img src="screenshots/CollectionDetailPage.png" alt="合集页" width="32%"/>
  <img src="screenshots/TorrentsResultPage.png" alt="种子结果" width="32%"/>
  <img src="screenshots/AddDownloadSheet.png" alt="添加下载" width="32%"/>
  <img src="screenshots/StatusPage.png" alt="状态页" width="32%"/>
</p>

## 核心特性

专为大屏幕和家庭观影设计，提供从浏览、搜索到订阅的完整闭环体验。

- **为家庭设计**: 聚焦核心观影功能，摒弃复杂的管理员后台设置，交互简洁，适合所有家庭成员。
- **原生沉浸体验**: 基于 Swift & SwiftUI 原生开发，遵循 tvOS 设计规范，提供流畅的动效和沉浸式详情页。
- **Siri Remote 完整支持**: 所有功能均可通过 Siri Remote 直观操作，支持长按海报进行订阅、搜索等快捷操作。
- **聚合搜索**: 一键搜索电影、电视剧、合集及演职人员。
- **高效订阅**: 优化订阅流程，在订阅时直接完成配置，一步到位。
- **无缝浏览**: 通过详情页预加载和持久化登录，消除等待，实现无缝切换和快速访问。

## ⚠️ 兼容性与已知问题

- **tvOS 版本**: 支持 **tvOS 17.0+**。本项目主要在 **tvOS 26.0+** 环境下开发，UI 效果在该版本上表现最佳。
- **后端版本**: 当前测试兼容的 MoviePilot 版本限定为：`v2.9.13`。由于 API 可能发生破坏性变更，其他版本后端可能出现功能异常或闪退。
- **账号登录**: **不支持**已开启双因素认证 (MFA/2FA) 的账号，请在关闭双因素认证后再登录。
- **应用更新**: 本应用不对旧版 API 或已知 Bug 进行向下兼容修复。更新频率可能低于 MoviePilot 原版。
- **图片加载问题**:
  - **原因**: MoviePilot 图片缓存以及部分数据源（如豆瓣、Bangumi）的原始图片会返回 **WEBP** 格式图片，而 tvOS 17.x 及更早版本原生不支持解码。
  - **临时方案**: 在 tvOS 17.x 系统上，App 会自动禁用后端的图片代理/缓存功能以尝试规避部分问题。
  - **建议**: 升级至 **tvOS 18.0+** 可解决所有 WEBP 图片加载问题，获得最佳体验。

## 安装指南

> [!IMPORTANT]
> **关于通过官方渠道分发 (App Store / TestFlight)**
> 
> 本项目当前仅支持通过 Xcode 源码构建和安装。
> 
> 若计划通过 TestFlight 或 App Store 进行分发，贡献者需了解以下前提与风险：
> 
> 1.  **开发者计划费用**: 分发需要一个年费为 99 美元的 Apple Developer Program 成员资格。
> 2.  **代码修改工作**: 为通过审查，需要投入精力对现有代码进行调整以满足 [App Store 审查指南](https://developer.apple.com/app-store/review/guidelines/) 的要求。
> 3.  **审查与账号风险**: 提交的应用仍可能被 App Review 拒绝。在极端情况下，违规行为可能导致开发者账号被禁。
> 
> 欢迎有意协助推进官方分发的贡献者，在 Issues 发起讨论。

### Xcode 源码构建 (当前唯一方式)

#### 准备工作
- macOS 26.0+
- Xcode 26.0+

#### 构建步骤
1. 克隆项目代码：
   ```sh
   git clone https://github.com/CHANTXU64/MoviePilot-TV.git
   ```
2. 使用 Xcode 打开 `MoviePilot-TV.xcodeproj`。
3. 选择你的真实 Apple TV 设备（需在同一局域网并已配对）。
4. 在 **Signing & Capabilities** 中选择你的开发者账号，修改 `Bundle Identifier` 为一个唯一的名称（例如 `com.yourname.MoviePilot-TV`）。
5. 点击 **Run** (或 `Cmd + R`) 编译并安装。
6. 自动续签 (可选): 免费账号签名的应用有效期为 7 天，可使用 [Sideloadly](https://sideloadly.io/) 等工具自动续签。


## 反馈与贡献

- **提交 Bug**：请务必提供 MoviePilot 版本号、相关截图和复现步骤。
- **功能建议**：本项目专注提供基础的客厅浏览和订阅体验，过于复杂的后端配置管理等需求暂不考虑。
- **贡献代码**：代码采用纯 Swift 编写。提交 PR 前请确保在真实 Apple TV 上测试过。

## 协议声明

本项目原创代码基于 **[CC0 1.0 Universal](LICENSE)** 协议发布（公有领域）。可自由复制、修改、发布和商业使用。

## 鸣谢

界面及交互设计参考了 **[MoviePilot-Frontend](https://github.com/jxxghp/MoviePilot-Frontend)** 与 Apple TV 官方应用，对相关开发者表示感谢。原项目的相关参考代码和逻辑遵循原作者的 **MIT License**。
