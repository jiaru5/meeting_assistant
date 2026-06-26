# 7. 开发计划

本文件定义 starter 落地计划、阶段门禁和演进路线。它是工程执行计划，不是产品事实源。

## 文件边界

1. 产品模型、字段、枚举、权限、API、事件、数据库语义、页面行为、验收标准和 ADR 以 `docs/product-spec/` 的主责分卷为准。
2. 工程结构、命令、测试策略、审查门禁、验证矩阵和服务标准以 `docs/engineering/` 的主责分卷为准。
3. 本文件只定义如何分阶段完成实现和交付门禁。

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

## Phase 2: 最小纵切实现

目标：

1. 实现一个前端页面、一个后端服务、一个持久化对象和一条端到端用户路径。
2. 接入 lint、unit、integration、API contract 和组件测试。
3. 建立 Docker Compose 下的本地集成运行。

退出标准：

1. `./scripts/check.sh` 通过；project 模式不允许跳过已要求的组件门禁。
2. 纵切行为的验证矩阵行达到 `covered`。
3. review report 能列出真实改动面和验证证据。
4. full-stack E2E 能实际启动 Compose、等待健康检查、seed、验证和清理。

## Phase 3: 微服务扩展

目标：

1. 按 bounded context 拆分服务。
2. 明确服务数据所有权和跨服务契约。
3. 接入异步事件、outbox、消息契约测试和消费者幂等。

退出标准：

1. 服务不能直接写其他服务数据库。
2. API 和事件 schema 纳入版本化契约管理。
3. 异步失败、重试、dead-letter 和补偿路径有测试或运行手册。

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
