# Codex 上下文启动器

一个 macOS 启动器，用于选择 Codex 模型、设置单次会话的上下文窗口和自动压缩阈值，并在终端新建或续接本机会话。

## 使用

1. 打开应用，选择新建或续接。新建时可选择项目目录。续接时可填入会话 UUID，也可留空后在终端按标题选择。
2. 从当前模型目录选择模型，或输入模型 ID。模型留空时，新建会话使用 Codex 的默认模型，续接时保留原会话模型。
3. 按 Token 填整数，也可留空沿用 Codex 设置。切换模型时清空上一模型的窗口和压缩覆盖。**Astra 800K / 700K** 按钮会填入 `gpt-6.2-astra`、`800000` 和 `700000`。
4. 点击「在终端启动」。续接正在运行的会话前，先等待当前轮结束并让原客户端释放会话。开始新一轮后可在终端运行 `/status` 查看窗口。

启动器使用 Codex CLI 原生的 `--model` 和 `-c` 参数。项目设置、账号登录、MCP 和权限继续由 Codex 管理。用同一会话切换配置时，从启动器重新续接即可。

## 数值校验

- 应用调用 `codex debug models` 读取当前 CLI 的模型目录。也可以更换 CLI 并刷新目录。
- 窗口覆盖上限使用目录中的 `max_context_window`。如果目录只声明默认窗口，应用以默认窗口为可验证上限。手动输入的模型若缺少窗口数据，仍可启动，数值沿用 Codex 设置。
- 界面按目录给出的 `effective_context_window_percent` 估算可用窗口，默认比例为 95%。压缩阈值上限取标称窗口的 90% 和可用窗口中的较小值。例如 800,000 标称窗口通常对应 760,000 可用 Token。
- 估算使用读取到的模型目录。重新加载会话后，实际值还受客户端版本、账号权限、服务端目录和现有压缩策略影响。只有本地 CLI 能访问的会话可以续接。Desktop 的模型选择器不会自动应用启动器里的覆盖值。

## 从源码构建

需要 macOS 13 或更新版本、带 Swift 5.9 或更新版本的 Xcode 命令行工具，以及支持 `codex debug models` 和 `--no-daemon` 的 Codex CLI。本机验证版本为 `0.169.0-alpha.11.1`。

```sh
swift run LauncherChecks
./scripts/build-app.sh
open 'dist/Codex 上下文启动器.app'
```

构建脚本生成本机架构的临时签名应用。启动器会查找 Desktop 内置 CLI 和常见安装路径，也可在界面选择可执行文件。

[Codex 配置参考](https://developers.openai.com/codex/config-reference/) · [Codex CLI 参考](https://developers.openai.com/codex/cli/reference/)
