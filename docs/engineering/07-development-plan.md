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

## MVP 纵切计划

下表是面向当前 Phase 1 MVP 的最小开发粒度。每一行都应能独立形成“实现 + 测试 + 验证矩阵证据 + 门禁”的交付单元。

| 顺序 | 纵切 | 能力和验收 | 主要实现表面 | 最小测试和证据 | 退出口径 |
|---|---|---|---|---|---|
| VS-MA-00 | 基线校准和证据管线 | Harness 基线，确认 `PROJECT-STATUS.md` 为 `project`，检查当前 `PV-MA-*` 状态 | `harness/project-manifest.json`、`scripts/`、现有 component scripts | `./scripts/docs-check.sh`、`./scripts/project-manifest-check.sh current`、`./scripts/agent-workflow-check.sh`、`./scripts/review-report.sh` | 现有门禁可运行；确认产品行为仍以验证矩阵为准，不把 skeleton smoke 当产品完成 |
| VS-MA-01 | 依赖检查命令收敛 | `CAP-MA-001`, `CAP-MA-005`; `AC-MA-001`, `AC-MA-005`; `PV-MA-001`, `PV-MA-005` | `platform/processing-cli` 的 `check_dependencies` JSON、错误码、workspace 和依赖来源摘要 | Processing CLI 单元/契约测试；fake environment 覆盖缺失依赖 `ok=false`；安全检查确认不自动下载 | `PV-MA-005` 可推进到 `covered`；真实 macOS 权限检测未接 native 前，`PV-MA-001` 最多 `partial` |
| VS-MA-02 | Workspace 和 artifact contract 内核 | `CAP-MA-003`, `CAP-MA-009`; `AC-MA-003`, `AC-MA-009`; `PV-MA-003`, `PV-MA-009` | `session.json`、artifact registry、ID、checksum、单会话 lock、路径边界 helper | 文件契约测试：创建会话目录、登记 artifacts、校验原始媒体只追加、lock 冲突返回 `path_conflict` | `PV-MA-003`/`PV-MA-009` 获得可复用文件契约证据，后续命令不重复发明存储语义 |
| VS-MA-03 | 导入已有媒体 | `CAP-MA-004`, `CAP-MA-006`; `AC-MA-004`; `PV-MA-004`, `PV-MA-006` | `import_media` 命令、显式路径读取、格式初检、`source_type=imported_media` 会话创建 | fixture media 契约测试；非法路径、格式不支持和 workspace 越界负向测试 | `PV-MA-004` 至少 `partial`；导入路径能作为后续处理流水线测试入口 |
| VS-MA-04 | 标准化处理音频和输入选择 | `CAP-MA-006`, `CAP-MA-009`; `AC-MA-006`, `AC-MA-009`; `PV-MA-006`, `PV-MA-009` | 音频源选择策略、`normalized_audio` 生成、FFmpeg 或兼容 adapter 边界 | source selection 单元测试；fixture 音频生成 `.wav`；原始 `mixed_audio`/`system_audio`/`microphone_audio` hash 不变 | `PV-MA-006` 可推进；原始媒体保护在 `PV-MA-009` 继续累积证据 |
| VS-MA-05 | Transcript adapter 契约 | `CAP-MA-007`, `CAP-MA-009`; `AC-MA-007`, `AC-MA-009`; `PV-MA-007`, `PV-MA-009` | `generate_transcript` 命令、transcription adapter interface、fake adapter、`transcript.json` | 契约测试覆盖有序 segments、`start_ms < end_ms`、失败保留原始媒体、`artifact_missing`/`processing_failed` | fake adapter 先让 `PV-MA-007` 到 `partial`；真实 runtime 接入前不报完整产品覆盖 |
| VS-MA-06 | 本地转写 runtime 接入 | `CAP-MA-007`; `AC-MA-007`; `PV-MA-007` | 本地 Whisper 或已确认 runtime adapter、runtime 配置、依赖检查联动 | 小样例音频 smoke；runtime 缺失时稳定失败；生成 transcript 和 fake 契约一致 | 在可重复本地 runtime 证据纳入标准门禁后，`PV-MA-007` 才能推进到 `covered` |
| VS-MA-07 | Speaker label fallback 契约 | `CAP-MA-008`, `CAP-MA-009`; `AC-MA-008`, `AC-MA-009`; `PV-MA-008`, `PV-MA-009` | `generate_speaker_labels` 命令、transcript-only fallback、`speaker_labels.json` 或降级元数据 | 契约测试覆盖 `SPEAKER_01` 匿名格式、`is_verified_identity=false`、不修改 transcript text、引擎缺失降级 | `PV-MA-008` 至少覆盖 fallback 和安全边界；真实 diarization 质量不作为 MVP 强承诺 |
| VS-MA-08 | Best-effort speaker adapter 硬化 | `CAP-MA-008`; `AC-MA-008`; `PV-MA-008` | 可选本地 speaker labeling adapter、引擎摘要、失败原因 | fixture transcript/audio 测试；重叠说话或不可用引擎降级测试 | adapter 可用时输出匿名 labels；不可用时仍以 transcript-only 完成交付，不新增实名识别事实 |
| VS-MA-09 | Transcript 导出 | `CAP-MA-010`, `CAP-MA-011`; `AC-MA-010`, `AC-MA-011`; `PV-MA-010`, `PV-MA-011` | `export_transcript` 命令、plain text / Markdown / JSON、可复制文本返回、导出摘要 | 导出文件测试；路径冲突测试；确认不读取外部 API key、不上传 transcript/audio/video | `PV-MA-011` 可由 CLI 先推进；`PV-MA-010` 的回查显示待 native surface 补齐 |
| VS-MA-10 | 删除会话命令 | `CAP-MA-012`; `AC-MA-012`; `PV-MA-012` | `delete_session` 命令、`confirm=true`、workspace 内路径约束、删除摘要 | 当前 workspace 删除 fixture；workspace 外导出文件不被删除；不存在、越界、权限不足负向测试 | `PV-MA-012` 获得命令层和文件边界证据 |
| VS-MA-11 | Processing CLI 端到端流水线 | `CAP-MA-004`, `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-008`, `CAP-MA-009`, `CAP-MA-011`, `CAP-MA-012` | CLI 编排、temp workspace fixture、标准命令组合 | smoke: import -> normalize -> transcript -> speaker fallback -> export -> delete；纳入 `platform/e2e` 或组件测试 | processing 侧核心链路可回归；相关 `PV-MA-*` 证据集中进入验证矩阵 |
| VS-MA-12 | Native app 权限和依赖状态面 | `CAP-MA-001`, `CAP-MA-005`; `AC-MA-001`, `AC-MA-005`; `PV-MA-001`, `PV-MA-005` | Swift/SwiftUI view model、权限状态、dependency check result 显示 | Swift Testing 覆盖状态转换；XCUITest 覆盖权限/依赖缺失文案和 accessible locator | `PV-MA-001` 从 CLI-only 推进到 native 可见阻断证据 |
| VS-MA-13 | Native 录制状态纵切 | `CAP-MA-002`; `AC-MA-002`; `PV-MA-002` | start/stop action、capture adapter interface、`created -> recording -> recorded/failed` 状态 | Swift Testing 覆盖状态机；fake capture adapter UI smoke 覆盖开始、录制中、停止保存 | 先用 fake adapter 建立可测 UI 和状态闭环；真实 capture 未接入前 `PV-MA-002` 只能 `partial` |
| VS-MA-14 | 原生 capture 技术纵切 | `CAP-MA-002`, `CAP-MA-003`; `AC-MA-002`, `AC-MA-003`; `PV-MA-002`, `PV-MA-003` | native capture adapter、录制目标选择、视频/音频落盘、权限 fail closed | 受控 native recording smoke；权限缺失、录制中断和保存失败证据；必要时 manual-evidence 记录环境 | 如果系统音频 capture 被证明不可行，停止实现并走 `spec-change`、ADR 和验证矩阵更新 |
| VS-MA-15 | Stop recording artifact 登记 | `CAP-MA-002`, `CAP-MA-003`, `CAP-MA-009`; `AC-MA-002`, `AC-MA-003`, `AC-MA-009`; `PV-MA-002`, `PV-MA-003`, `PV-MA-009` | stop 后写 `session.json`、登记 `screen_video`/三类音频、checksum、降级原因 | native smoke + 文件契约测试；重复 stop 幂等测试；缺失音轨登记 `capture_status` 和 `degradation_reason` | 原生录制产物能被 processing-cli 读取，`PV-MA-003` 可继续推进 |
| VS-MA-16 | Native 处理状态联动 | `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-008`, `CAP-MA-009`; `AC-MA-006`, `AC-MA-007`, `AC-MA-008`, `AC-MA-009`; `PV-MA-006`-`PV-MA-009` | native app 调用 processing-cli 或 helper，显示处理中、失败、降级和重试 | Swift Testing/XCUITest 覆盖处理失败、依赖缺失、transcript-only fallback、重试入口 | 用户能从录制会话进入处理链路；错误状态不吞掉原始媒体保护证据 |
| VS-MA-17 | Transcript 回查界面 | `CAP-MA-010`; `AC-MA-010`; `PV-MA-010` | Transcript review/export surface，时间戳 segments、匿名 labels 或降级原因 | Swift Testing view model；XCUITest 覆盖会话标题、时间戳、文本、匿名 label 和降级说明 | `PV-MA-010` 可由 native UI 证据推进 |
| VS-MA-18 | Native 导出/复制入口 | `CAP-MA-011`; `AC-MA-011`; `PV-MA-011` | UI copy/export action、调用 `export_transcript`、外部 GPT 边界文案 | XCUITest 覆盖用户主动触发；安全测试确认无 API key、无自动上传路径 | `PV-MA-011` 同时具备命令层和 UI 层证据 |
| VS-MA-19 | Native 删除确认入口 | `CAP-MA-012`; `AC-MA-012`; `PV-MA-012` | 删除确认 UI、调用 `delete_session`、结果摘要 | XCUITest 覆盖确认、取消、成功、越界/失败摘要；文件 fixture 证据复用命令层 | `PV-MA-012` 同时具备命令层和 UI 层证据 |
| VS-MA-20 | 本地端到端 MVP smoke | `JRN-MA-001`-`JRN-MA-006`; 发布范围内全部 `PV-MA-*` | `platform/e2e`、manifest full-stack smoke、native + processing + workspace fixture | local smoke 覆盖至少一条导入处理链路和一条 native 录制链路；`./scripts/test-e2e-full-stack.sh` | MVP 发布候选前，发布范围内 `PV-MA-*` 必须为 `covered` 或有明确非发布范围说明 |

## 硬化和发布纵切

| 顺序 | 纵切 | 触发条件 | 主要实现表面 | 最小验证 | 退出口径 |
|---|---|---|---|---|---|
| VS-MA-21 | 异常、重试和并发硬化 | Processing 和 native 主链路已打通 | lock、checksum 漂移检测、重复运行、失败日志和重试语义 | 并发/路径冲突测试、处理失败重试测试、日志脱敏检查 | `PV-MA-009` 达到发布要求；失败可解释、可重试且不覆盖原始媒体 |
| VS-MA-22 | 安全和供应链硬化 | 引入或固定真实 runtime/模型/依赖前 | 允许来源说明、依赖摘要、license/SBOM、agent policy 不放宽 | `./scripts/security-check.sh`、`./scripts/supply-chain-check.sh current`、组件 security/SBOM 命令 | `SEC-MA-001`-`SEC-MA-005` 均有对应测试或门禁证据 |
| VS-MA-23 | 本地 MVP release candidate | 所有发布范围 `PV-MA-*` 已达到目标状态 | release preflight、production readiness 工件、review report evidence | `./scripts/check.sh`、`./scripts/test-e2e-full-stack.sh`、`./scripts/release-preflight.sh` | 可以进入人工发布审查；无阻塞 open decision，无未解释的 planned 发布项 |
| VS-MA-24 | 团队内部分发准备 | `OD-MA-008` 关闭并写入主责分卷和 ADR 后 | 分发、安装、签名/公证、团队权限、共享和支持规则 | 更新 product-spec、security、production readiness、供应链门禁和相应 E2E | 这是后续范围；关闭 watch 决策前不得实现为默认产品能力 |
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
5. `./scripts/check.sh`、`./scripts/agent-workflow-check.sh` 和 `./scripts/review-report.sh` 能引用真实组件测试证据；未覆盖的 `PV-MA-*` 必须保持 `planned` 或 `partial`，不能报 `covered`。

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
