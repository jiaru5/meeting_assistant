# 6. 产品验证矩阵

本文件定义产品规范到自动化验证的映射，用于判断产品行为是否达到面向 PRD、交互和功能的完整验证目标。

`docs/product-spec/` 是产品事实源；本文件只记录验证覆盖状态、验证类型、证据入口和缺口。

## 状态定义

| 状态 | 含义 |
|---|---|
| `missing` | 当前没有持久化自动化验证。 |
| `planned` | 已明确验证方式，但测试用例或脚本尚未落地。 |
| `partial` | 仓库内已有部分自动化验证，但没有覆盖完整范围。 |
| `covered` | 仓库内已有测试或脚本覆盖，并纳入标准门禁。 |
| `manual-evidence` | 有截图、交互记录或人工检查作为短期证据，但没有长期回归测试。 |

## 使用规则

1. 实现或修改产品行为前，先找到对应矩阵行。
2. 如果没有对应行，先补充矩阵行，再实现代码。
3. 行为完成后，将验证状态推进到 `covered`，或写明为什么只能保留为 `manual-evidence`。
4. 产品行为、UI/UX 契约、API 契约、事件契约和验收标准变更时，必须同步检查本矩阵。
5. Playwright 截图、人工观察或本地浏览器检查只能辅助开发和审查，不能长期替代仓库测试。

## Starter 基线矩阵

| ID | 场景或规则 | 主事实源 | 验证类型 | 目标测试入口 | 当前证据 | 状态 |
|---|---|---|---|---|---|---|
| PV-HARNESS-001 | 事实源分卷、工程分卷、入口脚本、当前模式叙述和产品能力链路一致性 | `docs/product-spec/README.md`、`docs/engineering/README.md` | 文档门禁 | `./scripts/docs-check.sh` | `docs-check` 检查必要分卷、索引、脚本入口、当前 mode 单一声明、project 模式下的 activation 状态漂移，以及 `CAP-MA-*`、`AC-MA-*`、`PV-MA-*` 的双向可追溯链路 | `covered` |
| PV-HARNESS-002 | Agent 工作流可生成 spec sync 和 review report 证据，并能识别 backend、frontend、platform 产品表面 | `05-agent-operating-model.md`、`04-review-and-ci-gates.md` | 工程门禁、自测试 | `./scripts/agent-workflow-check.sh`、`./scripts/review-report.sh --check`、`./scripts/harness-self-test.sh` | workflow gate 调用 spec sync 和 review report check；自测试覆盖 platform source 缺少验证矩阵、platform 实现缺少测试和 review report 推荐验证 | `covered` |
| PV-HARNESS-003 | Docker 优先且禁止宿主机数据库/中间件依赖 | `01-repo-structure.md`、`02-dev-commands.md` | 文档门禁、Compose 配置 | `./scripts/docs-check.sh`、`./scripts/compose-check.sh` | docs-check 扫描宿主机依赖，compose-check 解析本地和测试配置 | `covered` |
| PV-HARNESS-004 | 非 project 模式和空组件不能通过发布门禁 | `02-dev-commands.md`、`04-review-and-ci-gates.md` | Harness 自测试 | `./scripts/harness-self-test.sh` | 单元测试验证 release fail-closed 和未注册组件 | `covered` |
| PV-HARNESS-005 | Agent 使用最小文件、网络、凭据和外部写权限 | `12-agent-security.md` | 策略校验 | `./scripts/project-manifest-check.sh current` | 校验 `harness/agent-policy.json` 固定安全默认值 | `covered` |
| PV-HARNESS-006 | 真实组件必须注册质量、安全、架构和 SBOM 命令，且新增 frontend、backend 或 platform 组件不能绕过 manifest | `01-repo-structure.md`、`10-security-and-supply-chain.md` | 清单门禁、自测试 | `./scripts/project-manifest-check.sh development`、`./scripts/harness-self-test.sh` | project 模式缺少组件或命令即失败；自测试覆盖未注册 `platform/*/component.json` 失败路径 | `covered` |
| PV-HARNESS-007 | 发布候选执行真实 Compose full-stack E2E | `03-test-strategy.md`、`11-production-readiness.md` | 运行门禁、自测试 | `./scripts/test-e2e-full-stack.sh`、`./scripts/harness-self-test.sh` | project 清单驱动 pre-start、本地 smoke image 准备、`compose up --wait`、seed、测试和清理；自测试验证 full-stack runner 执行 pre-start/config/up/seed/test/cleanup 顺序 | `covered` |
| PV-HARNESS-008 | 交付审查引用实际命令、退出码、commit、worktree fingerprint 和日志 | `04-review-and-ci-gates.md` | 证据门禁 | `./scripts/check.sh`、`./scripts/review-report.sh --require-evidence` | `.harness/evidence/` 记录并验证当前工作区命令结果 | `covered` |
| PV-HARNESS-009 | 不完整初始意向只能进入 adoption 工作区，不能直接变成产品事实或业务实现 | `09-starter-adoption-guide.md`、`14-greenfield-project-start.md` | Adoption 门禁、自测试 | `./scripts/adoption-check.sh`、`./scripts/harness-self-test.sh` | adoption check 阻断空 initial request、template marker、未完成 readiness 和无确认 activation | `covered` |
| PV-HARNESS-010 | Project activation 必须显式确认且 fail-closed；placeholder、blocking open decision、缺少 manifest 或 PV 行都会阻断 | `09-starter-adoption-guide.md`、`04-review-and-ci-gates.md` | Adoption activation 门禁 | `./scripts/adoption-check.sh --activation`、`./scripts/activate-project.sh` | activate-project 先写入确认、运行 activation check，失败回滚到 adoption | `covered` |

## Meeting Assistant 产品验证矩阵

| ID | 场景或规则 | 主事实源 | 验证类型 | 目标测试入口 | 当前证据 | 状态 |
|---|---|---|---|---|---|---|
| PV-MA-001 | `CAP-MA-001` 录制前权限和环境预检 fail closed | `docs/product-spec/01-product-scope.md`, `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/06-api-contracts.md`, `docs/product-spec/13-security-and-compliance.md` | Native app 状态测试、本地命令契约测试、权限状态模拟 | 未来 `platform/native-app` Swift Testing / XCUITest；`platform/processing-cli/scripts/test.sh` 中的 permission/dependency contract | `processing-cli` 已能报告平台、workspace、依赖、CLI best-effort permission unknown/denied 状态和缺失必需依赖 `ok=false`；缺少真实 native 权限检测和 UI 阻断测试 | `partial` |
| PV-MA-002 | `CAP-MA-002` 原生录制启动、持续状态和停止保存 | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/06-api-contracts.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/09-acceptance-criteria.md` | Swift Testing、XCUITest、受控 native recording smoke | 未来 `platform/native-app` 产品行为测试 | `native-app` 仍是 activation skeleton，不实现录制状态或 start/stop 行为 | `planned` |
| PV-MA-003 | `CAP-MA-003` 会话和录制产物登记，包含降级原因 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/07-data-and-events.md` | 文件契约测试、录制 artifact registry 测试、受控 E2E | `platform/processing-cli/scripts/test.sh`; 未来 native stop recording smoke | `processing-cli` workspace contract 已覆盖会话目录、`session.json`、artifact registry、checksum、路径边界和单会话 lock；尚未接入真实 `stop_recording` 对 `screen_video`/`system_audio`/`microphone_audio`/`mixed_audio` 的完整登记和降级原因 | `partial` |
| PV-MA-004 | `CAP-MA-004` 导入已有媒体作为回退或测试路径，覆盖格式白名单、artifact type 映射、源文件保护和 `invalid_input` 边界 | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/06-api-contracts.md`, `docs/product-spec/07-data-and-events.md` | 本地命令契约测试、文件契约测试、fixture media smoke | `platform/processing-cli/scripts/test.sh`; 未来真实媒体 fixture smoke 和 native UI import smoke | `processing-cli` 已实现 `import_media`，组件测试覆盖 `.wav` 导入为 `mixed_audio`、`.mp4` 导入为 `screen_video`、CLI JSON 成功响应、源文件不覆盖、会话内 artifact 副本、无 `normalized_audio`/transcript/speaker labels 派生产物，以及 unsupported suffix、缺失路径、目录输入的 `invalid_input`；尚未覆盖真实媒体解码 smoke 或 native UI import 集成 | `partial` |
| PV-MA-005 | `CAP-MA-005` 本地依赖检查稳定 JSON 响应，缺失必需依赖 `ok=false`，不自动下载 | `docs/product-spec/06-api-contracts.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/13-security-and-compliance.md`, `docs/engineering/10-security-and-supply-chain.md` | 本地命令契约测试、fake 环境测试、安全扫描 | `platform/processing-cli/scripts/test.sh`; `./scripts/test.sh`; `./scripts/lint.sh` | `processing-cli` 已实现 `check_dependencies` JSON 响应、平台/架构/Swift/FFmpeg/transcription runtime/speaker fallback/workspace/权限状态/允许来源/不自动下载 checks，组件测试覆盖成功、缺失必需依赖 `ok=false` 和 CLI JSON 非零退出；根 `./scripts/test.sh` 已通过 manifest 纳入该组件测试。真实 native 权限阻断仍由 `PV-MA-001` 继续覆盖 | `covered` |
| PV-MA-006 | `CAP-MA-006` 标准化处理音频和输入选择，不覆盖原始音频 | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/09-acceptance-criteria.md` | 文件契约测试、样例媒体处理测试、source selection 单元测试 | `platform/processing-cli/scripts/test.sh`; `platform/processing-cli/scripts/architecture.sh`; 未来真实 FFmpeg/兼容 adapter smoke 和 native 处理入口 | `processing-cli` 已实现内部 fixture-compatible normalized audio stage，组件测试覆盖默认选择 `mixed_audio`、缺失 `mixed_audio` 时必须显式选择可用 `system_audio`/`microphone_audio`、无默认音频返回 `artifact_missing`、仅 WAV/PCM 源可登记为 `normalized_audio.wav`、重复执行按同源 artifact id 与 checksum 复用已登记 `normalized_audio` 且不改变原始音频 checksum、已有 fallback normalized audio 在缺失 `mixed_audio` 时仍要求显式 source、显式换源在未定义 replace policy 前返回 `path_conflict`、adapter 失败或输出无效时清理 temp 并写入 `logs/processing.log`、登记失败或后续校验失败时回滚派生产物文件和 session metadata；架构脚本断言没有公开 `normalize_audio` 命令；尚未覆盖真实媒体转码 runtime 或 native UI 处理入口 | `partial` |
| PV-MA-007 | `CAP-MA-007` 生成按时间排序的 transcript segments | `docs/product-spec/02-domain-model.md`, `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/06-api-contracts.md` | 本地命令契约测试、adapter fake 测试、样例 transcript 测试 | `platform/processing-cli/scripts/test.sh`; 未来真实 transcription runtime smoke 和 native 处理入口 | `processing-cli` 已实现 `generate_transcript` fake adapter，组件测试覆盖使用已有 `normalized_audio`、默认 `mixed_audio` 标准化后生成 `artifacts/transcript.json` 并登记 `transcript_text`、缺失 `mixed_audio` 时显式 `system_audio` 输入、segments 排序和 `start_ms < end_ms` 校验、`artifact_missing` 和 `processing_failed` 失败响应、adapter 异常或 adapter `ContractError` 不覆盖原始音频、显式 runtime 在 fake slice 中稳定失败、已存在有效 transcript 按 source 和 language 复用且不覆盖、language/config 冲突不覆盖、已登记 transcript checksum drift 和持久化 segments 顺序错误会阻断复用、登记失败或后续校验失败时回滚 transcript 文件；尚未覆盖真实 transcription runtime 或 native UI 处理入口 | `partial` |
| PV-MA-008 | `CAP-MA-008` best-effort 匿名 speaker labels 和 transcript-only fallback | `docs/product-spec/02-domain-model.md`, `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/13-security-and-compliance.md` | 单元测试、样例 transcript 测试、fallback 契约测试 | 未来 `platform/processing-cli` speaker-label fallback 测试 | Product-spec 已允许 transcript-only fallback；尚未实现 fallback artifact 或 UI/metadata 证据 | `planned` |
| PV-MA-009 | `CAP-MA-009` 文件化流水线重试和原始媒体保护 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/11-adr.md` | 文件契约测试、处理重试测试、并发/路径冲突测试 | `platform/processing-cli/scripts/test.sh`; 未来 processing pipeline retry tests | `processing-cli` workspace contract 已覆盖原始媒体 artifact 按类型 append-only、checksum 漂移检测、workspace/session 路径越界 `path_conflict` 和单会话 lock 冲突；normalized audio 组件测试补充覆盖重复执行不改动原始音频 checksum、失败保留 `processing.log`、adapter temp 清理、登记失败和后续校验失败回滚派生产物文件及 session metadata，且不登记无效派生产物；transcript fake adapter 组件测试补充覆盖失败不覆盖原始音频、已存在有效 transcript 复用不覆盖、登记失败回滚 transcript 文件；尚未覆盖 speaker labels、export 等完整派生产物重试链路 | `partial` |
| PV-MA-010 | `CAP-MA-010` transcript 回查状态显示时间戳、文本、匿名 labels 或降级原因 | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/12-ui-ux-design.md` | Native app 状态测试、XCUITest、可访问性 locator 检查 | 未来 `platform/native-app` transcript review 状态测试 | UI/UX 契约已定义；尚未实现 transcript review surface | `planned` |
| PV-MA-011 | `CAP-MA-011` transcript 复制或导出由用户主动触发，应用不自动上传外部 GPT 或模型 API | `docs/product-spec/06-api-contracts.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/13-security-and-compliance.md` | 本地命令契约测试、导出文件测试、安全边界测试、UI 状态测试 | 未来 `platform/processing-cli` export 测试和 `platform/native-app` export/copy UI smoke | Product-spec 已定义外部边界；仓库尚未实现 export contract 或 no-auto-upload 负向测试 | `planned` |
| PV-MA-012 | `CAP-MA-012` 删除当前 workspace 内目标会话目录，且不删除 workspace 外导出文件 | `docs/product-spec/03-permissions-and-identity.md`, `docs/product-spec/06-api-contracts.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/13-security-and-compliance.md` | 本地命令契约测试、路径边界测试、文件删除 fixture 测试、UI 确认状态测试 | 未来 `platform/processing-cli` delete session contract tests 和 `platform/native-app` delete confirmation UI smoke | Product-spec 已定义删除语义和命令契约；仓库尚未实现 delete session 命令或路径边界测试 | `planned` |

## 标准验证命令目标

```bash
./scripts/docs-check.sh
./scripts/adoption-check.sh
./scripts/project-manifest-check.sh
./scripts/harness-self-test.sh
./scripts/compose-check.sh
./scripts/prod-config-check.sh
./scripts/architecture-check.sh
./scripts/security-check.sh
./scripts/supply-chain-check.sh
./scripts/db-migration-check.sh
./scripts/spec-sync-check.sh
./scripts/agent-workflow-check.sh
./scripts/check.sh
./scripts/test-e2e.sh
./scripts/test-e2e-full-stack.sh
./scripts/build.sh
./scripts/release-preflight.sh
```

## 产品级完成标准

一个产品行为只有同时满足以下条件，才能视为完成：

1. 对应事实源已更新或确认不需要更新。
2. 对应矩阵行存在。
3. 关键路径有自动化验证，状态达到 `covered`。
4. 如果短期只能使用 `manual-evidence`，交付说明必须写明证据、缺口和下一步测试落点。
5. 验证不依赖宿主机数据库、中间件或本机常驻服务。
