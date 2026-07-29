# AriaLane 发布指南

AriaLane 的源码采用 GPL-3.0-only 许可证。仅发布源码不需要 Apple 签名；向普通
macOS 用户提供可直接运行的 `.app` 或 `.zip` 时，建议使用 Developer ID
Application 签名、Hardened Runtime 和 Apple 公证。

## 发布前准备

当前 ad-hoc 公开发布需要：

- 一对只用于 AriaLane 更新的 Sparkle EdDSA 密钥
- GitHub 仓库的 Actions 权限允许工作流创建 Release

如需 Developer ID 正式签名与 Apple 公证，还需要：

- Apple Developer Program 会员资格
- `Developer ID Application` 证书及其私钥
- 用于公证的 Apple ID、Team ID 和 App 专用密码

请勿把 `.p12`、密码、Sparkle 私钥或公证凭据提交到仓库。

### GitHub Actions 配置

当前公开 Release 工作流使用 ad-hoc 代码签名，并通过 Sparkle EdDSA 签名保护
应用内更新。必须先在仓库的 **Settings → Secrets and variables → Actions**
中配置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Secret | `SPARKLE_PRIVATE_KEY` | Sparkle 私钥内容 |
| Variable | `SPARKLE_PUBLIC_ED_KEY` | 与私钥对应的 Sparkle 公钥 |

工作流缺少任一值时会直接失败，避免发布一个看似支持更新、实际没有更新源的
安装包。

如需改为 Developer ID 签名和 Apple 公证，还需要以下凭据，并相应扩展发布
工作流：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Secret | `DEVELOPER_ID_APPLICATION_P12` | Developer ID `.p12` 文件的 Base64 内容 |
| Secret | `DEVELOPER_ID_APPLICATION_PASSWORD` | 导出 `.p12` 时设置的密码 |
| Secret | `KEYCHAIN_PASSWORD` | Actions 临时钥匙串的随机强密码 |
| Secret | `APPLE_ID` | Apple Developer 账号 |
| Secret | `APPLE_TEAM_ID` | 10 位 Team ID |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | Apple ID 的 App 专用密码 |

生成 `.p12` 的 Base64 内容：

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Sparkle 的 `generate_keys` 工具位于 SwiftPM 下载的 Sparkle artifact 中。
生成后，把私钥作为 GitHub Secret 保存，把公钥作为 Repository Variable
保存，并另外保留一份离线备份。遗失私钥会中断已经发布版本的可信自动更新链。

## 本机构建

没有证书时，下列命令会生成 ad-hoc 签名的 Universal Binary，仅适合本机测试：

```bash
./script/package_release.sh
```

正式构建可以明确要求 Developer ID，并同时配置 Sparkle 与公证：

```bash
export REQUIRE_DISTRIBUTION_SIGNING=1
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="AriaLaneNotary"
export SPARKLE_FEED_URL="https://github.com/OWNER/REPO/releases/latest/download/appcast.xml"
export SPARKLE_PUBLIC_ED_KEY="PUBLIC_KEY"
./script/package_release.sh
```

如果公证凭据存放在非默认钥匙串，还需设置 `NOTARY_KEYCHAIN`。构建脚本会依次：

1. 构建 arm64 与 x86_64 并合并为 Universal Binary。
2. 嵌入并签名 Sparkle 的嵌套组件。
3. 启用 Hardened Runtime 并使用可信时间戳。
4. 提交 Apple 公证，装订票据并验证 Gatekeeper。
5. 输出 `outputs/AriaLane-<version>-macOS-universal.zip`。

## GitHub Release

1. 在 `Resources/Info.plist` 更新版本号和构建号。
2. 合并并推送到 `main`，或手动运行 Release 工作流。
3. 工作流会运行测试、构建 Universal ZIP 与 DMG、把 Sparkle Feed URL 和
   公钥注入应用、生成带 EdDSA 签名的 `appcast.xml`，然后创建或更新与版本
   一致的 GitHub Release。
4. 从下一次发布开始，每次都必须递增
   `CFBundleShortVersionString` 和 `CFBundleVersion`，否则 Sparkle 不会把
   新包识别为升级版本。

最初发布的 `1.0.0` 没有更新源时，可以重新发布一个仍为 `1.0.0` 的引导包。
此前已经安装旧包的用户需要手动重新下载一次；重新下载安装后的用户才能通过
应用内更新升级到 `1.0.1` 及更高版本。

当前工作流使用 ad-hoc 代码签名，没有进行 Apple 公证。Sparkle 更新包仍会
通过 EdDSA 签名校验；如需免除 Gatekeeper 手动允许步骤，应再接入
Developer ID 签名和 Apple 公证。

发布后请从一台未安装开发证书的 Mac 下载 Release。ad-hoc 版本至少确认代码
签名结构完整：

```bash
codesign --verify --deep --strict --verbose=2 /Applications/AriaLane.app
```

Developer ID 正式版本还应确认 Gatekeeper 和公证票据：

```bash
spctl --assess --type execute --verbose=2 /Applications/AriaLane.app
xcrun stapler validate /Applications/AriaLane.app
```

Apple 官方资料：

- [Distribute outside the Mac App Store](https://developer.apple.com/macos/distribution/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Developer ID certificate](https://developer.apple.com/help/glossary/developer-id-certificate/)

Sparkle 官方资料：

- [Sparkle documentation](https://sparkle-project.org/documentation/)
- [Publishing an update](https://sparkle-project.org/documentation/publishing/)
- [Sandboxing](https://sparkle-project.org/documentation/sandboxing/)
