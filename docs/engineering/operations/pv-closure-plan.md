# PV Closure Plan

本文件是 `docs/engineering/06-product-validation-matrix.md` 的执行清单，不是新的产品事实源。每个 PV 的当前状态仍以验证矩阵为准；本清单只用于把 release blocker 排成可逐项关闭的工程计划。

## 当前基线

- Baseline: 当前 `develop` 已包含 `VS-MA-14/15` release native capture gate 和前序 provider/full-stack evidence
- 当前工作 diff 已关闭 `PV-MA-001`、`PV-MA-004`、`PV-MA-005` 和 `PV-MA-013`；另补充 `PV-MA-006`/`PV-MA-007`/`PV-MA-008` 的真实 CLI process runner 到 native loader 证据，并把非 XCTest production processing/action command client 默认收紧到 process runner，但这些行仍保持 `partial`。当前目标状态为 `covered=14, partial=9`
- `./scripts/product-validation-check.py release`: fail，剩余原因是 `PV-MA-002`、`PV-MA-003`、`PV-MA-006` 到 `PV-MA-012` 仍非 `covered`
- 2026-07-05 已补 `platform/e2e/release-native-capture-artifact-smoke.sh`，本机 `MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_ATTEMPTS=1 MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS=2 ./platform/e2e/release-native-capture-artifact-smoke.sh` 通过并生成 `release_gate=release-scope-native-capture` report；这让 `VS-MA-14/15` 可按阶段退出口径收口，但 `PV-MA-002/003` 仍保持 `partial`
- 2026-07-05 已补 `platform/e2e/release-capture-processing-hardening-smoke.sh`，本机通过并生成 `release_gate=release-scope-provider-hardening` / `not_release_readiness=true` report；这让 `VS-MA-21` provider-side 异常、重试、并发、脱敏和 checksum preservation 有了结构化 release-scope gate，但 `PV-MA-009` 仍保持 `partial`
- 2026-07-05 已补 `platform/e2e/release-security-supply-chain-smoke.sh`，本机通过并生成 `release_gate=release-scope-security-supply-chain` / `not_release_readiness=true` report；这让 `VS-MA-22` security/supply-chain/provider sidecar evidence 有了结构化 release-scope gate，但不改变 `PV-MA-*` release blocker 状态
- 2026-07-06 本机授权当前 DerivedData app bundle 后，`MA_NATIVE_APP_XCODE_DESTINATION='platform=macOS,arch=arm64' MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 通过，证明真实 app-bundle ScreenCaptureKit `mixed_audio` 进入 processing/transcript/action/delete 同链路；这让 `VS-MA-21` 可按阶段退出口径收口，但 `PV-MA-*` release blocker 仍需按矩阵逐项关闭
- 2026-07-06 本机授权当前 DerivedData app bundle 后，`MA_NATIVE_APP_XCODE_DESTINATION='platform=macOS,arch=arm64' MA_NATIVE_APP_REUSE_XCTESTRUN=1 ./platform/e2e/release-native-ui-hardening-smoke.sh` 通过并生成 `release_gate=release-scope-native-ui-hardening` report；这关闭“本机 release native UI hardening wrapper 尚未通过”的缺口，但跨机器 TCC/display/UI Automation 可重复性和签名/公证 release bundle 仍留在 `VS-MA-23`/发布范围 PV 中
- 2026-07-06 本机执行 `MA_NATIVE_APP_XCODE_DESTINATION='platform=macOS,arch=arm64' MA_NATIVE_APP_REAL_ACTION_OS_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 通过，证明 process-backed transcript action 已穿过 system `NSPasteboard`、`NSSavePanel`、Markdown export 和 delete confirmation；这关闭“真实 OS action 仍只有 deterministic fixture”的缺口，但 `PV-MA-011/012` 仍需 release bundle、跨机器重复和最终 release-preflight 组合证据
- Spec Sync 分类：本计划文档为 `no-product-impact`；每个实现项默认按既有事实源 `spec-covered` 执行，只有改变产品、API、artifact、UI 或 release 范围时才升级为 `spec-change`

## VS-MA-21/22 关闭策略纠偏

当前 `VS-MA-21` 和 `VS-MA-22` 的主要风险不是缺更多 report wrapper，而是阶段关闭目标和真实功能链路没有拆干净。后续除非真实程序路径发生变化并会让既有门禁误读结果，否则不再新增 check/report-only 工作。

`VS-MA-21` 的关闭目标应回到产品功能链路：录制、处理、回查、导出、删除在同一 workspace/session 上可失败、可重试且不覆盖原始媒体。本轮关闭动作已完成：

1. 固定本轮 app-bundle under test 路径和 `MA_NATIVE_APP_DERIVED_DATA_PATH`，清理旧 worktree 的同名 `MeetingAssistantNative` TCC entry，并把当前 DerivedData app bundle 加回 Screen Recording / Screen & System Audio Recording 授权。
2. launched `.app` 真实 ScreenCaptureKit start/stop 已稳定产出 `screen_video`；请求 system audio 时从 combined recording 中导出 `mixed_audio` 并校验 checksum，`system_audio` 继续以 degraded 原因呈现，`microphone_audio` 未请求时保持 missing。
3. `MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 已通过：真实 capture 输出在同一 workspace/session 中进入真实 processing provider，再进入 transcript review、copy/export 和 delete confirmation，并验证原始 `mixed_audio` checksum preservation 与外部导出保留。
4. 既有 provider/native hardening gate 已覆盖 path conflict、retry、checksum preservation、safe display 和 redaction；这些证据与真实 same-chain 共同构成 `VS-MA-21` 阶段退出依据。

`VS-MA-22` 的关闭目标已完成阶段边界审计。当前 security/supply-chain current gate、release-provider smoke、runtime/model/audio `.local` 边界、hash/license/provenance fail-closed 已经是 `VS-MA-22` 的核心功能性安全证据；签名/公证 Release bundle、DSSE/SLSA provenance、Sigstore signing 和 all-target sidecar portability 是 `VS-MA-23` release candidate 的输入产物。如果继续把这些真实 release artifacts 作为 `VS-MA-22` 退出前置，就会形成“没进 VS-MA-23 就要求 VS-MA-23 产物”的循环。`07-development-plan.md`、验证矩阵和 release gate 顺序已对齐为：

1. `VS-MA-22` 已关闭 current-scope security/supply-chain、provider sidecar fail-closed、no-auto-download/no-auto-upload、runtime/model/audio provenance 边界，以及 release artifact guard 的 fail-closed 规则。
2. `VS-MA-23` 产出并校验真实签名/公证 bundle、bundle-bound provenance/signing、all-target sidecar portability 和最终 `release-preflight`。
3. 如果产品 owner 明确要求 `VS-MA-22` 就必须产出真实 release bundle，则应承认 `VS-MA-22` 是 release rehearsal 阶段，并直接安排构建签名/公证和 provenance 产物，而不是继续修改 check 文字。

因此当前最近的 `mixed_audio` extraction、compressed audio normalization、same-chain app-bundle entry 和 TCC 修复工作已经把 `VS-MA-21` 推到阶段退出口径。下一步不应继续围绕 `VS-MA-21/22` 增加 report-only 工作，而应进入 `VS-MA-23` release candidate 输入：逐项关闭仍为 `partial` 的发布范围 PV，产出真实 release bundle、provenance/signing/sidecar portability 证据，并让 `product-validation-check.py release` / `release-preflight.sh` 从 fail-closed 变成可通过。

## 执行顺序

| 顺序 | PV | 目标 | 主要阻塞 | 关闭动作 | 证明命令 |
|---|---|---|---|---|---|
| 1 | `PV-MA-004` | 已关闭：导入已有媒体达到 release-scope covered | 原缺口为真实媒体 fixture decode smoke；native UI import 不属于当前 AC/CMD 必需面 | 已在 `platform/e2e` 增加真实 `.wav`/`.mp4` fixture decode smoke，断言格式白名单、artifact type、源文件保护、session/artifact schema 和 `invalid_input` 边界，并纳入 `processing-cli`/full-stack gate | `platform/e2e/smoke-test.sh`; `./scripts/product-validation-check.py release` |
| 2 | `PV-MA-005` | 已关闭：依赖检查达到 release-scope covered | 原缺口为真实 runtime/model smoke 和 provenance sidecar 未形成稳定 release 证据 | 已固定本机 `whisper.cpp` runtime/model/audio fixture 的 hash/license/provenance sidecar，并让 release smoke 断言真实 `check_dependencies --format json` 依赖状态 | `platform/processing-cli/scripts/release-provider-smoke.sh`; `platform/processing-cli/scripts/test.sh`; `./scripts/product-validation-check.py release` |
| 3 | `PV-MA-006` | 标准化处理和输入选择 covered | 已补真实 CLI process runner 写入 workspace 并保持源 checksum；非 XCTest production processing client 默认已走 process runner；app-bundle same-chain 已证明真实 capture `mixed_audio.m4a` 可进入 normalization；剩余缺 release bundle / release-preflight 组合证据 | 用 release-scope app-bundle/full-stack 和 release candidate gate 证明 designed shell processing action、真实 provider workspace 和源文件不覆盖证据可进入发布候选 | `platform/native-app/scripts/test-app-bundle.sh`; `platform/e2e/full-stack-smoke.sh`; `./scripts/release-preflight.sh` |
| 4 | `PV-MA-007` | transcript segments covered | 已补 native `ProcessingCommandProcessRunner` 调真实 CLI 后由 native loader 读回 transcript；production 默认 process runner blocker 已移除；app-bundle same-chain 已证明真实 capture 后的 transcript artifact 被 native read model 消费；剩余缺 release bundle / release-preflight 组合证据 | 通过 release candidate gate 绑定真实 provider transcript artifact、native read model 和发布包证据 | `platform/e2e/native-transcript-bridge-smoke.sh`; app-bundle XCUITest; `./scripts/release-preflight.sh` |
| 5 | `PV-MA-008` | speaker label fallback covered | 已补真实 CLI fallback 进入 native degraded state 和 loader；production 默认 process runner blocker 已移除；真实 diarization 质量不作为 MVP 强承诺 | 证明 release-scope speaker fallback 从 provider 输出进入 native transcript/processing 状态，不新增实名识别承诺 | `platform/native-app/scripts/test-app-bundle.sh`; `platform/e2e/full-stack-smoke.sh` |
| 6 | `PV-MA-010` | transcript 回查 covered | production processing client 默认已走 process runner，但仍缺 native 触发 processing 后的 release-scope 回查链路 | 把 processing provider 产物通过 production-scope native action 写入 workspace，再由 transcript review surface 读取 | app-bundle XCUITest; full-stack smoke |
| 7 | `PV-MA-011` | 用户主动复制/导出 covered | 已补 production-injected macOS pasteboard / `NSSavePanel` OS boundary、非 XCTest action command client 默认 process runner，以及 real action OS app-bundle smoke；剩余缺签名/公证 release bundle、跨机器 action OS/TCC/UI Automation 重复和最终 release-preflight 组合证据 | 在 VS-MA-23 release rehearsal 中绑定真实 release bundle、跨机器 action OS smoke 或等价 release-scope 重复证据，并确认 no-auto-upload/no-external-API 边界不退化 | real action OS app-bundle XCUITest; release bundle gate; release-preflight |
| 8 | `PV-MA-012` | 删除确认 covered | 已补 process-backed delete confirmation、workspace 内 session root 删除、workspace 外导出保留和 delete event 不泄漏 transcript 的 real action OS app-bundle smoke；剩余缺签名/公证 release bundle、跨机器 action OS/TCC/UI Automation 重复和最终 release-preflight 组合证据 | 在 VS-MA-23 release rehearsal 中绑定真实 release bundle、跨机器真实 action 链路或等价 release-scope 重复证据，并保留确认/取消、失败摘要和外部导出保留断言 | real action OS app-bundle XCUITest; processing CLI delete tests; release-preflight |
| 9 | `PV-MA-013` | 已关闭：设计化 shell 达到 covered | 原缺口为 designed shell 完成口径、主操作 command/client wiring 和 Debug/Release fixture 隔离证据没有按行级口径收敛 | 已用 Swift Testing、hosted source-contract smoke、app-bundle `DesignedNativeShellAppBundleTests`/`AppBundleLocatorSmokeTests` 和 bridge smoke 证明 Preflight、recording、artifacts、processing、transcript、copy/export/delete 的 designed shell navigation/status/action wiring；关闭不外推真实 capture、真实 processing provider、真实 OS pasteboard/file picker/delete integration 或其他 PV | `platform/native-app/scripts/test.sh`; `platform/native-app/scripts/test-app-bundle.sh`; `platform/e2e/full-stack-smoke.sh` |
| 10 | `PV-MA-001` | 已关闭：权限和环境预检 fail closed 达到 covered | 原缺口为真实/受控 macOS 权限负向路径没有写入行级完成口径 | 当前标准 `platform/native-app/scripts/test.sh` 已包含 `MacOSNativeCapturePermissionChecker` + `CoreGraphicsScreenRecordingPermissionProbe(preflight: { false })` denied 测试，断言 `permission_denied`、不启动 adapter、不写 session；opt-in app-bundle real capture smoke 的 TCC denied 证据作为补充，不外推录制 PV | `platform/native-app/scripts/test.sh`; `platform/native-app/tests/MeetingAssistantNativeTests/NativeRecordingCommandClientTests.swift` |
| 11 | `PV-MA-002` | 原生录制 covered | release-scope native capture gate 和 app-bundle same-chain 已补；剩余为跨机器 TCC/display 可重复性、独立系统/麦克风音频真实产物策略和 release bundle 组合证据 | 保留 `release-native-capture-artifact-smoke.sh` 作为标准 gate；继续补跨机器诊断、音频策略和 release candidate bundle 证据 | `platform/e2e/release-native-capture-artifact-smoke.sh`; app-bundle real capture smoke; release full-stack smoke |
| 12 | `PV-MA-003` | 会话和录制产物登记 covered | release-scope stop artifact gate 和真实 capture 后续 processing 成功路径已补；剩余为独立音频产物策略、跨机器可重复性和 release bundle 同链路证据 | 保留四类 artifact available/missing/degraded 的 release-scope report；在 release candidate 中绑定真实 native 录制产物、后续 processing 和发布包证据 | `platform/e2e/release-native-capture-artifact-smoke.sh`; native capture smoke; session artifact tests; `./scripts/release-preflight.sh` |
| 13 | `PV-MA-009` | 文件化流水线重试和原始媒体保护 covered | VS-MA-21 provider hardening release gate、release native UI hardening gate 和 app-bundle same-chain 已补；剩余依赖跨机器 TCC/display/UI Automation 可重复性和 release bundle | 保留 `release-capture-processing-hardening-smoke.sh` 与 `release-native-ui-hardening-smoke.sh` 作为标准 release-scope gate；在 release candidate 中补 all-target repeatability、原始媒体保护和 bundle 证据 | `platform/e2e/release-capture-processing-hardening-smoke.sh`; `platform/e2e/release-native-ui-hardening-smoke.sh`; `./scripts/check.sh`; `./scripts/test-e2e-full-stack.sh`; `./scripts/release-preflight.sh` |

## 合并和验收规则

1. 每次只推进一个 PV 到 `covered`，除非同一验证命令自然覆盖多个 PV 且证据完整。
2. 不能用 Debug-only fixture、opt-in smoke 或局部组件测试直接外推 release covered。
3. 每关闭一个 PV 必须同步更新 `06-product-validation-matrix.md`，并用 `./scripts/product-validation-check.py release` 证明剩余 blocker 数下降。
4. 若发现需要改变公开 command、artifact、event、error code、exit code、UI state 或 release 范围，先按 `spec-change` 更新主责事实源和 ADR。
