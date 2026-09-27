# 签名与打包说明

本文面向源码构建、维护发布流程和排查签名问题的开发者。普通 IPA 安装步骤见 [README](../README.md#方式一下载-ipa-并自签侧载)。

## IPA 打包与重签

主 App 和 Top Shelf 扩展位于同一个 IPA 内。发布包尚未使用 Apple 开发者证书签名，需要用户通过侧载工具重新签名后安装。

发布流程使用本地 ad-hoc 签名保留主 App 和扩展的 App Group 权限声明，供重签工具识别。包内不包含维护者的 provisioning profile 或私钥；这种本地签名不能用于真机安装。

CI 和 Release 工作流统一调用 `scripts/package-ipa.py`。该脚本移除开发者 profile，为主 App 和扩展写入重签所需的共享组元数据，并在生成 IPA 前验证扩展存在、签名完整和共享组一致。不要直接把关闭签名后编译出的 `.app` 压缩发布。

```bash
python3 scripts/package-ipa.py \
  --app "build/DerivedData/Build/Products/Release-appletvos/MoviePilot-TV.app" \
  --output "build/MoviePilot-TV-unsigned.ipa"
```

### 重签后 Top Shelf 不显示时

先确认侧载工具保留了 Top Shelf 扩展，并为主 App 和扩展授权同一个 App Group。只有主 App 能启动，不代表扩展已获得共享数据的权限。

App 和扩展使用同一套规则，从各自的签名中识别 `TopShelfAppGroupIdentifier` 配置的组名，或 ATVloadly/PlumeImpactor 使用的“原组名追加当前 Team ID”形式，使共享缓存和 Keychain 使用同一组。

如果其他工具采用不同的组名改写规则，需要由重签流程同步修改主 App 与扩展 Info.plist 中的 `TopShelfAppGroupIdentifier`。这是工具兼容性排查，不是普通安装步骤。

## 源码构建与续签

`scripts/apple-tv-renew.sh` 把 `BUNDLE_ID` 传给工程的 `APP_BUNDLE_IDENTIFIER`，同时派生 App Group。使用已有 Group 时，可通过 `APP_GROUP_IDENTIFIER="group.yourteam.SharedLibrary"` 覆盖；构建和产物定位会沿用同一配置。更换 Group 后需打开 App，重新生成 Top Shelf 内容。

脚本检查本机 DerivedData 中主 App、Top Shelf 和所有嵌入扩展的：

- 完整签名，以及实际签名证书是否获 profile 授权。
- Bundle ID、签名团队、App Group 与当前构建配置是否一致。
- 每个 `embedded.mobileprovision` 的授权和有效期。

只有完整产物符合当前配置，且全部 profile 未过期时才跳过。更换 Group 或团队、缺少扩展或签名损坏都会触发重新构建。脚本不会确认 Apple TV 设备端是否仍安装了该 App。

安装前会重复上述检查，并以最短剩余有效期验收 `MIN_VALID_SECONDS`（默认 5 天），不满足时停止安装。`CLEAR_PROFILE_CACHE=1` 会备份并移走该 App 及其子标识的本地 profile，保留其他 App 的缓存。

`--force` 会忽略跳过条件，强制构建和安装，但不保证 Xcode/Apple 签发新的 profile。如果仍复用未过期的 profile，应用的到期时间不会延长。

## 模拟器构建与测试

模拟器构建和测试必须保留本地签名，使用 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`，完整命令见 [AGENTS.md](../AGENTS.md#0-本项目标准验证命令)。

测试会覆盖安装主 App 和扩展。关闭签名会让 App 丢失 App Group 权限，导致首页退回静态 Top Shelf。

单元测试宿主不启动正常 App 根视图的会话加载和 Top Shelf 同步，避免测试会话覆盖用户的首页数据。测试仍通过真实系统 API 检查共享容器和 Keychain 权限。修改签名、打包或共享组后，还应核对测试结束后的共享容器访问和实际首页展示。
