# Native App Project Skeleton

本目录是非业务 project skeleton，用于给原生 macOS 控制面预留组件边界和门禁入口。组件注册状态以 `harness/project-manifest.json` 为准。

当前目录只允许包含：

1. 组件元数据。
2. 结构检查脚本。
3. 架构和安全边界检查。
4. 最小 SBOM 描述。

当前目录不得实现真实录制、屏幕捕获、系统音频捕获、麦克风捕获、转写、speaker labeling、外部模型调用或自动依赖下载。
