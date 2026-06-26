# 工程执行规范

本目录定义工程执行规则，用于支持 AI agent 高度自主地完成设计、开发、审查、测试、集成和交付。

`docs/product-spec/` 是产品模型、权限、API、数据、事件、页面行为、计算规则和验收标准的唯一事实源。本目录只定义工程组织方式、命令、测试策略、审查门禁和 agent 工作流，不能覆盖或改写产品事实。

技术栈和应用实现边界以 `docs/product-spec/08-implementation-guidance.md` 为准。本目录说明这些技术如何在仓库结构、脚本、测试和 CI 中落地。

## 工程事实归属

| 主题 | 主责分卷 |
|---|---|
| 仓库结构、模块边界、脚本归属 | `01-repo-structure.md` |
| Docker 优先的开发、测试、构建和数据库命令 | `02-dev-commands.md` |
| 测试分层、测试数据、最小验证要求 | `03-test-strategy.md` |
| 审查清单、CI 门禁、交付说明 | `04-review-and-ci-gates.md` |
| AI agent 自主执行流程、多 agent 协同和停顿边界 | `05-agent-operating-model.md` |
| 产品规范到自动化验证的覆盖状态 | `06-product-validation-matrix.md` |
| Starter 落地计划、阶段门禁和演进路线 | `07-development-plan.md` |
| 微服务标准、配置、可观测性和韧性要求 | `08-service-standards.md` |
| 新 AI agent 接手和项目转写步骤 | `09-starter-adoption-guide.md` |
| 安全开发、依赖、制品和供应链 | `10-security-and-supply-chain.md` |
| SLO、发布、恢复和生产准备 | `11-production-readiness.md` |
| Agent 权限、工具、MCP 和非可信输入 | `12-agent-security.md` |
| Harness 自测试和 Agent 行为评测 | `13-harness-evaluation.md` |
| Greenfield 新项目启动、初始需求写入和 Agent 启动 prompt | `14-greenfield-project-start.md` |

## 分卷索引

| 文件 | 覆盖内容 |
|---|---|
| `01-repo-structure.md` | 目标仓库结构、模块边界、文件归属 |
| `02-dev-commands.md` | Docker 优先的本地开发、测试、构建和数据库命令 |
| `03-test-strategy.md` | 测试分层、验收标准到测试类型的映射、测试数据规则 |
| `04-review-and-ci-gates.md` | 审查清单、CI 门禁、合并前要求 |
| `05-agent-operating-model.md` | AI agent 自主执行流程、多 agent 协同、上下文管理、何时停下来确认 |
| `06-product-validation-matrix.md` | 产品规范到自动化验证的覆盖矩阵、状态定义和完成标准 |
| `07-development-plan.md` | starter 初始化、业务落地、服务拆分和发布阶段计划 |
| `08-service-standards.md` | 微服务通用标准：API、事件、配置、安全、观测、韧性 |
| `09-starter-adoption-guide.md` | 分步骤指导新 AI agent 将 starter 转写为特定项目框架和唯一事实源 |
| `10-security-and-supply-chain.md` | 安全开发、扫描、依赖、SBOM、签名、provenance 和漏洞响应 |
| `11-production-readiness.md` | SLO、容量、发布、回滚、备份恢复、事故响应和生产审查 |
| `12-agent-security.md` | AI coding agent 的权限、信任边界、工具和审批规则 |
| `13-harness-evaluation.md` | Harness fail-closed 自测试和 Agent 行为评测 |
| `14-greenfield-project-start.md` | 从 starter 启动全新项目的实际步骤、初始需求写入位置和 Agent prompts |

## 使用方式

1. 实现任务先读 `AGENTS.md`、`docs/product-spec/README.md` 和本文件。
2. 依据任务类型读取本目录下相关工程分卷。
3. 如果工程规范与产品规范冲突，以 `docs/product-spec/` 为准，并按变更流程处理。
4. 新增工程命令、目录、测试门禁或 Docker 部署约定时，先更新本目录。
5. 新增产品模型、权限、API、数据库、事件或页面行为时，先更新 `docs/product-spec/`。
