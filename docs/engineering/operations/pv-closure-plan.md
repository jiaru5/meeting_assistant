# PV Closure Plan

本文件是 `docs/engineering/06-product-validation-matrix.md` 的执行清单，不是新的产品事实源。每个 PV 的当前状态仍以验证矩阵为准；本清单只用于把 release blocker 排成可逐项关闭的工程计划。

## 当前基线

- Baseline: 当前 `develop` 已包含 `VS-MA-14/15` release native capture gate 和前序 provider/full-stack evidence
- 当前工作 diff 已关闭 `PV-MA-001`、`PV-MA-004`、`PV-MA-005` 和 `PV-MA-013`；另补充 `PV-MA-006`/`PV-MA-007`/`PV-MA-008` 的真实 CLI process runner 到 native loader 证据，并把非 XCTest production processing/action command client 默认收紧到 process runner，但这些行仍保持 `partial`。当前目标状态为 `covered=14, partial=9`
- `./scripts/product-validation-check.py release`: fail，剩余原因是 `PV-MA-002`、`PV-MA-003`、`PV-MA-006` 到 `PV-MA-012` 仍非 `covered`
- 2026-07-05 已补 `platform/e2e/release-native-capture-artifact-smoke.sh`，本机 `MA_NATIVE_CAPTURE_ARTIFACT_SMOKE_ATTEMPTS=1 MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS=2 ./platform/e2e/release-native-capture-artifact-smoke.sh` 通过并生成 `release_gate=release-scope-native-capture` report；这让 `VS-MA-14/15` 可按阶段退出口径收口，但 `PV-MA-002/003` 仍保持 `partial`
- 2026-07-05 已补 `platform/e2e/release-capture-processing-hardening-smoke.sh`，本机通过并生成 `release_gate=release-scope-provider-hardening` / `not_release_readiness=true` report；这让 `VS-MA-21` provider-side 异常、重试、并发、脱敏和 checksum preservation 有了结构化 release-scope gate，但 `PV-MA-009` 仍保持 `partial`
- 2026-07-05 已补 `platform/e2e/release-security-supply-chain-smoke.sh`，本机通过并生成 `release_gate=release-scope-security-supply-chain` / `not_release_readiness=true` report；这让 `VS-MA-22` security/supply-chain/provider sidecar evidence 有了结构化 release-scope gate，但不改变 `PV-MA-*` release blocker 状态
- Spec Sync 分类：本计划文档为 `no-product-impact`；每个实现项默认按既有事实源 `spec-covered` 执行，只有改变产品、API、artifact、UI 或 release 范围时才升级为 `spec-change`

## VS-MA-21/22 关闭策略纠偏

当前 `VS-MA-21` 和 `VS-MA-22` 的主要风险不是缺更多 report wrapper，而是阶段关闭目标和真实功能链路没有拆干净。后续除非真实程序路径发生变化并会让既有门禁误读结果，否则不再新增 check/report-only 工作。

`VS-MA-21` 的关闭目标应回到产品功能链路：录制、处理、回查、导出、删除在同一 workspace/session 上可失败、可重试且不覆盖原始媒体。具体关闭动作是：

1. 固定本轮 app-bundle under test 路径和 `MA_NATIVE_APP_DERIVED_DATA_PATH`，恢复或授予同一个 bundle 的 Screen Recording / Screen & System Audio Recording 权限，然后重跑 `platform/e2e/release-native-ui-hardening-smoke.sh`。
2. 证明 launched `.app` 真实 ScreenCaptureKit start/stop 至少稳定产出 `screen_video`；请求音频时若 combined recording 中存在可导出的音轨，则 `mixed_audio` 必须登记为 `available` 并校验 checksum；若没有可导出音轨，必须保留 degraded 原因，并决定是否接受 screen-only native capture 或另开 ADR 讨论辅助音频策略。
3. 真实 same-chain app-bundle smoke 入口已补：`MA_NATIVE_APP_REAL_CAPTURE_SAME_CHAIN_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 要求真实 capture 输出在同一 workspace/session 中进入真实 processing provider，再进入 transcript review、copy/export 和 delete confirmation。2026-07-06 本机运行已进入 test body，但当前阻断在真实 capture `permission_denied`；授权并证明该链路通过前，不应把 provider-side hardening 或受控 recording fixture 当作 `VS-MA-21` 关闭证据。
4. 在真实 same-chain 通过后，再复用既有 provider/native hardening gate 证明 path conflict、retry、checksum preservation、safe display 和 redaction 发生在同一类真实链路上。

`VS-MA-22` 的关闭目标需要先做阶段边界审计。当前 security/supply-chain current gate、release-provider smoke、runtime/model/audio `.local` 边界、hash/license/provenance fail-closed 已经是 `VS-MA-22` 的核心功能性安全证据；签名/公证 Release bundle、DSSE/SLSA provenance、Sigstore signing 和 all-target sidecar portability 更像 `VS-MA-23` release candidate 的输入产物。如果继续把这些真实 release artifacts 作为 `VS-MA-22` 退出前置，就会形成“没进 VS-MA-23 就要求 VS-MA-23 产物”的循环。后续应先把 `07-development-plan.md`、验证矩阵和 release gate 顺序对齐为：

1. `VS-MA-22` 关闭 current-scope security/supply-chain、provider sidecar fail-closed、no-auto-download/no-auto-upload、runtime/model/audio provenance 边界，以及 release artifact guard 的 fail-closed 规则。
2. `VS-MA-23` 产出并校验真实签名/公证 bundle、bundle-bound provenance/signing、all-target sidecar portability 和最终 `release-preflight`。
3. 如果产品 owner 明确要求 `VS-MA-22` 就必须产出真实 release bundle，则应承认 `VS-MA-22` 是 release rehearsal 阶段，并直接安排构建签名/公证和 provenance 产物，而不是继续修改 check 文字。

因此当前最近的 `mixed_audio` extraction、compressed audio normalization 和 same-chain app-bundle entry work 可以作为 `VS-MA-21` 的程序功能子切片保留，但它们本身不 close `VS-MA-21`。下一步必须固定/授权同一个 app bundle 的 TCC 权限后重跑 same-chain 路线，并根据真实 `mixed_audio` 结果决定 screen-only 是否可接受或是否需要音频策略 ADR。

## 执行顺序

| 顺序 | PV | 目标 | 主要阻塞 | 关闭动作 | 证明命令 |
|---|---|---|---|---|---|
| 1 | `PV-MA-004` | 已关闭：导入已有媒体达到 release-scope covered | 原缺口为真实媒体 fixture decode smoke；native UI import 不属于当前 AC/CMD 必需面 | 已在 `platform/e2e` 增加真实 `.wav`/`.mp4` fixture decode smoke，断言格式白名单、artifact type、源文件保护、session/artifact schema 和 `invalid_input` 边界，并纳入 `processing-cli`/full-stack gate | `platform/e2e/smoke-test.sh`; `./scripts/product-validation-check.py release` |
| 2 | `PV-MA-005` | 已关闭：依赖检查达到 release-scope covered | 原缺口为真实 runtime/model smoke 和 provenance sidecar 未形成稳定 release 证据 | 已固定本机 `whisper.cpp` runtime/model/audio fixture 的 hash/license/provenance sidecar，并让 release smoke 断言真实 `check_dependencies --format json` 依赖状态 | `platform/processing-cli/scripts/release-provider-smoke.sh`; `platform/processing-cli/scripts/test.sh`; `./scripts/product-validation-check.py release` |
| 3 | `PV-MA-006` | 标准化处理和输入选择 covered | 已补真实 CLI process runner 写入 workspace 并保持源 checksum；非 XCTest production processing client 默认已走 process runner；剩余缺 release-scope native processing/provider 到 transcript review 的完整门禁 | 用 release-scope app-bundle/full-stack 证明 designed shell processing action 触发真实 provider workspace，并保留源文件不覆盖证据 | `platform/native-app/scripts/test-app-bundle.sh`; `platform/e2e/full-stack-smoke.sh` |
| 4 | `PV-MA-007` | transcript segments covered | 已补 native `ProcessingCommandProcessRunner` 调真实 CLI 后由 native loader 读回 transcript；production 默认 process runner blocker 已移除；剩余缺 release-scope 真实 runtime/provider 证据 | 通过 designed shell 触发真实 processing provider，验证 transcript artifact 被 native read model 消费 | `platform/e2e/native-transcript-bridge-smoke.sh`; app-bundle XCUITest |
| 5 | `PV-MA-008` | speaker label fallback covered | 已补真实 CLI fallback 进入 native degraded state 和 loader；production 默认 process runner blocker 已移除；真实 diarization 质量不作为 MVP 强承诺 | 证明 release-scope speaker fallback 从 provider 输出进入 native transcript/processing 状态，不新增实名识别承诺 | `platform/native-app/scripts/test-app-bundle.sh`; `platform/e2e/full-stack-smoke.sh` |
| 6 | `PV-MA-010` | transcript 回查 covered | production processing client 默认已走 process runner，但仍缺 native 触发 processing 后的 release-scope 回查链路 | 把 processing provider 产物通过 production-scope native action 写入 workspace，再由 transcript review surface 读取 | app-bundle XCUITest; full-stack smoke |
| 7 | `PV-MA-011` | 用户主动复制/导出 covered | 已补 production-injected macOS pasteboard / `NSSavePanel` OS boundary，并把非 XCTest action command client 默认收紧到 `TranscriptActionProcessRunner`；剩余缺真实导出命令、OS boundary 和 release bundle 组合证据 | 用 native action XCUITest/security gate 证明用户主动触发、真实导出文件、pasteboard/save-panel 边界和 no-auto-upload | native action XCUITest; security gate |
| 8 | `PV-MA-012` | 删除确认 covered | 非 XCTest action command client 默认已走 `TranscriptActionProcessRunner`；剩余缺 release-scope 删除确认、workspace 内删除、workspace 外导出保留和失败摘要组合证据 | 增加 production-scope delete bridge release evidence，覆盖确认/取消、workspace 内删除、workspace 外导出保留、失败摘要 | native action XCUITest; processing CLI delete tests |
| 9 | `PV-MA-013` | 已关闭：设计化 shell 达到 covered | 原缺口为 designed shell 完成口径、主操作 command/client wiring 和 Debug/Release fixture 隔离证据没有按行级口径收敛 | 已用 Swift Testing、hosted source-contract smoke、app-bundle `DesignedNativeShellAppBundleTests`/`AppBundleLocatorSmokeTests` 和 bridge smoke 证明 Preflight、recording、artifacts、processing、transcript、copy/export/delete 的 designed shell navigation/status/action wiring；关闭不外推真实 capture、真实 processing provider、真实 OS pasteboard/file picker/delete integration 或其他 PV | `platform/native-app/scripts/test.sh`; `platform/native-app/scripts/test-app-bundle.sh`; `platform/e2e/full-stack-smoke.sh` |
| 10 | `PV-MA-001` | 已关闭：权限和环境预检 fail closed 达到 covered | 原缺口为真实/受控 macOS 权限负向路径没有写入行级完成口径 | 当前标准 `platform/native-app/scripts/test.sh` 已包含 `MacOSNativeCapturePermissionChecker` + `CoreGraphicsScreenRecordingPermissionProbe(preflight: { false })` denied 测试，断言 `permission_denied`、不启动 adapter、不写 session；opt-in app-bundle real capture smoke 的 TCC denied 证据作为补充，不外推录制 PV | `platform/native-app/scripts/test.sh`; `platform/native-app/tests/MeetingAssistantNativeTests/NativeRecordingCommandClientTests.swift` |
| 11 | `PV-MA-002` | 原生录制 covered | release-scope native capture gate 已补；剩余为跨机器 TCC/display 可重复性、独立系统/麦克风音频真实产物、真实 capture 到 transcript/export/delete 的 release-scope 同链路和 release bundle | 保留 `release-native-capture-artifact-smoke.sh` 作为标准 gate；继续补跨机器诊断、音频策略和真实 native-to-processing 成功链路证据 | `platform/e2e/release-native-capture-artifact-smoke.sh`; app-bundle real capture smoke; release full-stack smoke |
| 12 | `PV-MA-003` | 会话和录制产物登记 covered | release-scope stop artifact gate 已补；剩余为独立音频产物策略、真实 capture 后续 processing 成功路径和 release bundle 同链路证据 | 保留四类 artifact available/missing/degraded 的 release-scope report；继续补至少一条真实 native 录制产物进入后续 processing 成功链路 | `platform/e2e/release-native-capture-artifact-smoke.sh`; native capture smoke; session artifact tests |
| 13 | `PV-MA-009` | 文件化流水线重试和原始媒体保护 covered | VS-MA-21 provider hardening release gate 已补；剩余依赖真实 ScreenCaptureKit/native UI 并发、真实 capture -> transcript/export/delete 同链路和 release bundle | 保留 `release-capture-processing-hardening-smoke.sh` 作为 provider-side 标准 gate；在录制、处理、导出、删除全链路关闭后，补真实 native/release-scope 并发、重试和原始媒体保护 release gate | `platform/e2e/release-capture-processing-hardening-smoke.sh`; `./scripts/check.sh`; `./scripts/test-e2e-full-stack.sh`; `./scripts/release-preflight.sh` |

## 合并和验收规则

1. 每次只推进一个 PV 到 `covered`，除非同一验证命令自然覆盖多个 PV 且证据完整。
2. 不能用 Debug-only fixture、opt-in smoke 或局部组件测试直接外推 release covered。
3. 每关闭一个 PV 必须同步更新 `06-product-validation-matrix.md`，并用 `./scripts/product-validation-check.py release` 证明剩余 blocker 数下降。
4. 若发现需要改变公开 command、artifact、event、error code、exit code、UI state 或 release 范围，先按 `spec-change` 更新主责事实源和 ADR。
