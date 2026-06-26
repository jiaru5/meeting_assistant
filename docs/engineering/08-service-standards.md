# 8. 服务标准

本文件定义微服务通用工程标准：API、事件、配置、安全、可观测性、韧性、数据和运行。

## 服务准入

新增服务前必须明确：

1. 所属 bounded context。
2. 拥有的数据表、集合或 topic。
3. 对外 API 和事件契约。
4. 依赖的上游和下游。
5. 权限模型和审计要求。
6. 健康检查、指标、日志和 trace。
7. 本地、测试和生产配置。
8. `harness/project-manifest.json` 中的组件、命令、架构测试和制品信息。

## API 标准

1. 所有 API 必须有 request id 和稳定错误结构。
2. 写入 API 必须有 validation、权限、幂等或冲突策略。
3. 跨服务同步调用必须设置 timeout。
4. 高风险调用必须有 retry policy、circuit breaker 或降级策略。
5. OpenAPI 或等价 contract 必须纳入版本控制。

## 事件标准

1. 事件名包含语义版本，例如 `entity.changed.v1`。
2. 事件 payload 必须包含 `event_id`、`occurred_at`、producer、trace context 和必要业务键。
3. Producer 使用 outbox 或等价机制避免本地事务与消息发送不一致。
4. Consumer 必须幂等，能处理重复、乱序和延迟消息。
5. Dead-letter 和重放策略必须有运行手册。

## 配置标准

1. dev、test、prod profile 分离。
2. 生产 secret 不写入仓库、镜像或日志。
3. 启动时 fail fast 检查关键配置。
4. 配置项必须有默认值策略和文档。
5. Dev-only 身份、固定 clock、mock 依赖不能在 prod profile 生效。

## 可观测性标准

1. 结构化日志包含 timestamp、level、service、request_id、trace_id、actor 摘要和 error code。
2. 不记录 password、token、secret、完整敏感 payload 或个人敏感明文。
3. HTTP、数据库、消息、外部调用和关键业务命令都有 metrics。
4. trace 跨前端、gateway、服务和消息消费者传播。
5. 健康检查区分 liveness 和 readiness。

## 韧性标准

1. 外部调用默认有 timeout。
2. 可重试错误和不可重试错误明确区分。
3. 重试必须有上限、退避和幂等保护。
4. 批处理和消费者必须支持 checkpoint 或幂等重放。
5. 降级策略不能扩大权限或绕过审计。

## 数据标准

1. 每个服务拥有自己的写模型。
2. 跨服务查询优先通过 API、事件投影或只读 read model。
3. 共享数据库只作为过渡方案，必须有 ADR 和退出计划。
4. Migration 必须可从空库执行，并能在共享环境中前向演进。
5. 生产数据修复必须 dry-run、审计和可回滚。

## 架构门禁

1. 后端服务必须使用 ArchUnit 或等价结构测试验证 api、application、domain、persistence 和 security 的依赖方向。
2. 前端应用必须使用 ESLint boundaries、dependency-cruiser 或等价工具验证 feature/shared 和跨包依赖。
3. 架构约束必须通过组件 `architecture` 命令纳入 `./scripts/architecture-check.sh`。
4. 禁止只在文档中声明层级而没有可执行测试。

## 生产准入

1. 每个生产服务必须有 digest-pinned 基础镜像和非 root runtime user。
2. 每个生产服务必须生成 SBOM，并可追溯到 commit 和制品 digest。
3. 每个生产服务必须有 SLO、runbook、rollback 和恢复路径。
4. 服务不能因依赖故障绕过认证、权限或审计。
