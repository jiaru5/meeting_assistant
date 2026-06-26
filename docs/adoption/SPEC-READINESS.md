# Spec Readiness 状态

> Adoption 工作区文档。本文件跟踪持久事实源是否已准备好进入实现阶段。它不是产品事实源。

## Readiness 状态值

| 状态 | 含义 |
|---|---|
| `missing` | 该分卷仍只包含 starter 示例，或缺少必需项目事实。 |
| `partial` | 已有部分项目事实，但重要决策、验收标准或验证映射仍不完整。 |
| `ready` | 该分卷包含已确认、可实现、可测试的项目事实。 |
| `not-applicable` | 已明确该分卷不适用于本项目，并有已确认理由。 |

## 当前 Activation Blocker

| 领域 | 当前 blocker | 来源 |
|---|---|---|
| Product-spec 审查 | 已确认内容已经转写到持久 product-spec、ADR、open decisions 和 engineering 分卷；用户尚未审查完整持久规范集是否接受。 | `docs/product-spec/`, `harness/adoption-state.json` |
| 验证执行 | 已有真实 `PV-MA-*` 行并映射到未来产品测试；activation-time 非业务骨架和可执行项目命令已注册，但不证明产品行为已实现。 | `docs/engineering/06-product-validation-matrix.md`, `harness/project-manifest.json` |
| Manifest | 项目名、owner、非业务组件骨架、命令集、full-stack E2E smoke 计划和 Phase 1 本地运行准备工件已设置；仍等待用户审查。 | `harness/project-manifest.json` |
| Agent policy | 项目依赖策略已记录，且未扩大默认 Agent 权限；最终 activation 仍需要用户审查。 | `harness/agent-policy.json` |
| Sign-off | 阻塞性 open decisions 已关闭；尚未提供 product-spec 审查和 activation 批准。 | `harness/adoption-state.json` |

## Product-spec 分卷 Readiness

`./scripts/adoption-check.sh --activation` 要求下方每个必需行都为 `ready` 或明确 `not-applicable`，没有 blocking gap，product-spec 中没有 starter 占位，没有阻塞性 open decision，并且有用户显式确认。

| Chapter | Required content before project mode | Status | Blocking gap? | Next action |
|---|---|---|---|---|
| `01-product-scope.md` | 目标、非目标、用户、核心场景和可观察成功标准 | ready | no | 进入用户 spec-review；后续团队使用保持 watch，不阻塞个人 MVP。 |
| `02-domain-model.md` | 领域对象、字段、枚举、关系、生命周期和不变量 | ready | no | 进入用户 spec-review；artifact 测试等待 activation-time 骨架。 |
| `03-permissions-and-identity.md` | 认证、角色、权限、数据隔离和审计身份 | ready | no | 进入用户 spec-review；未来团队权限模型保持 watch。 |
| `04-user-journeys-and-ui.md` | 关键旅程、页面/视图、导航、状态、empty/error/forbidden 流 | ready | no | 进入用户 spec-review；非业务 native-app/helper 骨架属于 activation 准备。 |
| `05-business-rules-and-calculations.md` | 业务规则、状态机、计算、时间语义和幂等 | ready | no | 进入用户 spec-review；speaker fallback 测试等待 processing-cli 骨架。 |
| `06-api-contracts.md` | API 或命令契约、错误、分页、兼容性和外部契约 | ready | no | 进入用户 spec-review；MVP 不包含应用托管的外部 GPT/API 集成。 |
| `07-data-and-events.md` | 持久化、migration、事件、cache/search、保留和审计数据 | ready | no | 进入用户 spec-review；artifact contract 测试等待 activation-time 骨架。 |
| `08-implementation-guidance.md` | 技术栈、服务边界、集成策略和部署约束 | ready | no | 进入用户 spec-review；组件骨架和命令注册属于 activation 准备。 |
| `09-acceptance-criteria.md` | 映射到目标、旅程、权限和失败状态的 `AC-*` 标准 | ready | no | 进入用户 spec-review；AC-MA-001 到 AC-MA-007 已映射到 `PV-MA-*`。 |
| `10-open-decisions.md` | activation 前没有阻塞性的 `open` 决策 | ready | no | 阻塞性决策已关闭；watch 决策保留给未来团队分发和自动纪要。 |
| `11-adr.md` | 重要产品或技术决策已记录为 ADR | ready | no | ADR 已覆盖原生录制、文件边界、依赖检查、GPT 边界和骨架/adapter 策略。 |
| `12-ui-ux-design.md` | 如果存在 UI，则定义 UI/UX 契约、可访问性、响应式行为和 locator 规则 | ready | no | 进入用户 spec-review；UI 骨架和 locator 测试等待 activation-time 骨架。 |
| `13-security-and-compliance.md` | 安全需求、数据分类、威胁模型、合规、RTO/RPO/SLO hook | ready | no | 进入用户 spec-review；依赖检查和组件安全门禁等待 skeleton 命令。 |

## Engineering Readiness

| Area | Required content before project mode | Status | Blocking gap? | Next action |
|---|---|---|---|---|
| Validation matrix | 关键行为有真实 `PV-*` 行；没有 starter 模板验证行 | ready | no | `PV-MA-001` 到 `PV-MA-007` 已存在；状态保持 `planned`，直到组件测试/脚本落地后推进。 |
| Project manifest | 真实项目名、owner、组件骨架、命令、full-stack E2E 计划和生产工件 | ready | no | 非业务 activation skeleton、命令、smoke E2E 和 Phase 1 本地运行准备工件已注册；仍需用户 spec-review 和 activation 批准。 |
| Agent policy | 组织 allowlist、受保护路径、凭据规则和审批边界已审查 | ready | no | 保留现有默认最小权限策略；已加入项目依赖策略，且不自动下载。 |
| Adoption agent workflow | 已确认 adoption/spec 转写轮次的多 agent 工作流 | ready | no | 后续每轮 adoption/spec 应使用 PM + Worker + read-only Reviewer，并仅在需要时使用 Specialist。 |
| CI and gates | 必需检查已知、可执行且已注册 | ready | no | 现有 harness 门禁和项目 activation skeleton 命令已接入；产品行为测试在 project 模式按 `PV-MA-*` 推进。 |

## 建议的下一批转写目标

| 主题 | 当前状态 | 持久目标 |
|---|---|---|
| 用户 spec 审查 | 等待用户操作 | `harness/adoption-state.json` 的 `product_spec_reviewed` |
| Project activation 批准 | 等待用户显式批准 | `harness/adoption-state.json` 的 `approved_for_project_activation`, `confirmed_by`, `confirmation_text` |
| Project 模式切换 | 等待用户批准后由 agent 执行 `./scripts/activate-project.sh` | `docs/product-spec/PROJECT-STATUS.md`, activation gate evidence |

## Activation Sign-off

| 字段 | 值 |
|---|---|
| 用户是否已审查 product-spec | no |
| 阻塞性 open decisions 是否已关闭 | yes |
| 用户是否已显式批准 project activation | no |
| 确认人 |  |
| 确认时间 |  |
