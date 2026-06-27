# Processing CLI

本目录承载本地 processing/dependency-check CLI。组件注册状态以 `harness/project-manifest.json` 为准。

当前已实现：

1. `check_dependencies` 命令契约。
2. 稳定 JSON 响应、API 契约 exit code 映射和缺失依赖失败语义。
3. fake 环境下的 dependency-check 单元测试，包含 `whisper.cpp` runtime 可执行文件、multilingual 模型路径、推荐模型等级硬件 preflight 和 English-only `.en` 模型拒绝。
4. Workspace 和 artifact contract 内核，包括 `session.json` 创建、artifact 登记、checksum、路径边界和单会话 lock。
5. `import_media` 命令契约，支持显式本地媒体文件复制到新会话 `artifacts/` 并登记为 `mixed_audio` 或 `screen_video`。
6. 内部 normalized audio stage：默认选择 `mixed_audio`；`mixed_audio` 缺失时仅处理用户显式选择的可用 `system_audio` 或 `microphone_audio`；在当前 fixture-compatible slice 中只接受 WAV/PCM 源，生成并登记 `artifacts/normalized_audio.wav`，且不覆盖原始音频 artifact。
7. `generate_transcript` 命令契约的 fake adapter，使用可用 `normalized_audio` 或显式/默认音频输入生成 `artifacts/transcript.json` 并登记 `transcript_text` artifact。
8. `runtime=whisper_cpp` 的最小本地 adapter：显式请求时调用用户配置的本地 `whisper.cpp` CLI，解析 JSON 输出并写入同一 `transcript.json` 契约。
9. `generate_speaker_labels` 命令契约：默认支持 transcript-only fallback，写入 `artifacts/speaker_labels.json` 并登记降级的 `speaker_labels` artifact；可注入本地 fake/best-effort adapter，但不选择真实外部 speaker runtime。
10. `export_transcript` 命令契约：支持 `plain_text`、`markdown`、`json` 内容返回或用户显式目标路径导出，不修改 transcript 或媒体 artifact。
11. `delete_session` 命令契约：要求 `confirm=true`，只删除当前 workspace 中目标 session 目录，并保留 workspace 外导出文件。
12. 结构、架构、安全和 SBOM 检查。

当前目录没有公开 `normalize_audio` 命令；标准化音频是 `generate_transcript` 或原生处理流程可复用的内部 stage。当前 normalized audio stage 使用 fixture-compatible WAV/PCM adapter 边界。当前 transcript adapter 包含 deterministic fake 和最小 `whisper.cpp` 调用路径；speaker labeling 只提供 transcript-only fallback 和可注入 adapter 边界，不选择 WhisperX、pyannote.audio 或其他真实 speaker runtime。当前组件不承诺生产级转码、生产级识别质量、生产级 speaker labeling、外部模型调用或自动依赖下载。真实 `PV-MA-007` covered 仍需要本机 `whisper.cpp` CLI、multilingual 模型和中英混合小样例 smoke 进入标准门禁。

本机共享资产约定：

```bash
export MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$HOME/.local/bin/whisper-cli"
export MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$HOME/.local/share/ai-models/whisper.cpp/large-v3-turbo/ggml-large-v3-turbo-q5_0.bin"
export MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$HOME/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav"
```

当前本机已在 `~/.zshrc` 的 `meeting_assistant whisper.cpp smoke runtime` 标记块中持久化上述三项环境变量，因此新开的 zsh 终端从项目根目录运行 `./scripts/check.sh` 时会执行真实 `whisper.cpp` smoke。未安装 `direnv` 的环境继续使用 shell profile；若后续改用 `direnv`，`.envrc` 应只包含同一组三个 export，并由开发者手动 `direnv allow`。该持久化只记录本地路径，不包含 secret，也不代表自动下载、自动发现或自动安装 runtime/model。

当前本机已验证的 shared runtime 和模型：

| 资产 | 当前值 |
|---|---|
| runtime source | `https://github.com/ggml-org/whisper.cpp` |
| runtime version | `v1.9.1` |
| runtime commit | `f049fff95a089aa9969deb009cdd4892b3e74916` |
| runtime entry | `~/.local/bin/whisper-cli` -> `~/.local/opt/whisper.cpp/v1.9.1/bin/whisper-cli` |
| model source | `https://huggingface.co/ggerganov/whisper.cpp` |
| model file | `~/.local/share/ai-models/whisper.cpp/large-v3-turbo/ggml-large-v3-turbo-q5_0.bin` |
| model sha256 | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` |

`scripts/smoke-whisper-cpp.sh` 是条件真实 runtime smoke 入口，并由 `scripts/test.sh` 调用。未配置 runtime/model 或缺少混合语言 WAV fixture 时默认报告 not run；设置 `MEETING_ASSISTANT_REQUIRE_WHISPER_CPP_SMOKE=1` 后缺依赖或缺少 fixture 会失败。若未设置 `MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO`，脚本会检查默认 fixture 路径 `~/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav`。fixture 必须包含中文为主且夹杂 `HTTP`、`LLM`、`clean architecture`、`EDA` 的语音；脚本会拒绝非 `large-v3`/`large-v3-turbo` 名称模型，并断言 transcript 含中文字符和这些英文技术术语。该脚本的 not-run 结果不能作为 `PV-MA-007` covered 证据。
