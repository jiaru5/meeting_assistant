# Spec Readiness 状态

> Adoption 工作区文档。本文件跟踪持久事实源是否已准备好进入实现阶段。它不是产品事实源。

## Readiness 状态值

| 状态 | 含义 |
|---|---|
| `missing` | 该分卷仍只包含 starter 示例，或缺少必需项目事实。 |
| `partial` | 已有部分项目事实，但重要决策、验收标准或验证映射仍不完整。 |
| `ready` | 该分卷包含已确认、可实现、可测试的项目事实。 |
| `not-applicable` | 已明确该分卷不适用于本项目，并有已确认理由。 |

## Activation 审计快照

本节记录 2026-06-26 activation 审计结果，不声明当前 mode。当前 mode 值只以 `docs/product-spec/PROJECT-STATUS.md` 为准。

| 领域 | Activation 审计结论 | 来源 |
|---|---|---|
| Product-spec 审查 | activation 时已完成；用户确认 product-spec、ADR、open decisions、validation matrix、manifest 和 readiness 可作为事实源与执行规范。 | `docs/product-spec/`, `harness/adoption-state.json` |
| 验证执行 | activation 时已有真实 `PV-MA-*` 行并映射到未来产品测试；非业务骨架和可执行项目命令已注册，但不证明产品行为已实现。 | `docs/engineering/06-product-validation-matrix.md`, `harness/project-manifest.json` |
| Manifest | 项目名、owner、非业务组件骨架、命令集、full-stack E2E smoke 计划和 Phase 1 本地运行准备工件已设置。 | `harness/project-manifest.json` |
| Agent policy | 项目依赖策略已记录，且未扩大默认 Agent 权限。 | `harness/agent-policy.json` |
| Sign-off | activation 时已完成；阻塞性 open decisions 已关闭，用户已批准 project activation。 | `harness/adoption-state.json` |

## Product-spec 分卷 Readiness

`./scripts/adoption-check.sh --activation` 要求下方每个必需行都为 `ready` 或明确 `not-applicable`，没有 blocking gap，product-spec 中没有 starter 占位，没有阻塞性 open decision，并且有用户显式确认。

| Chapter | Required content before project mode | Status | Blocking gap? | Next action |
|---|---|---|---|---|
| `01-product-scope.md` | 目标、非目标、用户、核心场景和可观察成功标准 | ready | no | activation 审计为 ready；后续团队使用保持 watch，不阻塞个人 MVP。 |
| `02-domain-model.md` | 领域对象、字段、枚举、关系、生命周期和不变量 | ready | no | activation 审计为 ready；artifact 测试按 `PV-MA-*` 推进。 |
| `03-permissions-and-identity.md` | 认证、角色、权限、数据隔离和审计身份 | ready | no | activation 审计为 ready；未来团队权限模型保持 watch。 |
| `04-user-journeys-and-ui.md` | 关键旅程、页面/视图、导航、状态、empty/error/forbidden 流 | ready | no | activation 审计为 ready；真实 native-app/helper 行为按验证矩阵推进。 |
| `05-business-rules-and-calculations.md` | 业务规则、状态机、计算、时间语义和幂等 | ready | no | activation 审计为 ready；speaker fallback 测试按 `PV-MA-004` 推进。 |
| `06-api-contracts.md` | API 或命令契约、错误、分页、兼容性和外部契约 | ready | no | activation 审计为 ready；MVP 不包含应用托管的外部 GPT/API 集成。 |
| `07-data-and-events.md` | 持久化、migration、事件、cache/search、保留和审计数据 | ready | no | activation 审计为 ready；artifact contract 测试按 `PV-MA-*` 推进。 |
| `08-implementation-guidance.md` | 技术栈、服务边界、集成策略和部署约束 | ready | no | activation 审计为 ready；组件 skeleton 只作为初始工程边界。 |
| `09-acceptance-criteria.md` | 映射到目标、旅程、权限和失败状态的 `AC-*` 标准 | ready | no | activation 审计为 ready；AC-MA-001 到 AC-MA-007 已映射到 `PV-MA-*`。 |
| `10-open-decisions.md` | activation 前没有阻塞性的 `open` 决策 | ready | no | 阻塞性决策已关闭；watch 决策保留给未来团队分发和自动纪要。 |
| `11-adr.md` | 重要产品或技术决策已记录为 ADR | ready | no | ADR 已覆盖原生录制、文件边界、依赖检查、GPT 边界和骨架/adapter 策略。 |
| `12-ui-ux-design.md` | 如果存在 UI，则定义 UI/UX 契约、可访问性、响应式行为和 locator 规则 | ready | no | activation 审计为 ready；UI 行为测试按 `PV-MA-*` 推进。 |
| `13-security-and-compliance.md` | 安全需求、数据分类、威胁模型、合规、RTO/RPO/SLO hook | ready | no | activation 审计为 ready；依赖检查和组件安全门禁按 manifest 命令推进。 |

## Engineering Readiness

| Area | Required content before project mode | Status | Blocking gap? | Next action |
|---|---|---|---|---|
| Validation matrix | 关键行为有真实 `PV-*` 行；没有 starter 模板验证行 | ready | no | `PV-MA-001` 到 `PV-MA-007` 已存在；状态保持 `planned`，直到组件测试/脚本落地后推进。 |
| Project manifest | 真实项目名、owner、组件骨架、命令、full-stack E2E 计划和生产工件 | ready | no | 非业务 skeleton、命令、smoke E2E 和 Phase 1 本地运行准备工件已注册；当前注册表以 `harness/project-manifest.json` 为准。 |
| Agent policy | 组织 allowlist、受保护路径、凭据规则和审批边界已审查 | ready | no | 保留现有默认最小权限策略；已加入项目依赖策略，且不自动下载。 |
| Adoption agent workflow | 已确认 adoption/spec 转写轮次的多 agent 工作流 | ready | no | 后续每轮 adoption/spec 应使用 PM + Worker + read-only Reviewer，并仅在需要时使用 Specialist。 |
| CI and gates | 必需检查已知、可执行且已注册 | ready | no | harness 门禁和非业务 skeleton 命令在 activation 审计时已接入；产品行为测试按 `PV-MA-*` 推进。 |

## Activation 后 follow-up 记录

| 主题 | Activation 审计值 | 持久目标 |
|---|---|---|
| 用户 spec 审查 | 已完成 | `harness/adoption-state.json` 的 `product_spec_reviewed` |
| Project activation 批准 | 已完成 | `harness/adoption-state.json` 的 `approved_for_project_activation`, `confirmed_by`, `confirmation_text` |
| 第一条产品纵切 | 待实现 | 对应 product-spec 主责分卷、`AC-MA-*`、`PV-MA-*` 和组件测试 |

## Activation Sign-off 审计值

| 字段 | 值 |
|---|---|
| 用户是否已审查 product-spec | yes |
| 阻塞性 open decisions 是否已关闭 | yes |
| 用户是否已显式批准 project activation | yes |
| 确认人 | JeRRy |
| 确认时间 | 2026-06-26T10:08:01+00:00 |
