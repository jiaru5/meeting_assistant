# Processing CLI

本目录承载本地 processing/dependency-check CLI。组件注册状态以 `harness/project-manifest.json` 为准。

当前已实现：

1. `check_dependencies` 命令契约。
2. 稳定 JSON 响应和缺失依赖失败语义。
3. fake 环境下的 dependency-check 单元测试。
4. Workspace 和 artifact contract 内核，包括 `session.json` 创建、artifact 登记、checksum、路径边界和单会话 lock。
5. `import_media` 命令契约，支持显式本地媒体文件复制到新会话 `artifacts/` 并登记为 `mixed_audio` 或 `screen_video`。
6. 内部 normalized audio stage：默认选择 `mixed_audio`；`mixed_audio` 缺失时仅处理用户显式选择的可用 `system_audio` 或 `microphone_audio`；在当前 fixture-compatible slice 中只接受 WAV/PCM 源，生成并登记 `artifacts/normalized_audio.wav`，且不覆盖原始音频 artifact。
7. `generate_transcript` 命令契约的 fake adapter，使用可用 `normalized_audio` 或显式/默认音频输入生成 `artifacts/transcript.json` 并登记 `transcript_text` artifact。
8. 结构、架构、安全和 SBOM 检查。

当前目录没有公开 `normalize_audio` 命令；标准化音频是 `generate_transcript` 或原生处理流程可复用的内部 stage。当前 normalized audio stage 使用 fixture-compatible WAV/PCM adapter 边界，当前 transcript adapter 是 deterministic fake，不承诺生产级转码、真实转写 runtime、真实 speaker labeling、外部模型调用或自动依赖下载。
