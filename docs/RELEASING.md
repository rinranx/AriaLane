# AriaLane 发布指南

AriaLane 的源码采用 GPL-3.0-only 许可证。仅发布源码不需要 Apple 签名；向普通
macOS 用户提供可直接运行的 `.app` 或 `.zip` 时，建议使用 Developer ID
Application 签名、Hardened Runtime 和 Apple 公证。

## 发布前准备

需要：

- Apple Developer Program 会员资格
- `Developer ID Application` 证书及其私钥
- 用于公证的 Apple ID、Team ID 和 App 专用密码
- 一对只用于 AriaLane 更新的 Sparkle EdDSA 密钥
- GitHub 仓库的 Actions 权限允许工作流创建 Release

请勿把 `.p12`、密码、Sparkle 私钥或公证凭据提交到仓库。

### GitHub Actions 配置

在仓库的 **Settings → Secrets and variables → Actions** 中配置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Secret | `DEVELOPER_ID_APPLICATION_P12` | Developer ID `.p12` 文件的 Base64 内容 |
| Secret | `DEVELOPER_ID_APPLICATION_PASSWORD` | 导出 `.p12` 时设置的密码 |
| Secret | `KEYCHAIN_PASSWORD` | Actions 临时钥匙串的随机强密码 |
| Secret | `APPLE_ID` | Apple Developer 账号 |
| Secret | `APPLE_TEAM_ID` | 10 位 Team ID |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | Apple ID 的 App 专用密码 |
| Secret | `SPARKLE_PRIVATE_KEY` | Sparkle 私钥内容 |
| Variable | `SPARKLE_PUBLIC_ED_KEY` | 与私钥对应的 Sparkle 公钥 |

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
2. 合并并推送所有更改，确认 CI 通过。
3. 创建与版本一致的标签，例如版本 `1.0.0` 使用 `v1.0.0`。
4. 推送标签。

```bash
git tag -a v1.0.0 -m "AriaLane 1.0.0"
git push origin v1.0.0
```

如果已经配置 Git 提交签名，也可以把 `-a` 换成 `-s` 创建签名标签。

`.github/workflows/release.yml` 会验证版本、运行测试、签名、公证、生成带
EdDSA 签名的 `appcast.xml`，然后创建 GitHub Release。任何正式签名、公证
或更新密钥缺失都会让流程失败，不会降级发布临时签名包。

发布后请从一台未安装开发证书的 Mac 下载 Release，并确认：

```bash
spctl --assess --type execute --verbose=2 /Applications/AriaLane.app
codesign --verify --deep --strict --verbose=2 /Applications/AriaLane.app
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
