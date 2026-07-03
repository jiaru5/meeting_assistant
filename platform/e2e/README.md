# Local E2E Smoke

本目录提供 manifest 驱动的本地 full-stack/E2E smoke。E2E 注册状态以 `harness/project-manifest.json` 为准。

当前 `smoke-test.sh` 覆盖 P2-C / VS-MA-11 的 deterministic processing local smoke：使用临时 workspace 和脚本内生成的 WAV fixture，通过公开 `processing-cli` JSON/exit code 边界串联 `import_media -> generate_transcript` 内部 normalized audio/source selection -> `generate_speaker_labels -> export_transcript -> delete_session`。

该 smoke 覆盖每步 JSON response、exit code、关键 artifact、`session.json` 变化、原始媒体 checksum、用户显式 export target、confirm=false 失败、workspace 外 export 保留和 workspace 级 `meeting_session.deleted.v1` 删除事件。命令 schema 负向、损坏 `session.json`、session lock、导出 metadata 写失败清理、speaker labels 复用再校验、artifact symlink/hardlink fail-closed 等回归由 `platform/processing-cli/scripts/test.sh` 下的组件测试覆盖。它不调用真实 speaker runtime、不上传/下载外部内容，也不依赖真实会议数据或宿主机常驻服务。

`smoke-test.sh` 的 `VS-MA-20 provider/e2e marker [non-contract]` 输出只用于把 provider smoke 证据归因到 import processing chain 的阶段：no-auto-download dependency preflight、invalid delete exit-code path、import checksum、normalized/transcript artifact、speaker transcript-only fallback/no-auto-upload boundary、export conflict/retention 和 delete retention/event。该 marker 文案不是公开 CLI 命令、字段、artifact、error code 或 exit code 契约。

`capture-processing-smoke.sh` 覆盖 VS-MA-20 provider/e2e 的 native_recording-style artifact chain：通过 test-only `source_type=native_recording`、`status=recorded` workspace fixture，验证默认 `mixed_audio`、`system_audio`/`microphone_audio` fallback、lock/path/temp/checksum rollback、no-auto-download/no-auto-upload 边界、workspace 外 export 保留和 delete event summary。它只证明 processing/e2e 可消费 native_recording 形态的 provider artifact，不证明真实 native capture、native UI 触发、release bundle 或真实 runtime 质量。

同一脚本还输出 `VS-MA-21 provider/e2e marker [non-contract]`，用于标记 test-only capture-style provider failure fixture：公开 `generate_transcript --runtime whisper_cpp` 在缺失 runtime/model env 时返回既有 `dependency_missing` / exit 4，fake whisper runtime 非零失败时返回既有 `processing_failed` / exit 5，并断言失败响应、processing log、capture checksum、derived artifact 污染和 retry success 边界。该 marker 不是公开 CLI 命令、字段、artifact、error code 或 exit code 契约，也不代表真实 native UI、真实 native capture、真实 release bundle 或所有开发机 runtime/model 环境 coverage。

`native-transcript-bridge-smoke.sh` 覆盖 integration-only 的 processing-to-native transcript bridge：同样通过公开 `processing-cli` 生成临时 workspace/session artifacts，保留 `session.json`、`transcript.json` 和 `speaker_labels.json`，再用临时 SwiftPM harness 调用 `TranscriptReviewWorkspaceLoader` 与 `TranscriptReviewViewModel` 只读消费同一 workspace，断言 transcript text、segment count 和 transcript-only degradation 可投射到 native read model。它不注册新 product command、不调用真实 capture、不调用真实 external runtime，也不替代 app-bundle XCUITest locator 覆盖。

`full-stack-smoke.sh` 是 manifest 注册入口，顺序运行 import processing local smoke、native_recording-style provider smoke 和 native bridge smoke，并在最终 pass marker 前输出 VS-MA-20 provider/e2e attribution summary 与 VS-MA-23 provider/e2e release-readiness summary。VS-MA-23 summary 只说明 provider/e2e 侧本地命令链、capture-style provider artifact/failure-redaction 链和 native read bridge smoke 通过；发布候选是否可进入人工审查仍以 `./scripts/product-validation-check.py release`、`./scripts/release-preflight.sh` 和验证矩阵中的 `PV-MA-*` 状态为准。`platform/processing-cli/scripts/test.sh` 仍直接调用 processing-owned smoke，避免 processing 组件测试反向依赖 native/Xcode 工具链。

`prepare-smoke-image.sh` 只复用本机已缓存的允许基础镜像并打成本地 smoke tag；它不会在 E2E 执行阶段从外部 registry 拉取镜像。脚本会在有界窗口内反复扫描 target 和允许的 cached base images，以吸收 Docker Desktop image-store 短暂不可用；没有可用缓存时，标准 E2E 应明确失败并提示预加载镜像。
