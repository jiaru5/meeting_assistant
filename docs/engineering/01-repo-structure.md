# 1. 仓库结构

本文件定义目标仓库结构和模块边界。项目初始化时应按本结构落地；已有代码存在时，agent 应优先对齐本结构，除非先更新工程规范。

## 目标结构

```text
.
├── AGENTS.md
├── docs/
│   ├── adoption/
│   ├── product-spec/
│   └── engineering/
├── frontend/
│   ├── apps/
│   │   └── web/
│   └── packages/
│       ├── api-client/
│       └── ui/
├── backend/
│   ├── services/
│   │   └── <service-name>/
│   └── libs/
│       ├── shared-kernel/
│       └── test-support/
├── platform/
│   ├── native-app/
│   ├── processing-cli/
│   ├── e2e/
│   └── infra/
├── harness/
│   ├── adoption-state.json
│   ├── project-manifest.json
│   └── agent-policy.json
├── scripts/
├── templates/
├── docker-compose.yml
├── docker-compose.test.yml
├── .env.example
└── .env.prod.example
```

## 前端模块边界

推荐单应用结构：

```text
frontend/apps/web/src/
├── app/
├── routes.tsx
├── features/
├── shared/
│   ├── api/
│   ├── components/
│   ├── lib/
│   ├── test/
│   └── theme/
└── main.tsx
```

规则：

1. 页面级路由表放在 `routes.tsx`，业务功能代码放在 `features/`。
2. API client、query key、通用 UI、日期工具和测试工具放在 `shared/`。
3. `features/` 可以依赖 `shared/`，`shared/` 不得依赖具体 feature。
4. 多前端应用共享 UI 时，提取到 `frontend/packages/ui/`。
5. 页面行为必须对齐 `docs/product-spec/04-user-journeys-and-ui.md`、`05-business-rules-and-calculations.md` 和 `12-ui-ux-design.md`。

## 后端微服务边界

推荐服务结构：

```text
backend/services/<service-name>/
├── Dockerfile
├── pom.xml
├── src/main/java/.../
│   ├── api/
│   ├── application/
│   ├── domain/
│   ├── persistence/
│   ├── security/
│   ├── config/
│   └── observability/
├── src/main/resources/
│   └── db/migration/
└── src/test/
```

规则：

1. `api/` 只处理 HTTP/message handler、request/response DTO、状态码和错误映射。
2. `application/` 承载用例、事务边界、权限校验、幂等、状态机编排和外部端口。
3. `domain/` 承载领域对象、枚举、策略和纯规则。
4. `persistence/` 承载 repository、数据库映射、查询实现和 outbox。
5. `security/` 承载当前主体、权限上下文和服务间身份适配。
6. `observability/` 承载 metrics、tracing、logging、health 和 readiness。
7. Flyway migration 放在服务自己的 `src/main/resources/db/migration/`。
8. 服务之间不能直接写对方数据库；跨服务交互通过 API、事件或明确的共享只读契约。

## 共享库边界

共享库只放真正跨服务稳定的能力：

1. 通用错误结构、request id、审计上下文。
2. 测试 fixture 或 contract test helper。
3. OpenTelemetry、日志、配置绑定等基础设施适配。

禁止把业务实体、服务用例或数据库访问封装到共享库中形成隐式单体。

## Docker 和基础设施

1. 所有部署都必须通过 Docker 镜像和 Docker Compose 或后续等价容器编排完成。
2. 本地开发默认使用 Docker Desktop。
3. `docker-compose.yml` 是本地集成入口，至少包含基础数据库；缓存、消息等中间件按 profile 启用。
4. `docker-compose.test.yml` 用于 CI 或本地集成测试隔离环境。
5. 宿主机 Node、Java、Maven 只能作为快速内循环工具，不能成为部署前提。
6. 数据库、中间件、队列、缓存、对象存储、邮件服务等必须作为容器服务启动。

## Platform skeleton 边界

`platform/` 中的组件注册、命令和 full-stack E2E 入口以 `harness/project-manifest.json` 为唯一工程事实源。本分卷只定义 platform skeleton 的目录职责和行为边界：

1. `platform/native-app/`：原生 app/helper 边界；非业务 skeleton 只能提供结构、门禁、architecture 和 SBOM 检查。
2. `platform/processing-cli/`：本地 processing/dependency-check/adapter 边界；非业务 skeleton 只能提供结构、门禁、architecture 和 SBOM 检查。
3. `platform/e2e/`：full-stack E2E 或 smoke E2E 的 compose 计划和清单接线检查。
4. `platform/infra/`：后续本地基础设施、部署清单和可观测性配置。

非业务 skeleton 不代表 `PV-MA-*` 产品行为已经覆盖。产品行为测试必须按 `docs/engineering/06-product-validation-matrix.md` 推进；实现真实能力时同步更新组件测试、E2E 和 manifest 命令。

## 脚本归属

`scripts/` 用于放可重复执行的工程入口。脚本必须：

1. 可从仓库根目录运行。
2. 失败时返回非 0 exit code。
3. 输出关键检查结论。
4. 不读取未声明的本机私有路径。
5. 不把 secret 写入日志。

## Adoption 工作区

`docs/adoption/` 只用于 greenfield 项目启动和需求澄清，包含：

1. `INITIAL-REQUEST.md`：原始初始意向。
2. `DISCOVERY-LEDGER.md`：问答、假设、冲突和转写记录。
3. `SPEC-READINESS.md`：进入 project 模式前的逐章 readiness。

该目录不是产品事实源。Agent 只能把用户确认后的内容转写到 `docs/product-spec/`、ADR、open decisions、validation matrix 或 manifest 后再实现。

## Harness 机器配置

1. `harness/project-manifest.json` 是组件、质量命令、全栈 E2E、供应链目标和生产就绪工件的注册表。
2. `harness/agent-policy.json` 是 Agent 文件、网络、凭据、外部写入和人工审批的最小权限策略。
3. `harness/adoption-state.json` 记录 adoption subphase 和显式 activation 确认，不声明当前 mode。
4. 这些文件都属于工程事实，不承载业务模型；产品安全事实仍归 `docs/product-spec/13-security-and-compliance.md`。
5. project 模式不允许存在未注册的 `frontend/apps/*/package.json`、`backend/services/*/pom.xml` 或 `platform/*/component.json`。
6. release 不允许通过目录自动发现后静默跳过；缺少注册目标必须失败。
