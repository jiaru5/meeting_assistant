# 3. 测试策略

本文件定义测试分层、测试数据规则和验收标准到测试类型的映射。产品级覆盖状态见 `06-product-validation-matrix.md`。

## 测试分层

| 层级 | 工具 | 覆盖重点 |
|---|---|---|
| 后端单元测试 | JUnit 5 或等价工具 | 领域规则、状态机、权限判断、计算函数 |
| 后端集成测试 | Spring Boot Test、Testcontainers、PostgreSQL | repository、事务、migration、权限、API 行为 |
| API 合约测试 | MockMvc、OpenAPI validator 或 Pact | 路径、状态码、request/response schema、错误响应 |
| 消息契约测试 | AsyncAPI、schema registry mock 或 contract tests | 事件 schema、幂等、消费者兼容性 |
| 前端组件测试 | Vitest、React Testing Library | 表格、筛选、空状态、权限状态、表单校验 |
| Mocked E2E | Playwright | 前端路由、布局、权限态和关键交互回归 |
| Full-stack E2E | Playwright、Docker Compose | 真实 frontend/backend/database 用户路径和 API 集成 |
| Docker 构建测试 | Docker Build、Docker Compose | 镜像可构建、容器可启动、健康检查可通过 |
| 可观测性测试 | integration tests、log assertions | request id、metrics、traces、健康检查 |
| 架构结构测试 | ArchUnit、dependency-cruiser 或等价工具 | 层级依赖、跨域访问、禁止边 |
| Harness 自测试 | Python unittest、shell | 生命周期、清单、权限、fail-closed |
| Adoption 生命周期测试 | Python unittest、shell | 初始需求空缺、假设未确认、readiness blocker、无确认激活、project 切换回滚 |
| 安全测试 | SAST、SCA、secret、IaC/container scan、DAST | 漏洞和供应链风险 |

## Meeting Assistant 测试分层

Phase 1 是本地 macOS 工具，不以 Web 前端、远程 HTTP API 或数据库作为默认纵切。当前项目的测试映射是：

| 层级 | 工具 | 覆盖重点 |
|---|---|---|
| Processing CLI 单元测试 | Python unittest 或后续等价工具 | 本地命令响应、错误码、dependency-check、artifact contract、adapter fake |
| 本地命令契约测试 | JSON schema/assertions | `CMD-MA-*` 输入、输出、错误 code 和 fail-fast 行为 |
| Native app 状态测试 | Swift Testing | Swift/SwiftUI view model、权限/依赖状态、录制状态转换 |
| Native UI smoke | XCUITest | 开始/停止、权限缺失、录制中、失败/降级、导出入口和 accessible locator |
| 本地文件契约测试 | Python/Swift 测试 | `session.json`、artifact registry、原始媒体保护、派生产物重试 |
| Smoke E2E | manifest 驱动脚本 | `native-app` + `processing-cli` + workspace fixture 的受控端到端路径 |

Playwright 只在后续引入 Web UI 时作为 Web mocked/full-stack E2E 工具；当前 native macOS UI 自动化优先使用 Swift Testing 和 XCUITest。

`platform/native-app/Sources/`、`platform/native-app/Tests/`、`platform/native-app/UITests/`、`platform/processing-cli/src/`、`platform/processing-cli/tests/` 和 `platform/e2e/` 是当前产品行为和产品验证的主要代码表面。修改这些路径时，工程门禁必须要求同步检查 `06-product-validation-matrix.md`，并运行对应组件测试、架构检查和 local full-stack smoke。Local full-stack smoke 必须优先使用已缓存或预加载的本地 smoke 镜像，不得在 E2E 执行阶段隐式依赖公网 registry 拉取。

## Meeting Assistant 自动化测试前置条件

任何 `CMD-MA-*`、artifact contract、native UI 状态或 processing pipeline 的产品行为实现开始前，必须先满足以下 testability 前置条件。缺少前置条件时，只能做规范补齐、测试基础设施或 spike，不能把对应产品行为标为实现完成。

| 前置条件 | 最低要求 | 不满足时的处理 |
|---|---|---|
| 命令 schema | `06-api-contracts.md` 已定义目标命令的输入、成功响应关键字段、失败响应关键字段、错误码、unknown field fail-fast 和 exit code；测试能断言 JSON object，而不是只看 stdout 字符串 | 先补 API 契约和本地命令契约测试；相关 `PV-MA-*` 保持 `planned` 或 `partial` |
| Artifact schema | `07-data-and-events.md` 已定义 `session.json`、artifact registry、`transcript.json`、`speaker_labels.json` 或 delete summary 的最小字段和路径边界 | 先补文件契约测试和 fixture；不得通过 ad hoc 文件内容判断产品完成 |
| 确定性 fixture | 测试使用临时 workspace、受控 clock 或可断言时间格式、小型媒体 fixture、fake adapter 和固定依赖状态；不得依赖用户真实会议数据或本机常驻服务 | 先补 fixture/fake adapter；真实 runtime smoke 只能作为附加证据 |
| UI locator | SwiftUI 控件和状态有 accessible name、状态文本和稳定 accessibility identifier；测试可定位权限、依赖、录制、处理、回查、导出和删除状态 | 先补 view model、locator 和 XCUITest/Swift Testing 基础；不能只以人工截图作为长期证据 |
| 负向用例 | 至少覆盖 unknown field、非法 enum、缺失必填字段、权限缺失、依赖缺失、artifact 缺失、路径越界、symlink 逃逸、处理失败、导出冲突、确认缺失、no-auto-upload 和 no-auto-download | 先补负向测试；未覆盖的高风险边界必须写入验证矩阵缺口 |
| 证据入口 | `06-product-validation-matrix.md` 必须写明目标测试文件或脚本、标准命令入口、当前证据、阻塞缺口和关闭条件 | 不能只写“未来测试”；缺少目标入口时不能标 `covered`，也不应扩大产品实现范围 |

`docs/engineering/07-development-plan.md` 的 `TDG-MA-*` testability gate 是这些前置条件的执行清单。实现 agent 必须在相关 `VS-MA-*` 开始和退出时检查该清单，验证 agent 必须按验证矩阵中的目标入口确认关闭状态。

## 验收标准映射

| 规范来源 | 必须覆盖的测试 |
|---|---|
| `09-acceptance-criteria.md` 身份和权限 | 后端权限测试、API 合约测试、前端权限状态测试、E2E |
| `02-domain-model.md` 领域不变量 | 后端单元、集成、数据库约束测试 |
| `05-business-rules-and-calculations.md` | 后端单元和集成测试，必要时加前端展示测试 |
| `06-api-contracts.md` | API 合约测试、前端 API client 测试 |
| `07-data-and-events.md` | migration、repository、事件契约、消费者幂等测试 |
| `12-ui-ux-design.md` | 前端组件测试、Playwright E2E、视觉和可访问性检查 |
| `12-ui-ux-design.md` 的原生 macOS UI | Swift Testing、XCUITest、可访问性 locator 检查 |

## 高风险边界

以下情况必须有自动化测试：

1. 未登录、登录过期、无权限和跨租户访问。
2. 服务端维护字段不能由客户端写入。
3. 同租户或跨域引用校验。
4. 状态机迁移、并发冲突和幂等重试。
5. migration 从空库启动成功。
6. 异步消息重复、乱序、失败和补偿。
7. 生产 profile 不接受 dev-only 身份、默认 secret 或固定测试数据。
8. 前端关键页面的 loading、empty、error、forbidden 和 submitting 状态。
9. 架构边界、禁止依赖和跨服务数据访问。
10. Agent 权限放宽、门禁绕过、未注册组件和发布假绿灯。
11. Meeting Assistant 命令 unknown field、非法 enum、缺失必填字段和 CLI exit code。
12. Meeting Assistant workspace 路径越界、symlink 逃逸、delete session 误删和 workspace 外导出保留。
13. Meeting Assistant 外部 GPT/API、依赖下载、辅助 capture adapter 静默切换等禁止路径。

## 测试数据

1. 测试数据必须确定性生成，不依赖当前真实日期，除非测试显式控制 clock。
2. 至少准备两个租户或隔离域，用于数据隔离测试。
3. 至少准备普通用户、管理员、无权限用户和 inactive/disabled 用户。
4. E2E seed 只维护全栈路径所需的最小稳定 fixture。
5. dev seed 可以更丰富，但不得成为产品事实源。
6. 集成测试和 E2E 使用的数据库、中间件和外部依赖模拟服务必须由 Docker Compose、Testcontainers 或测试进程内 mock 提供。

## 最低测试要求

1. 修改领域模型、权限、API、事件或计算规则时，必须有后端单元、集成或契约测试。
2. 修改页面、表单、筛选、表格列时，必须有前端组件测试；关键路径加 Playwright E2E。
3. 修改 Docker 或启动流程时，必须验证镜像构建和 Compose 启动。
4. 修改 migration 或数据库启动流程时，必须运行 `./scripts/db-migration-check.sh`。
5. 修改生产 profile、secret 或 env 示例时，必须运行 `./scripts/prod-config-check.sh`。
6. 修复 bug 时，优先补能失败的回归测试，再修复。
7. 新增或修改产品行为时，必须同步检查 `06-product-validation-matrix.md`。
8. 新增组件时，必须先注册 `harness/project-manifest.json` 并提供架构测试。
9. 修改 Harness 生命周期、安全策略或发布门禁时，必须补 `scripts/tests/` 的失败路径测试。
10. 发布候选的 full-stack E2E 必须实际启动 Compose 服务并等待健康检查，不能只执行 `docker compose config`。
11. 修改 adoption 流程、启动脚本、readiness 规则或 project activation 时，必须补 `scripts/tests/` 的失败路径测试，并运行 `./scripts/adoption-check.sh`。
12. 修改 `processing-cli` 命令契约、dependency-check 或 artifact contract 时，必须补本地命令契约测试，并更新 `06-product-validation-matrix.md`。
13. 修改 `native-app` SwiftUI 状态、权限提示或录制控制时，必须补 Swift Testing；关键用户状态补 XCUITest 或说明短期 manual-evidence。
