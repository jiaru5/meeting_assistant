# 7. 开发计划

本文件定义 starter 落地计划、阶段门禁和演进路线。它是工程执行计划，不是产品事实源。

## 文件边界

1. 产品模型、字段、枚举、权限、API、事件、数据库语义、页面行为、验收标准和 ADR 以 `docs/product-spec/` 的主责分卷为准。
2. 工程结构、命令、测试策略、审查门禁、验证矩阵和服务标准以 `docs/engineering/` 的主责分卷为准。
3. 本文件只定义如何分阶段完成实现和交付门禁。

## 开发节奏

每个产品纵切按同一个闭环推进：

1. 确认目标 `CAP-MA-*`、`AC-MA-*` 和 `PV-MA-*` 已存在且语义清楚。
2. 如果事实源缺失或冲突，先按 `spec-change` 更新主责分卷、ADR 或 open decisions，再实现。
3. 如果事实源已覆盖，按 `spec-covered` 做最小纵切实现，并同步补测试。
4. 更新 `docs/engineering/06-product-validation-matrix.md` 的状态和证据；未完整覆盖时只能推进到 `partial` 或 `manual-evidence`，不能报 `covered`。
5. 运行该纵切的组件测试和标准门禁；非平凡纵切交付前至少运行 `./scripts/project-manifest-check.sh current`、`./scripts/agent-workflow-check.sh` 和 `./scripts/review-report.sh`。
6. 标准门禁通过、残余风险写清后，再进入下一个纵切。

默认每个 MVP 产品纵切的 Spec Sync 分类是 `spec-covered`。只有发现需要新增或改变产品能力、命令语义、artifact contract、权限、数据保留、外部依赖来源、录制主路径或 UI 旅程时，才升级为 `spec-change`。

## 测试可确定性缺口 / Testability Gate

`TDG-MA-*` 是工程 testability gate，不是新的产品能力或 open decision。它用于防止在命令 schema、artifact schema、fixture、locator 或证据入口不足时开始业务实现，或把 `PV-MA-*` 虚报为 `covered`。

TDG 按具体命令、artifact、UI 状态或纵切逐项关闭；同一个 TDG 可以对某个已实现命令关闭，同时对后续命令保持未关闭。当前关闭状态以 `06-product-validation-matrix.md` 的对应 `PV-MA-*` 行为准。

执行规则：

1. 每个 `VS-MA-*` 开始前，先检查下表中映射到该纵切的 `TDG-MA-*`；缺口未关闭时，只能先做规范、测试基础设施、fixture、fake adapter 或 spike。
2. 每个 `VS-MA-*` 退出时，验证矩阵必须写明相关 `TDG-MA-*` 是已关闭、仍阻塞，还是本纵切不适用。
3. 关闭 `TDG-MA-*` 必须有仓库内测试文件或标准命令证据，不能只依赖聊天说明、截图或“未来测试”。
4. `TDG-MA-*` 未关闭时，对应 `PV-MA-*` 最高只能是 `planned`、`partial` 或 `manual-evidence`；只有纳入标准门禁的自动化覆盖完整范围后才能标 `covered`。

| TDG ID | 缺口 | 影响 VS | 影响 PV | 主责事实源 | 关闭条件 |
|---|---|---|---|---|---|
| TDG-MA-001 | Command schema、错误响应、unknown field fail-fast 和 CLI exit code 断言不足 | `VS-MA-01`, `VS-MA-03`, `VS-MA-05`, `VS-MA-06`, `VS-MA-07`, `VS-MA-09`, `VS-MA-10`, `VS-MA-11`, `VS-MA-18`, `VS-MA-19` | `PV-MA-001`, `PV-MA-004`, `PV-MA-005`, `PV-MA-007`, `PV-MA-008`, `PV-MA-011`, `PV-MA-012` | `docs/product-spec/06-api-contracts.md`, `docs/engineering/03-test-strategy.md` | 每个相关 `CMD-MA-*` 有成功/失败 JSON schema 断言、unknown field 和非法 enum 负向测试、exit code 测试，并由组件 test 命令或标准脚本调用 |
| TDG-MA-002 | Session/artifact/transcript/speaker labels/delete summary schema 和路径边界不足 | `VS-MA-02`-`VS-MA-11`, `VS-MA-15`, `VS-MA-19`, `VS-MA-21` | `PV-MA-003`, `PV-MA-004`, `PV-MA-006`, `PV-MA-007`, `PV-MA-008`, `PV-MA-009`, `PV-MA-011`, `PV-MA-012` | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md` | 文件契约测试断言最小字段、checksum、状态、降级原因、排序、workspace 内路径、symlink/path traversal 负向用例和删除摘要 |
| TDG-MA-003 | 确定性 fixture、fake adapter 和临时 workspace 不足 | `VS-MA-03`-`VS-MA-11`, `VS-MA-20` | `PV-MA-004`, `PV-MA-006`, `PV-MA-007`, `PV-MA-008`, `PV-MA-009`, `PV-MA-011`, `PV-MA-012` | `docs/product-spec/07-data-and-events.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/engineering/03-test-strategy.md` | 仓库内有小型媒体 fixture、fake transcription/speaker adapters、固定临时 workspace/clock 策略和不依赖真实本机数据的 smoke 入口 |
| TDG-MA-004 | SwiftUI 状态、accessibility locator 和 native UI 自动化不足 | `VS-MA-12`, `VS-MA-13`, `VS-MA-16`-`VS-MA-19`, `VS-MA-19A` | `PV-MA-001`, `PV-MA-002`, `PV-MA-007`, `PV-MA-010`, `PV-MA-011`, `PV-MA-012`, `PV-MA-013` | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/12-ui-ux-design.md`, `docs/engineering/03-test-strategy.md` | Swift Testing 覆盖 view model 状态，XCUITest 覆盖关键可见状态和 accessibility identifier；权限/依赖缺失、失败、降级、确认/取消均可查询 |
| TDG-MA-005 | 原生 capture spike、native smoke 和禁止静默辅助 capture 切换证据不足 | `VS-MA-13`-`VS-MA-15`, `VS-MA-20` | `PV-MA-002`, `PV-MA-003`, `PV-MA-006`, `PV-MA-009` | `docs/product-spec/08-implementation-guidance.md` | spike 记录 API、权限、系统音频、artifact 和失败模式；fake adapter 与受控 native smoke 均有证据；未完成 spec-change/ADR 时测试能证明不会切到 OBS/BlackHole/FFmpeg 辅助路径 |
| TDG-MA-006 | 负向安全边界不足：权限、依赖、路径、delete、no-auto-upload/no-auto-download | `VS-MA-01`, `VS-MA-03`, `VS-MA-06`, `VS-MA-09`, `VS-MA-10`, `VS-MA-18`, `VS-MA-19`, `VS-MA-21`, `VS-MA-22` | `PV-MA-001`, `PV-MA-004`, `PV-MA-005`, `PV-MA-007`, `PV-MA-009`, `PV-MA-011`, `PV-MA-012` | `docs/product-spec/06-api-contracts.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/13-security-and-compliance.md`, `docs/engineering/10-security-and-supply-chain.md` | 自动化测试覆盖 `permission_denied`、`dependency_missing`、`invalid_input`、`artifact_missing`、`path_conflict`、symlink 逃逸、workspace 外导出保留、无自动上传和无自动下载 |
| TDG-MA-007 | 验证矩阵证据入口和关闭条件不足 | `VS-MA-00`, `VS-MA-01`-`VS-MA-23`, `VS-MA-19A` | 所有 `PV-MA-*` | `docs/engineering/03-test-strategy.md`, `docs/engineering/04-review-and-ci-gates.md`, `docs/engineering/06-product-validation-matrix.md` | 每个 planned/partial/manual-evidence 行都有目标测试文件或命令、当前证据、阻塞 `TDG-MA-*`、关闭条件和标准门禁入口；review report 能引用实际执行证据 |
| TDG-MA-008 | 设计化 native shell、视觉状态回归、主操作触发和 Debug/Release fixture 隔离证据不足 | `VS-MA-19A`, `VS-MA-20`, `VS-MA-23` | `PV-MA-013`; 同时影响 `PV-MA-001`, `PV-MA-002`, `PV-MA-006`-`PV-MA-012` 的 UI 入口证据 | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/12-ui-ux-design.md`, `docs/engineering/03-test-strategy.md`, `docs/engineering/06-product-validation-matrix.md` | app-bundle XCUITest 和 Swift Testing 覆盖 Preflight、recording、artifacts、processing、transcript、export/delete 的 designed shell navigation、状态层级、主操作触发、locator、failure/degraded 状态和 Debug/Release hook 隔离；可选截图证据只能补充，不能替代自动化断言 |

## 阶段化契约交付策略

Phase 2 以后按“大阶段管理、纵切交付、契约验收”的方式推进。大阶段只用于组织上下文、模块边界和验收门槛；实际交付仍以 `VS-MA-*` 纵切为最小单元，避免一次性跨越 `native-app`、`processing-cli`、真实 runtime 和 E2E。

每个阶段必须先明确本阶段要稳定的边界契约，再实现功能。边界契约包括：

1. Command contract：`06-api-contracts.md` 定义的命令输入、输出、错误码和 fail-fast 语义。
2. Artifact contract：`02-domain-model.md` 和 `07-data-and-events.md` 定义的 `session.json`、artifact registry、checksum、状态、路径和保留语义。
3. Adapter contract：capture、media processing、transcription 和 speaker labeling 的可替换端口、fake/local 实现、失败与降级语义。
4. UI state contract：`04-user-journeys-and-ui.md` 和 `12-ui-ux-design.md` 定义的权限、依赖、录制、处理、回查、导出和删除状态。
5. Evidence contract：`06-product-validation-matrix.md` 中对应 `PV-MA-*` 的状态、证据入口和剩余缺口。

阶段关闭时必须满足以下自验证目标：

1. 本阶段涉及的 `CAP-MA-*`、`AC-MA-*` 和 `PV-MA-*` 均已定位，并且验证矩阵状态与证据一致。
2. 每个新增或修改的边界契约都有自动化契约测试；如果只能使用 fake 或 manual evidence，验证矩阵必须保持 `partial` 或 `manual-evidence`。
3. 每个产品命令都有稳定 JSON 响应、错误码和负向测试；不得用脚本跳过或 UI 隐藏代替契约测试。
4. 本阶段至少运行相关组件测试、`./scripts/project-manifest-check.sh current`、`./scripts/agent-workflow-check.sh` 和 `./scripts/review-report.sh`；阶段收口或跨模块集成时运行 `./scripts/phase-preflight.sh`，该入口会同时验证当前阶段矩阵状态、`./scripts/check.sh`、full-stack E2E 和 evidence review。
5. 涉及 native UI、处理链路或跨组件集成时，补 Swift Testing、XCUITest 或 `platform/e2e` smoke；如果本地 smoke image 不可用，交付说明必须记录未运行原因和恢复条件。
6. 不因阶段完成而自动把所有相关 `PV-MA-*` 推进到 `covered`；只有被标准门禁长期调用的测试覆盖完整范围时才能标为 `covered`。

| 阶段 | 覆盖纵切 | 稳定边界 | 主要代码表面 | 自动化验证目标 | 验证矩阵目标 |
|---|---|---|---|---|---|
| P2-A Contract Kernel | `VS-MA-00`-`VS-MA-02` | dependency check command、workspace/artifact contract、错误码、checksum、lock、路径边界 | `platform/processing-cli/src/meeting_assistant_cli/dependency_check.py`、`workspace_contract.py`、组件脚本 | Processing CLI 单元/契约测试；缺失依赖 `ok=false`；artifact registry、append-only、checksum drift、lock 冲突和路径越界测试；标准门禁生成证据 | `PV-MA-005` 在关闭 `TDG-MA-001` 的 exact exit code/schema 断言后恢复到 `covered`；`PV-MA-001`、`PV-MA-003`、`PV-MA-009` 按实际覆盖到 `partial` 或更高 |
| P2-B Processing Command Contracts | `VS-MA-03`-`VS-MA-10` | `import_media`、audio source selection、`generate_transcript` fake adapter、speaker fallback、export、delete command contracts | `processing-cli` commands、adapters、contracts、tests | 每条 `CMD-MA-*` 的 JSON 响应、错误码、路径边界、artifact 缺失、格式不支持、失败不覆盖原始媒体、no-auto-upload/no-auto-download 测试 | `PV-MA-004`、`PV-MA-006`、`PV-MA-007`、`PV-MA-008`、`PV-MA-011`、`PV-MA-012` 至少达到 `partial`；fake 或本地 adapter 完整接入标准门禁后才能推进 |
| P2-C Processing Local E2E | `VS-MA-11` | import -> normalize -> transcript fake -> speaker fallback -> export -> delete 的文件化流水线 | `platform/processing-cli`、`platform/e2e` | 临时 workspace fixture；端到端 smoke；每步保留可解释错误和 artifact 证据；`./scripts/check.sh` 和可运行时的 `./scripts/test-e2e-full-stack.sh` | processing 侧相关 `PV-MA-*` 证据集中更新；仍未接真实 runtime 或 native UI 的行保持 `partial` |
| P2-D Native Control Plane | `VS-MA-12`-`VS-MA-13` | native permission/dependency state、recording state machine、fake capture adapter、processing bridge | `platform/native-app/Sources`、`Tests`、`UITests` | Swift Testing 覆盖 view model 和状态转换；XCUITest 覆盖权限/依赖缺失、开始、录制中、停止和失败状态；不实现真实 capture 前使用 fake adapter | `PV-MA-001`、`PV-MA-002` 获得 native 可见阻断和状态证据；真实 capture 前不报完整 `covered` |
| P2-E Native Capture Integration | `VS-MA-14`-`VS-MA-16` | native capture adapter、stop recording artifact registration、native-to-processing invocation | `native-app` capture/helper、`processing-cli` artifact contract、E2E fixture | 受控 native recording smoke；权限缺失、录制中断、保存失败、重复 stop、缺失音轨降级和 checksum 测试；必要时 manual evidence 记录平台限制 | `PV-MA-002`、`PV-MA-003`、`PV-MA-006`-`PV-MA-009` 按真实 capture 和处理联动证据推进 |
| P2-F Native Review, Export and Delete | `VS-MA-17`-`VS-MA-19` | transcript review UI、copy/export UI、delete confirmation UI、CLI bridge | `native-app` review/export/delete surfaces、`processing-cli` export/delete commands | Swift Testing/XCUITest 覆盖时间戳、文本、匿名 label、降级说明、用户主动导出、确认/取消删除和失败摘要；安全测试确认无 API key 和无自动上传路径 | `PV-MA-010`、`PV-MA-011`、`PV-MA-012` 同时获得命令层和 UI 层证据 |
| P2-F2 Native Designed App Shell | `VS-MA-19A` | designed native shell、集成导航、视觉状态层级、主操作触发和 Debug/Release fixture 隔离 | `platform/native-app/Sources`、`Tests`、`UITests`、app-bundle XCUITest | Swift Testing/XCUITest 覆盖 Preflight、recording、artifacts、processing、transcript、export/delete shell；主操作通过既有 command/helper/adapter client；截图证据只作为辅助 | `PV-MA-013` 获得设计化 shell 证据；真实 capture、真实 processing、真实 OS 集成和 release bundle 仍按各自 `PV-MA-*` 保持诚实状态 |
| P2-G MVP Smoke and Candidate Gates | `VS-MA-20`-`VS-MA-23` | 本地 MVP smoke、异常/重试硬化、安全供应链、release candidate | `platform/e2e`、组件 scripts、`.harness/evidence`、生产就绪工件 | `./scripts/phase-preflight.sh`、`./scripts/security-check.sh`、`./scripts/supply-chain-check.sh current`、release candidate 时再运行 `./scripts/release-preflight.sh`；失败路径和未运行项必须可解释 | 阶段收口可保留有阻塞缺口和关闭条件的 `partial/planned`；进入 `VS-MA-23` 发布候选时，发布范围内 `PV-MA-*` 必须为 `covered` |

模块开发顺序应遵守依赖方向：`native-app` 只调用 command/helper 边界，不直接解释 processing artifact 之外的内部状态；`processing-cli` 只通过 workspace files 和 command responses 暴露结果，不反向依赖 native UI；真实 runtime adapter 必须服从 fake adapter 已验证的契约。

并行 worktree 的推荐拆分：

1. `contract-kernel`：只关闭 `TDG-MA-001`、`TDG-MA-002` 和相关 fixture/fake 测试，提供命令响应和 artifact contract 的可执行断言。
2. `processing-provider`：实现 `processing-cli` 的命令 provider、adapter 和文件化产物，只通过 `CMD-MA-*` 响应和 workspace artifact 暴露结果。
3. `native-consumer`：实现 `native-app` 调用方、UI state 和 CLI/helper bridge，只依赖冻结命令响应和 artifact read model。
4. `runtime-adapter`：实现或接入已确认的真实 transcription runtime，但必须保持 fake adapter 已验证的 transcript contract。
5. `integration-e2e`：在上述分支合并后验证 import/capture -> processing -> transcript -> export/delete 的集成链路，并把证据回填验证矩阵。

这些 worktree 可以并行开发内部实现和边缘测试，但不得并行修改同一 frozen source。需要改变命令字段、artifact 语义、UI state 或 validation 关闭条件时，先回到 `05-agent-operating-model.md` 的 contract-change 通道。

## MVP 纵切计划

下表是面向当前 Phase 1 MVP 的最小开发粒度。每一行都应能独立形成“实现 + 测试 + 验证矩阵证据 + 门禁”的交付单元。

进入每个纵切前必须检查上方 `TDG-MA-*` 映射。若相关 TDG 未关闭，该纵切的第一交付物应是关闭 testability gate；退出口径必须在验证矩阵中记录 TDG 状态和下一步关闭条件。

## 当前 VS-MA 状态盘点

本表是工程执行状态索引，不是产品完成度事实源。产品能力是否完成仍以 `06-product-validation-matrix.md` 的 `PV-MA-*` 状态和 `product-validation-check.py release` 为准。状态含义：

1. `已达退出口径`：该纵切的当前开发退出条件已有仓库内证据或标准门禁支撑；后续 release 证据仍可能由更晚纵切补齐。
2. `partial evidence`：已有实现、fixture、smoke 或组件级证据，但该纵切要求的 release-scope 证据还未闭合。
3. `未进入 release-scope`：前置纵切或发布范围 `PV-MA-*` 尚未关闭，不能作为 release candidate 输入。
4. `MVP 外`：当前 Phase 1 MVP 不执行，除非用户先触发 spec-change。

| 纵切 | 当前状态 | 证据口径 | 下一步 |
|---|---|---|---|
| `VS-MA-00` | 已达退出口径 | Project 模式、清单、文档和 workflow 门禁已建立 | 作为后续纵切的基线校验保留 |
| `VS-MA-01` | 已达退出口径 | `check_dependencies`、依赖 fail-closed 和 no-auto-download 已有标准证据 | 只在依赖策略变更时回归 |
| `VS-MA-02` | 已达退出口径 | workspace、session、artifact registry、lock、checksum 和路径边界已有可复用契约证据 | 后续真实 native capture 只补录制产物维度，不重开存储语义 |
| `VS-MA-03` | 已达退出口径 | `import_media` 格式白名单、artifact 映射和源文件保护已进入组件/E2E 证据 | 作为 processing smoke 输入路径保留 |
| `VS-MA-04` | 已达退出口径 | 标准化音频和原始媒体保护已有 processing 侧证据 | release-scope 仍要由 native-to-processing 链路复用证明 |
| `VS-MA-05` | 已达退出口径 | transcript command、adapter 契约、失败保留原始媒体已有测试证据 | release-scope 仍要由真实 native 触发 processing 证明 |
| `VS-MA-06` | partial evidence | `whisper.cpp` mixed-language smoke 和 runtime/model fail-closed 已有组件证据 | 补 release provider 的 model hash、license、provenance 和 native 触发链路 |
| `VS-MA-07` | 已达退出口径 | transcript-only fallback、匿名 label 和不声明真实身份已有契约证据 | 真实 diarization 质量不是 MVP 强承诺；release-scope 需证明 native 链路能消费结果 |
| `VS-MA-08` | partial evidence | fallback 路径已支撑 MVP；可选 speaker adapter 仍只有有限证据 | 若引入具体 speaker runtime，先确认是否需要 spec-change |
| `VS-MA-09` | 已达退出口径 | `export_transcript` 命令层导出、路径冲突和 no-auto-upload 已有证据 | release-scope OS/UI 集成在 `VS-MA-18` 收口 |
| `VS-MA-10` | 已达退出口径 | `delete_session` 命令层确认、路径边界、外部导出保留已有证据 | release-scope OS/UI 集成在 `VS-MA-19` 收口 |
| `VS-MA-11` | 已达退出口径 | import -> normalize -> transcript -> speaker fallback -> export -> delete processing smoke 已建立 | 作为后续 full-stack 和 release smoke 的 provider 侧基础 |
| `VS-MA-12` | 已达退出口径 | native 权限/依赖状态、blocked readiness 和 app-bundle locator 已有证据 | 只在权限或 dependency contract 变化时回归 |
| `VS-MA-13` | 已达退出口径 | fake capture adapter、recording state UI 和 start/stop 状态机已可测 | 不外推为真实 capture；真实录制在 `VS-MA-14/15` 收口 |
| `VS-MA-14` | partial evidence | ScreenCaptureKit adapter、opt-in native capture smoke 和 app-bundle real capture smoke 已有单机/显式 opt-in 证据；脚本级真实 capture smoke 已验证 `screen_video` 非空和四类 artifact presence；opt-in E2E 已证明 processing workspace contract 可读取真实 native session；`full-stack-smoke.sh` 已可显式 opt-in 纳入真实 capture artifact stage，display wake guard + ScreenCaptureKit start/finish wait 修复后本机 opt-in full-stack 已通过 | 优先补 release-scope 真实 native capture 标准门禁、跨机器 TCC/ReplayKit 诊断和 production/default 录制策略 |
| `VS-MA-15` | partial evidence | stop artifact registration、degradation reason、path-conflict retry、restart recovery 和 adapter path 防御已有测试；脚本级真实 capture smoke 已断言三类音频缺失/降级必须带 `degradation_reason`；opt-in E2E 已证明三类音频缺失时 processing `generate_transcript` fail closed 且不登记派生产物；opt-in full-stack 已在本机验证真实 stop artifact registry 可进入 processing fail-closed transcript path | 优先补 release-scope stop 产物登记标准门禁、独立音频产物策略和后续 native-to-processing 成功链路 |
| `VS-MA-16` | 已达退出口径 | native processing state consumer、process runner、safe display、retry/busy guard 和 controlled fixture 已有证据；real processing-cli app-bundle UI smoke 使用 provider-owned `platform/e2e/ma-cli-local.sh` 路由，`build-for-testing` / architecture 检查通过；清理另一个 worktree 残留的同 bundle id `MeetingAssistantNative` 进程后，`MA_NATIVE_APP_XCODE_DESTINATION='platform=macOS,arch=arm64' MA_NATIVE_APP_REAL_PROCESSING_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 于 2026-07-05 08:26 通过，证明 `.app` UI 点击 `ma.processing.startButton` 能触发真实 `processing-cli` provider 并生成 `normalized_audio`、`transcript_text` 和 transcript-only `speaker_labels` artifact | 进入 `VS-MA-17/18/19`，收口 transcript 回查、复制/导出、删除确认的 release-scope OS 集成；后续 `VS-MA-20` 再串同一条 full-stack/release-scope 链路 |
| `VS-MA-17` | 已达退出口径 | transcript review UI 和 workspace artifact loader 已能消费 fixture/受控 artifact；2026-07-05 10:49 执行 `MA_NATIVE_APP_XCODE_DESTINATION='platform=macOS,arch=arm64' MA_NATIVE_APP_REAL_ACTION_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 通过，测试先经 `.app` UI 点击 `ma.processing.startButton` 触发真实 `processing-cli` provider 生成 transcript-only artifact，再重启 `.app` 读取同一 workspace/session，断言 transcript heading `Real processing CLI app-bundle fixture`、summary `Transcript has 1 segment for review.`、文本 `Fake transcript generated from local audio.` 和 `transcript-only fallback` 降级说明可见 | `VS-MA-20` 已由后续 MVP full-stack app-bundle smoke 收口；进入 `VS-MA-21/22` 前不把该 opt-in smoke 外推为真实 native capture、真实 runtime/model 质量或 release bundle |
| `VS-MA-18` | 已达退出口径 | copy/export UI、受控 process-runner workspace、production OS pasteboard/save-panel boundary 已有证据；2026-07-05 10:49 real action app-bundle smoke 通过，点击 `ma.transcriptAction.copyButton` 和 `ma.transcriptAction.exportButton` 后，经 `TranscriptActionProcessRunner` 与 provider-owned `platform/e2e/ma-cli-local.sh` 执行 `export_transcript`，UI 返回 `Copy complete.` / `Export complete.`，并在临时 workspace 外保留 Markdown 导出文件 | 进入 `VS-MA-20`；仍不把 deterministic XCTest save destination 等同于真实用户 Save Panel |
| `VS-MA-19` | 已达退出口径 | delete confirmation UI、受控 process-runner 删除、安全错误展示和 production command-client default 已有证据；2026-07-05 10:49 real action app-bundle smoke 通过，删除确认文案包含目标 session 和 `External exports are retained.`，点击 `ma.transcriptAction.deleteConfirmButton` 后经 provider-owned CLI 删除 session root，UI 返回 `Delete complete.` / `Deleted session session-app-ui-smoke.` / `Retained 1 external export.`，并验证 workspace 外导出保留和 delete event 不泄漏 transcript 文本 | `VS-MA-20` 已由后续 MVP full-stack app-bundle smoke 收口；进入 `VS-MA-21/22` |
| `VS-MA-19A` | 已达退出口径 | designed native shell、主操作 wiring、Debug/Release fixture 隔离和 app-bundle XCUITest 已覆盖 | 后续纵切不得退回 primitive debug UI |
| `VS-MA-20` | 已达退出口径 | 默认 local/full-stack smoke、designed shell marker 和 provider attribution 已有阶段证据；真实 native capture artifact stage 已接入 opt-in full-stack，且本机 opt-in full-stack 已通过 screen-only capture -> processing fail-closed transcript path；2026-07-05 执行 `MA_NATIVE_APP_XCODE_DESTINATION='platform=macOS,arch=arm64' MA_NATIVE_APP_MVP_FULL_STACK_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 通过，单个 app-bundle XCUITest 从 designed shell 点击录制开始/停止，登记受控 native recording 的 `screen_video` 和 `mixed_audio`，随后经 provider-owned `platform/e2e/ma-cli-local.sh` 触发真实 processing CLI 生成 `normalized_audio`、`transcript_text`、transcript-only `speaker_labels`，重启同一 workspace/session 后完成 transcript review、copy、export 和 delete confirmation，且验证导出文件保留和 delete event 不泄漏 transcript 文本 | 进入 `VS-MA-21/22` 做异常、重试、安全和供应链硬化；该 smoke 仍是显式 opt-in + 受控 recording 证据，不证明真实 ScreenCaptureKit 输出、真实用户 Save Panel、release bundle、完整 release provenance 或发布范围 `PV-MA-*` covered |
| `VS-MA-21` | partial evidence | processing failure retry、native safe display、stop retry、restart recovery 和路径/日志脱敏已有证据 | 在真实 capture/native-processing 链路闭合后补并发、重试和 checksum release 证据 |
| `VS-MA-22` | partial evidence | 组件 security/SBOM/build/architecture、provider redaction，以及 SBOM Apache-2.0 license/no packaged third-party runtime component/validation-only scope fail-closed 证据已有 | 补完整 release-scope SAST/SCA/license/provenance 和 model sidecar 证据 |
| `VS-MA-23` | 未进入 release-scope | `product-validation-check.py release` 仍有发布范围 `partial` 行 | 等 `VS-MA-14`-`VS-MA-22` 关闭后再运行 release candidate |
| `VS-MA-24` | MVP 外 | 团队分发、签名公证、自动更新和商业化分发不属于当前 MVP | 用户重新纳入范围时先走 spec-change 和 ADR |
| `VS-MA-25` | MVP 外 | 自动纪要或模型集成受 `OD-MA-009` watch 约束 | 用户确认自动 GPT/Qwen 后再新增 `CAP/AC/PV` |

当前顺序：`VS-MA-14/15`、`VS-MA-16`、`VS-MA-17/18/19` 和 `VS-MA-20` 已按阶段退出口径收口；下一步进入 `VS-MA-21/22`，最后才进入 `VS-MA-23` 发布候选。

| 顺序 | 纵切 | 能力和验收 | 主要实现表面 | 最小测试和证据 | 退出口径 |
|---|---|---|---|---|---|
| VS-MA-00 | 基线校准和证据管线 | Harness 基线，确认 `PROJECT-STATUS.md` 为 `project`，检查当前 `PV-MA-*` 状态 | `harness/project-manifest.json`、`scripts/`、现有 component scripts | `./scripts/docs-check.sh`、`./scripts/project-manifest-check.sh current`、`./scripts/agent-workflow-check.sh`、`./scripts/review-report.sh` | 现有门禁可运行；确认产品行为仍以验证矩阵为准，不把 skeleton smoke 当产品完成 |
| VS-MA-01 | 依赖检查命令收敛 | `CAP-MA-001`, `CAP-MA-005`; `AC-MA-001`, `AC-MA-005`; `PV-MA-001`, `PV-MA-005` | `platform/processing-cli` 的 `check_dependencies` JSON、错误码、workspace 和依赖来源摘要 | Processing CLI 单元/契约测试；fake environment 覆盖缺失依赖 `ok=false`；安全检查确认不自动下载 | 关闭 `TDG-MA-001` 和 `TDG-MA-006` 中 dependency-check 相关项；`PV-MA-005` 可推进到 `covered`；真实 macOS 权限检测未接 native 前，`PV-MA-001` 最多 `partial` |
| VS-MA-02 | Workspace 和 artifact contract 内核 | `CAP-MA-003`, `CAP-MA-009`; `AC-MA-003`, `AC-MA-009`; `PV-MA-003`, `PV-MA-009` | `session.json`、artifact registry、ID、checksum、单会话 lock、路径边界 helper | 文件契约测试：创建会话目录、登记 artifacts、校验原始媒体只追加、lock 冲突返回 `path_conflict` | 关闭 `TDG-MA-002` 的 session/artifact 基础项；`PV-MA-003`/`PV-MA-009` 获得可复用文件契约证据，后续命令不重复发明存储语义 |
| VS-MA-03 | 导入已有媒体 | `CAP-MA-004`, `CAP-MA-006`; `AC-MA-004`; `PV-MA-004`, `PV-MA-006` | `import_media` 命令、显式路径读取、格式初检、`source_type=imported_media` 会话创建 | fixture media 契约测试；非法路径、格式不支持和 workspace 越界负向测试 | 关闭或记录 `TDG-MA-001`、`TDG-MA-002`、`TDG-MA-003`、`TDG-MA-006` 的导入媒体项；`PV-MA-004` 至少 `partial`；导入路径能作为后续处理流水线测试入口 |
| VS-MA-04 | 标准化处理音频和输入选择 | `CAP-MA-006`, `CAP-MA-009`; `AC-MA-006`, `AC-MA-009`; `PV-MA-006`, `PV-MA-009` | 音频源选择策略、`normalized_audio` 生成、FFmpeg 或兼容 adapter 边界 | source selection 单元测试；fixture 音频生成 `.wav`；原始 `mixed_audio`/`system_audio`/`microphone_audio` hash 不变 | 关闭或记录 `TDG-MA-002`、`TDG-MA-003` 的 normalized audio 项；`PV-MA-006` 可推进；原始媒体保护在 `PV-MA-009` 继续累积证据 |
| VS-MA-05 | Transcript adapter 契约 | `CAP-MA-007`, `CAP-MA-009`; `AC-MA-007`, `AC-MA-009`; `PV-MA-007`, `PV-MA-009` | `generate_transcript` 命令、transcription adapter interface、fake adapter、`transcript.json` | 契约测试覆盖有序 segments、`start_ms < end_ms`、失败保留原始媒体、`artifact_missing`/`processing_failed` | 关闭或记录 `TDG-MA-001`、`TDG-MA-002`、`TDG-MA-003` 的 transcript 项；fake adapter 先让 `PV-MA-007` 到 `partial`；真实 runtime 接入前不报完整产品覆盖 |
| VS-MA-06 | 本地转写 runtime 接入 | `CAP-MA-007`; `AC-MA-007`; `PV-MA-007` | `runtime=whisper_cpp`、本地 `whisper.cpp` CLI、multilingual Whisper 模型路径、依赖检查联动、非敏感硬件 preflight | 小样例音频 smoke；runtime/model 缺失时稳定失败；非法 runtime fail fast；生成 transcript 和 fake 契约一致；无自动下载证据；hardware preflight 报告推荐模型等级适配风险；fixture 覆盖中文为主且夹杂 `HTTP`、`LLM`、`clean architecture`、`EDA` 等英文词汇 | 关闭或记录 `TDG-MA-001`、`TDG-MA-003`、`TDG-MA-006` 的真实 runtime 项；在可重复本地 runtime 证据纳入标准门禁且使用 multilingual 模型后，`PV-MA-007` 才能推进到 `covered`；硬件 preflight 只能支撑部署建议，不能替代真实 smoke |
| VS-MA-07 | Speaker label fallback 契约 | `CAP-MA-008`, `CAP-MA-009`; `AC-MA-008`, `AC-MA-009`; `PV-MA-008`, `PV-MA-009` | `generate_speaker_labels` 命令、transcript-only fallback、`speaker_labels.json` 或降级元数据 | 契约测试覆盖 `SPEAKER_01` 匿名格式、`is_verified_identity=false`、不修改 transcript text、引擎缺失降级 | 关闭或记录 `TDG-MA-001`、`TDG-MA-002`、`TDG-MA-003`、`TDG-MA-006` 的 speaker fallback 项；`PV-MA-008` 至少覆盖 fallback 和安全边界；真实 diarization 质量不作为 MVP 强承诺 |
| VS-MA-08 | Best-effort speaker adapter 硬化 | `CAP-MA-008`; `AC-MA-008`; `PV-MA-008` | 可选本地 speaker labeling adapter、引擎摘要、失败原因 | fixture transcript/audio 测试；重叠说话或不可用引擎降级测试 | adapter 可用时输出匿名 labels；不可用时仍以 transcript-only 完成交付，不新增实名识别事实 |
| VS-MA-09 | Transcript 导出 | `CAP-MA-010`, `CAP-MA-011`; `AC-MA-010`, `AC-MA-011`; `PV-MA-010`, `PV-MA-011` | `export_transcript` 命令、plain text / Markdown / JSON、可复制文本返回、导出摘要 | 导出文件测试；路径冲突测试；确认不读取外部 API key、不上传 transcript/audio/video | 关闭或记录 `TDG-MA-001`、`TDG-MA-002`、`TDG-MA-006` 的 export 项；`PV-MA-011` 可由 CLI 先推进；`PV-MA-010` 的回查显示待 native surface 补齐 |
| VS-MA-10 | 删除会话命令 | `CAP-MA-012`; `AC-MA-012`; `PV-MA-012` | `delete_session` 命令、`confirm=true`、workspace 内路径约束、删除摘要 | 当前 workspace 删除 fixture；workspace 外导出文件不被删除；不存在、越界、权限不足负向测试 | 关闭或记录 `TDG-MA-001`、`TDG-MA-002`、`TDG-MA-006` 的 delete 项；`PV-MA-012` 获得命令层和文件边界证据 |
| VS-MA-11 | Processing CLI 端到端流水线 | `CAP-MA-004`, `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-008`, `CAP-MA-009`, `CAP-MA-011`, `CAP-MA-012` | CLI 编排、temp workspace fixture、标准命令组合 | smoke: import -> normalize -> transcript -> speaker fallback -> export -> delete；纳入 `platform/e2e` 或组件测试 | `TDG-MA-001`、`TDG-MA-002`、`TDG-MA-003` 相关 processing 项可回归；相关 `PV-MA-*` 证据集中进入验证矩阵 |
| VS-MA-12 | Native app 权限和依赖状态面 | `CAP-MA-001`, `CAP-MA-005`; `AC-MA-001`, `AC-MA-005`; `PV-MA-001`, `PV-MA-005` | Swift/SwiftUI view model、权限状态、dependency check result 显示 | Swift Testing 覆盖状态转换；XCUITest 覆盖权限/依赖缺失文案和 accessible locator | 关闭或记录 `TDG-MA-004` 的权限/依赖 UI 项；`PV-MA-001` 从 CLI-only 推进到 native 可见阻断证据 |
| VS-MA-13 | Native 录制状态纵切 | `CAP-MA-002`; `AC-MA-002`; `PV-MA-002` | start/stop action、capture adapter interface、`created -> recording -> recorded/failed` 状态 | Swift Testing 覆盖状态机；fake capture adapter UI smoke 覆盖开始、录制中、停止保存 | 关闭或记录 `TDG-MA-004` 和 `TDG-MA-005` 的 fake capture 项；先用 fake adapter 建立可测 UI 和状态闭环；真实 capture 未接入前 `PV-MA-002` 只能 `partial` |
| VS-MA-14 | 原生 capture 技术纵切 | `CAP-MA-002`, `CAP-MA-003`; `AC-MA-002`, `AC-MA-003`; `PV-MA-002`, `PV-MA-003` | native capture adapter、录制目标选择、视频/音频落盘、权限 fail closed | 受控 native recording smoke；权限缺失、录制中断和保存失败证据；必要时 manual-evidence 记录环境 | 关闭或记录 `TDG-MA-005` 的 spike/native smoke 项；如果系统音频 capture 被证明不可行，停止实现并走 `spec-change`、ADR 和验证矩阵更新 |
| VS-MA-15 | Stop recording artifact 登记 | `CAP-MA-002`, `CAP-MA-003`, `CAP-MA-009`; `AC-MA-002`, `AC-MA-003`, `AC-MA-009`; `PV-MA-002`, `PV-MA-003`, `PV-MA-009` | stop 后写 `session.json`、登记 `screen_video`/三类音频、checksum、降级原因 | native smoke + 文件契约测试；重复 stop 幂等测试；缺失音轨登记 `capture_status` 和 `degradation_reason` | 原生录制产物能被 processing-cli 读取，`PV-MA-003` 可继续推进 |
| VS-MA-16 | Native 处理状态联动 | `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-008`, `CAP-MA-009`; `AC-MA-006`, `AC-MA-007`, `AC-MA-008`, `AC-MA-009`; `PV-MA-006`-`PV-MA-009` | native app 调用 processing-cli 或 helper，显示处理中、失败、降级和重试 | Swift Testing/XCUITest 覆盖处理失败、依赖缺失、transcript-only fallback、重试入口 | 关闭或记录 `TDG-MA-004` 的 processing state UI 项；用户能从录制会话进入处理链路；错误状态不吞掉原始媒体保护证据 |
| VS-MA-17 | Transcript 回查界面 | `CAP-MA-010`; `AC-MA-010`; `PV-MA-010` | Transcript review/export surface，时间戳 segments、匿名 labels 或降级原因 | Swift Testing view model；XCUITest 覆盖会话标题、时间戳、文本、匿名 label 和降级说明 | 关闭或记录 `TDG-MA-004` 的 transcript review 项；`PV-MA-010` 可由 native UI 证据推进 |
| VS-MA-18 | Native 导出/复制入口 | `CAP-MA-011`; `AC-MA-011`; `PV-MA-011` | UI copy/export action、调用 `export_transcript`、外部 GPT 边界文案 | XCUITest 覆盖用户主动触发；安全测试确认无 API key、无自动上传路径 | 关闭或记录 `TDG-MA-001`、`TDG-MA-004`、`TDG-MA-006` 的 native export 项；`PV-MA-011` 同时具备命令层和 UI 层证据 |
| VS-MA-19 | Native 删除确认入口 | `CAP-MA-012`; `AC-MA-012`; `PV-MA-012` | 删除确认 UI、调用 `delete_session`、结果摘要 | XCUITest 覆盖确认、取消、成功、越界/失败摘要；文件 fixture 证据复用命令层 | 关闭或记录 `TDG-MA-001`、`TDG-MA-002`、`TDG-MA-004`、`TDG-MA-006` 的 native delete 项；`PV-MA-012` 同时具备命令层和 UI 层证据 |
| VS-MA-19A | Designed native app shell | `CAP-MA-013`; `AC-MA-013`; `PV-MA-013` | SwiftUI shell layout、navigation、design tokens、session/artifact/processing/transcript/action panels、existing command/helper/adapter client wiring | Swift Testing 覆盖 shell view model 和 state projection；app-bundle XCUITest 覆盖 Preflight、recording、artifacts、processing、transcript、export/delete 主路径和失败/降级状态；Debug/XCTest fixture 与 Release 默认行为隔离检查；可选截图证据 | 关闭或记录 `TDG-MA-004` 和 `TDG-MA-008`；primitive debug UI 不再作为 MVP UI 完成口径；`PV-MA-013` 至少达到 `partial`，但真实 capture、真实 processing 和 release bundle 未证明时不得外推为相关 `PV-MA-*` covered |
| VS-MA-20 | 本地端到端 MVP smoke | `JRN-MA-001`-`JRN-MA-006`; 发布范围内全部 `PV-MA-*` | `platform/e2e`、manifest full-stack smoke、designed native shell + processing + workspace fixture | local smoke 覆盖至少一条导入处理链路和一条 native 录制链路，并证明 smoke 入口使用 designed shell 而不是 primitive debug UI；`./scripts/test-e2e-full-stack.sh` | `TDG-MA-003`、`TDG-MA-005`、`TDG-MA-007`、`TDG-MA-008` 的 release-scope 项均已关闭或有明确非发布范围说明；MVP 发布候选前，发布范围内 `PV-MA-*` 必须为 `covered` 或有明确非发布范围说明 |

## 硬化和发布纵切

| 顺序 | 纵切 | 触发条件 | 主要实现表面 | 最小验证 | 退出口径 |
|---|---|---|---|---|---|
| VS-MA-21 | 异常、重试和并发硬化 | Processing 和 native 主链路已打通 | lock、checksum 漂移检测、重复运行、失败日志和重试语义 | 并发/路径冲突测试、处理失败重试测试、日志脱敏检查 | 关闭或记录 `TDG-MA-002`、`TDG-MA-006` 的异常路径项；`PV-MA-009` 达到发布要求；失败可解释、可重试且不覆盖原始媒体 |
| VS-MA-22 | 安全和供应链硬化 | 引入或固定真实 runtime/模型/依赖前 | 允许来源说明、依赖摘要、license/SBOM、agent policy 不放宽 | `./scripts/security-check.sh`、`./scripts/supply-chain-check.sh current`、组件 security/SBOM 命令 | 关闭或记录 `TDG-MA-006` 的安全边界项；`SEC-MA-001`-`SEC-MA-005` 均有对应测试或门禁证据 |
| VS-MA-23 | 本地 MVP release candidate | 所有发布范围 `PV-MA-*` 已达到目标状态 | release preflight、production readiness 工件、review report evidence | `./scripts/check.sh`、`./scripts/test-e2e-full-stack.sh`、`./scripts/release-preflight.sh` | 关闭 `TDG-MA-007` 的 release-scope 证据项；可以进入人工发布审查；无阻塞 open decision，无未解释的 planned 发布项 |
| VS-MA-24 | 产品化分发准备 | 用户重新提出商业化分发、签名公证、自动更新、跨设备共享或集中支持诉求 | 分发、安装、签名/公证、权限、共享和支持规则 | 更新 product-spec、security、production readiness、供应链门禁和相应 E2E | 当前不提供团队分发或团队支持；进入范围前必须先走 spec-change 和 ADR |
| VS-MA-25 | 自动纪要或模型集成 | `OD-MA-009` 关闭并写入 API、安全、数据和 ADR 后 | 本地 Qwen 或外部 API adapter、密钥边界、隐私告知、质量验收 | 新增 `CAP/AC/PV`、安全测试、外部集成契约测试、无自动上传负向测试 | 这是后续范围；MVP 只允许用户主动复制或导出 transcript |

## Phase 0: Starter 校准

目标：

1. 确认事实源分卷、工程分卷和脚本入口完整。
2. 运行文档和 workflow 门禁。
3. 确认没有业务事实被写入 starter。
4. 验证项目清单、Agent 最小权限和发布 fail-closed。

退出标准：

1. `./scripts/docs-check.sh` 通过。
2. `./scripts/agent-workflow-check.sh` 通过。
3. `./scripts/review-report.sh --check` 通过。
4. `./scripts/harness-self-test.sh` 通过。
5. `./scripts/release-preflight.sh` 在 framework 模式按预期失败。

## Phase 1: 受控 adoption 和业务事实源填充

目标：

1. 运行 `./scripts/start-project.sh` 进入 `adoption`。
2. 将初始意向写入 `docs/adoption/INITIAL-REQUEST.md`，通过 discovery ledger 分轮澄清需求。
3. 只把已确认内容转写到产品范围、领域模型、权限、API、数据、事件、UI 和验收标准。
4. 为每个高风险行为建立验证矩阵行。
5. 关闭阻塞实现的 open decisions。
6. 填写安全需求、数据分类、威胁模型、组件清单、owner 和最小组件骨架。

退出标准：

1. 关键行为均有 `AC-*` 和 `PV-*`。
2. `10-open-decisions.md` 中没有阻塞第一批实现的问题。
3. 重要技术或产品决策有 ADR。
4. `./scripts/adoption-check.sh --activation` 通过。
5. 用户显式批准后，`./scripts/activate-project.sh` 成功切换到 `project`。
6. `./scripts/project-manifest-check.sh development` 通过。

## Phase 2: Meeting Assistant 本地纵切实现

目标：

1. 先实现 `processing-cli` 的本地命令契约、`check_dependencies`、artifact contract、导入媒体和 transcript/export 的可测试边界。
2. 再实现最小 `native-app` Swift/SwiftUI 控制面，覆盖权限状态、开始/停止录制状态、失败/降级提示和保存反馈。
3. 使用本地文件和元数据作为纵切持久化边界，不为了 Phase 1 引入 Web 前端、远程后端服务或数据库。
4. 为每条 `CMD-MA-*` 提供稳定 JSON 响应、错误码和自动化契约测试。
5. 对原生 macOS capture 先保持 native-first；如果技术 spike 证明系统音频 capture 不可行，只能通过 spec-change、ADR 和验证矩阵更新引入辅助 capture adapter。

退出标准：

1. `PV-MA-005` 至少达到 `partial`，`check_dependencies` 命令能输出平台、工具链、媒体工具、runtime、workspace、权限状态和允许来源摘要，且不自动下载依赖。
2. `PV-MA-003`、`PV-MA-006` 和 `PV-MA-009` 的 artifact contract 测试落地，产物登记、标准化音频、原始媒体保护和派生产物可重试规则有自动化验证。
3. `PV-MA-004`、`PV-MA-007`、`PV-MA-008`、`PV-MA-011` 和 `PV-MA-012` 至少通过 fake/local adapter 覆盖导入媒体、transcript、speaker-label fallback、导出和删除会话契约。
4. `native-app` 接入 Swift Testing 和 XCUITest 或等价 XCTest UI smoke，覆盖 `PV-MA-001`、`PV-MA-002`、`PV-MA-010`、`PV-MA-011` 和 `PV-MA-012` 的关键 UI 状态和 accessible locator。
5. `native-app` 完成 designed native shell 纵切，`PV-MA-013` 至少达到有明确阻塞缺口和关闭条件的 `partial`；primitive debug UI 不能作为 MVP UI 完成口径。
6. `./scripts/phase-preflight.sh`、`./scripts/agent-workflow-check.sh` 和 `./scripts/review-report.sh` 能引用真实组件测试证据；未覆盖的 `PV-MA-*` 必须保持 `planned` 或 `partial`，不能报 `covered`。

## Phase 3: 产品能力扩展和适配器硬化

目标：

1. 将 native capture、media processing、transcription、speaker labeling 和 export adapter 从 fake/smoke 推进到真实 runtime。
2. 固定样例媒体、fixture、adapter 版本和质量回归测试。
3. 完善异常路径：权限撤销、依赖缺失、磁盘写入失败、处理重试、artifact checksum 漂移和导出冲突。
4. 如需引入辅助 capture adapter、本地模型自动发现或新的依赖来源，先按 spec-change 更新事实源、ADR、安全和供应链规则。

退出标准：

1. 进入本阶段范围的 `PV-MA-*` 行达到 `covered`，且测试被标准门禁调用。
2. adapter 契约保持稳定，替换 runtime 不改变 `06-api-contracts.md` 和 `07-data-and-events.md` 定义的语义。
3. 高风险降级和失败路径有自动化测试或明确 manual-evidence 记录。

## Phase 4: 生产化

目标：

1. 完成生产 profile、secret 注入、健康检查、可观测性、限流和安全配置。
2. 完成 migration、回滚、备份恢复和数据修复策略。
3. 建立 release preflight。
4. 完成 SLO、容量、threat model、SBOM、签名、provenance、运行手册和恢复演练。

退出标准：

1. `./scripts/release-preflight.sh` 通过。
2. 发布范围内所有 `PV-*` 行为 `covered`。
3. 生产部署、回滚和监控告警完成审查。
4. `./scripts/production-readiness-check.sh` 和独立 Production Readiness Review 通过。
