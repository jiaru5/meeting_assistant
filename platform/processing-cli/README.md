# Processing CLI Skeleton

本目录承载本地 processing/dependency-check CLI。组件注册状态以 `harness/project-manifest.json` 为准。

当前已实现：

1. `check_dependencies` 命令契约。
2. 稳定 JSON 响应和缺失依赖失败语义。
3. fake 环境下的 dependency-check 单元测试。
4. 结构、架构、安全和 SBOM 检查。

当前目录仍不得实现真实媒体处理、真实转写、真实 speaker labeling、外部模型调用或自动依赖下载。
