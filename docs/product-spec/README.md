# Meeting Assistant 产品和技术规范

本目录是 `meeting_assistant` 的产品和应用技术设计唯一事实源。当前模式只由 `PROJECT-STATUS.md` 声明；当模式允许实现时，本目录中的 Meeting Assistant 事实可以作为 AI agent 技术方案设计、代码实现、测试和审查依据。

项目目标是构建一个本地 macOS 会议助手，用于录制线上会议或现场讨论，保存可回查的会议视频、音频、转写文本，并在 MVP 中提供 best-effort 匿名说话人标签。会议纪要生成不是 MVP 必需能力；用户可以主动复制 transcript 到 GPT 等外部工具。

字段名、枚举值、命令名、文件格式、API 路径、事件名、数据库对象和代码标识符使用英文并保持稳定；产品、技术和工程规范说明统一使用中文。

工程执行规范见 `docs/engineering/`。工程规范可以定义仓库结构、命令、测试、CI 和 Docker 交付方式，但不能覆盖本目录中的产品和应用技术事实。

`docs/adoption/` 保留为转写审计工作区，只保存原始意向、问答、假设、冲突和 readiness 记录；该目录不是事实源，也不能覆盖本目录。

## 模式

当前模式的唯一声明见 `PROJECT-STATUS.md`。其他文件只能引用该文件，不能独立记录当前 mode 值。

1. `adoption`：正在把已确认项目事实转写到本目录；不得实现业务代码。
2. `project`：本目录全部替换为真实项目事实，且 activation 门禁通过后，才能开始业务实现。

产品行为实现必须先对齐主责分卷、`09-acceptance-criteria.md` 和 `docs/engineering/06-product-validation-matrix.md`；`PV-MA-*` 为 `planned` 时不能声称对应产品行为已完成。

Phase 1 MVP 的产品能力索引以 `01-product-scope.md` 中的 `CAP-MA-*` 能力矩阵为入口；每个能力必须能追溯到对应主责分卷、`AC-MA-*` 验收标准和 `PV-MA-*` 验证矩阵行。

## 事实源归属

同一主题只能有一个主责分卷。其他分卷可以引用主责分卷，但不得复制一套可独立维护的规则。

| 主题 | 主责分卷 | 其他分卷如何使用 |
|---|---|---|
| 产品范围、目标、非目标、角色和场景边界 | `01-product-scope.md` | 只引用，不重新定义范围 |
| 领域对象、字段、枚举、关系、生命周期 | `02-domain-model.md` | API、数据、页面和测试只引用字段语义 |
| 身份、认证、授权、数据隔离 | `03-permissions-and-identity.md` | UI 只定义权限状态呈现，命令/API 只定义校验入口 |
| 用户旅程、页面或本地工具入口 | `04-user-journeys-and-ui.md` | UI/UX 分卷只定义布局和交互呈现 |
| 业务规则、状态机、转写、分轨、speaker label 规则 | `05-business-rules-and-calculations.md` | 命令、页面和测试只引用规则结果 |
| 本地命令、内部接口和外部集成契约 | `06-api-contracts.md` | 实现和测试只引用契约，不反向发明语义 |
| 文件、元数据、数据保留、事件和审计 | `07-data-and-events.md` | 代码可等价实现，但不能改变语义 |
| 技术栈、应用边界、依赖和部署约束 | `08-implementation-guidance.md` | 工程规范定义落地方式，不改写技术栈 |
| 产品验收口径 | `09-acceptance-criteria.md` | 验证矩阵只记录覆盖状态 |
| 尚未确认的产品或技术问题 | `10-open-decisions.md` | 已关闭问题回到对应主责分卷维护 |
| 变更流程和 ADR 历史 | `11-adr.md` | ADR 记录背景，当前规则以主责分卷为准 |
| UI/UX、可访问性、交互状态、测试定位契约 | `12-ui-ux-design.md` | 不定义业务字段、权限、命令或计算规则 |
| 安全需求、数据分类、威胁模型、合规和风险接受 | `13-security-and-compliance.md` | 工程分卷只定义扫描、CI 和供应链实现 |

## 分卷索引

| 文件 | 覆盖内容 |
|---|---|
| `PROJECT-STATUS.md` | 当前模式：framework、adoption 或 project |
| `00-governance.md` | 文档治理、事实源冲突、变更流程入口 |
| `01-product-scope.md` | 产品目标、非目标、用户角色、核心场景 |
| `02-domain-model.md` | 领域模型、数据字典、字段、枚举、关系、生命周期 |
| `03-permissions-and-identity.md` | 认证、授权、数据隔离、审计身份 |
| `04-user-journeys-and-ui.md` | 用户旅程、本地工具入口、页面或交互范围 |
| `05-business-rules-and-calculations.md` | 规则、状态机、分轨、转写、speaker label 口径 |
| `06-api-contracts.md` | 本地命令、内部接口、错误和外部集成边界 |
| `07-data-and-events.md` | 文件模型、元数据、事件、保留、删除、审计 |
| `08-implementation-guidance.md` | 技术栈、模块边界、依赖策略和部署约束 |
| `09-acceptance-criteria.md` | 产品验收标准和完成定义 |
| `10-open-decisions.md` | 尚未关闭的产品或技术决策 |
| `11-adr.md` | ADR 格式和决策记录 |
| `12-ui-ux-design.md` | UI/UX 契约、可访问性、响应式、locator 规则 |
| `13-security-and-compliance.md` | 安全需求、数据分类、威胁模型、合规和风险接受 |
