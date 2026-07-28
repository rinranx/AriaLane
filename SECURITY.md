# Security Policy

## Supported versions

安全修复优先提供给最新 GitHub Release 和 `main` 分支。旧版本可能不会单独
维护，请先确认问题能在最新版本复现。

## Reporting a vulnerability

请优先使用 GitHub 的 **Private vulnerability reporting**，不要在公开 Issue
中粘贴漏洞细节、访问密钥、Cookie、RPC Secret 或可识别个人身份的数据。

如果仓库尚未启用私密漏洞报告，可以通过
[@rinran223](https://x.com/rinran223) 联系维护者，并只发送建立安全沟通
所需的最少信息。收到报告后会先确认影响范围，再协调披露和修复时间。

## RPC deployment guidance

- 为 aria2 RPC 配置足够强的 `rpc-secret`。
- 不要把未加密的 6800 端口直接暴露到公网。
- 远程访问优先使用可信 VPN，或通过有 TLS 和访问控制的反向代理连接。
- 不要在 Issue、日志或截图中公开 RPC Secret、Cookie、认证 Header。
- 计划任务和断线待发送任务可能包含认证参数；它们只应保存在权限为 `0600`
  的本机应用支持文件中，不要手动同步或公开这些存档。
