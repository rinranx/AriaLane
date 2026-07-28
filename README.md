# AriaLane

[![GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-5c6ac4.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111.svg)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-f05138.svg)
![Version 1.0.0](https://img.shields.io/badge/version-1.0.0-2ebfa5.svg)

AriaLane 是一个简约、原生的 macOS aria2 桌面客户端。它既能自动
连接本机 `aria2c`，也能管理多个远程 aria2 JSON-RPC 服务器。

当前版本：**1.0.0**

作者：rinran（[a@rinran.me](mailto:a@rinran.me)）

## 功能

### 下载管理

- 添加 HTTP、HTTPS、FTP、SFTP、magnet 链接
- 从图片文件或照片图库识别二维码中的下载链接
- `⌘⇧V` 从剪贴板预填任务，或通过 `arialane://add` 从浏览器唤起
- 一次拖入多个链接、`.torrent`、`.metalink` 或 `.meta4`，导入文件会排队逐个选择
- Torrent 导入支持文件选择与 HTTP(S)/FTP Web Seed
- 高级任务设置：文件名、保存目录、单任务上传/下载限速与备用镜像
- Referer、User-Agent、自定义 Header、Cookie、用户名与密码
- SHA-1 / SHA-2 / MD5 校验、分段数与单服务器连接数
- 单任务代理、TLS 证书、FTP/SFTP、BT、Metalink 与任意 aria2 参数
- 暂停、强制暂停、继续、单个或批量重试、移除、批量操作和拖放调整队列
- 按名称、来源、路径搜索，并按状态、名称、大小、进度、速度或队列排序
- aria2 断线时持久化保存待发送链接，恢复连接后自动提交

### 状态与历史

- 连续的任务进度条和列表整体进度
- 可折叠的最近 3 分钟下载/上传速度曲线
- 本机下载历史，可搜索、排序、重新下载或在 Finder 中显示
- 用户标签贯穿当前任务与下载历史，支持列表批量分配、右键菜单和检查器编辑
- 智能文件夹按标签、内容类型、传输协议、来源域名、日期与任务状态动态筛选
- 任务详情包含文件选择、镜像增删、运行中参数、BT Peer、服务器连接、
  Info Hash 和文件分块状态
- 下载完成或失败提示，以及错误原因和快捷重试

### 自动化与系统集成

- 定时添加下载任务，可编辑、复制、立即开始或取消
- RSS / Atom 订阅定时刷新，可选择服务器并自动下载新附件
- 过期计划会安全转入待发送队列，使用稳定 GID 避免恢复时重复提交
- 跨午夜的夜间限速，结束后自动恢复日间设置
- 菜单栏迷你窗口，可快速查看速度、任务并暂停或继续
- Dock 图标显示加权总进度
- 可选开机启动
- 下载期间防止系统自动休眠，任务结束后立即释放
- 自动保存 aria2 会话并恢复未完成任务
- 中文与英文界面，可在设置中跟随系统或手动切换

### aria2 与连接

- 多个本机或远程 aria2 服务器配置，一键切换
- 待发送任务绑定原服务器，切换配置时不会误发，并可手动改发到当前服务器
- RPC Secret 使用 macOS 钥匙串保存
- WebSocket 实时状态通知，断开时自动回退到定时刷新并重连
- `system.multicall` 批量操作，以及 RPC 方法和通知能力探测
- 连接诊断显示 aria2 版本、功能、RPC 能力、Session ID、任务数量与响应耗时
- 全局和新任务限速、并发数、分段、连接、超时与重试
- DHT、PEX、LPD、BT 端口、节点数和做种规则
- 全局代理、TLS、Cookie、FTP/SFTP、BT 加密、Tracker 与 Metalink 偏好
- 保存会话、清理下载结果，以及正常或强制关闭远程 aria2
- 断点续传、文件预分配、自动重命名与远端时间

### 发布能力

- arm64 与 x86_64 Universal Binary
- Developer ID、Hardened Runtime、Apple 公证与票据装订
- Sparkle 2 自动更新与 EdDSA 更新签名
- GitHub Actions 自动测试和正式 Release 流程

## 语言

AriaLane 1.0.0 支持简体中文与英文，并可在 **设置 → 通用 → 语言** 中切换：

- 默认跟随系统语言。
- 系统首选语言为任意中文时显示中文。
- 系统首选语言为英文时显示英文。
- 系统首选语言既不是中文也不是英文时，回退显示英文。
- 也可以手动固定为“简体中文”或 “English”。
- 其他语言在逐步更新。

英文界面由本地大模型 `gemma4:31b` 翻译，可能存在错误或不够自然的表达。
若中英文含义不一致，以中文原文为准。欢迎通过 Issue 或 Pull Request 提出
英文翻译修正。

## 系统要求

- macOS 14 Sonoma 或更高版本
- aria2

使用 Homebrew 安装 aria2：

```bash
brew install aria2
```

## 构建与运行

```bash
./script/build_and_run.sh
```

常用命令：

```bash
# 仅构建应用
./script/build_and_run.sh --build

# 运行测试
./script/test.sh

# 生成 Universal Binary 压缩包
./script/package_release.sh
```

没有 Developer ID 证书时，打包脚本会使用 ad-hoc 签名，产物仅适合开发测试。
面向普通用户的 GitHub Release 应使用正式签名和 Apple 公证。完整步骤见
[发布指南](docs/RELEASING.md)。

## 使用远程 aria2

在 **设置 → 连接** 中添加服务器名称、JSON-RPC 地址与 RPC Secret。远程
地址可使用 HTTP(S) 或 WS(S) JSON-RPC 端点。

请勿把未加密的 aria2 RPC 端口直接暴露到公网。建议设置强 `rpc-secret`，
并通过可信 VPN 或带 TLS 和访问控制的反向代理连接。更多建议见
[安全策略](SECURITY.md)。

## 从浏览器添加

AriaLane 注册了只用于添加任务的 URL Scheme。浏览器扩展、快捷指令或其他
应用可以打开：

```text
arialane://add?url=https%3A%2F%2Fexample.com%2Ffile.zip
```

外部链接只会打开并预填“添加下载”窗口，仍需手动确认，不会静默开始下载。

## 快捷键

- `⌘N`：添加下载
- `⌘⇧V`：从剪贴板添加
- `⌘O`：导入 Torrent / Metalink
- `⌘R`：刷新任务
- `⌘⇧P`：暂停全部
- `⌘⇧R`：继续全部
- `⌘,`：打开设置

## 参与贡献

请先阅读 [贡献指南](CONTRIBUTING.md)。报告安全问题时不要创建包含漏洞细节
或凭据的公开 Issue，请按 [安全策略](SECURITY.md) 私下联系。

## 隐私与许可证

AriaLane 不包含遥测、广告或账户系统。数据处理说明见
[PRIVACY.md](PRIVACY.md)。

本项目采用 [GNU General Public License v3.0 only](LICENSE)
（SPDX：`GPL-3.0-only`），
版权所有：[rinran（a@rinran.me）](COPYRIGHT)。
作者的 X：[@rinran223](https://x.com/rinran223)。
第三方组件许可见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
