# Contributing to AriaLane

欢迎提交 Issue 和 Pull Request。提交改动前，请：

1. 说明要解决的问题和可验证的预期行为。
2. 保持 macOS 原生交互与现有简洁视觉风格。
3. 不提交下载记录、RPC Secret、Cookie、证书或其他私密数据。
4. 为模型、RPC 解析和业务规则变更补充测试。
5. 在 macOS 14 或更高版本运行：

```bash
./script/check_repository_secrets.sh
./script/test.sh
```

较大的功能建议先开 Issue 对齐交互与范围。安全问题请按
[SECURITY.md](SECURITY.md) 私下报告。
