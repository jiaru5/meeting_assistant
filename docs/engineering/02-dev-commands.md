# 2. 开发命令

本文件定义 agent 和研发人员优先使用的标准命令。项目初始化后必须把真实前端、后端和服务命令接入这些入口；在具体服务尚未创建前，脚本应明确跳过而不是假装成功执行应用测试。

所有部署使用 Docker。数据库和中间件只能通过 Docker、Docker Compose、Testcontainers 或等价容器机制启动，不能在宿主机部署或启动。

## 标准入口

所有脚本从仓库根目录执行：

```bash
./scripts/bootstrap.sh
./scripts/start-project.sh
./scripts/adoption-status.sh
./scripts/adoption-check.sh
./scripts/activate-project.sh
./scripts/project-manifest-check.sh
./scripts/harness-self-test.sh
./scripts/compose-check.sh
./scripts/dev-up.sh
./scripts/dev-down.sh
./scripts/db-migration-check.sh
./scripts/prod-config-check.sh
./scripts/spec-sync-check.sh
./scripts/agent-workflow-check.sh
./scripts/architecture-check.sh
./scripts/security-check.sh
./scripts/supply-chain-check.sh
./scripts/production-readiness-check.sh
./scripts/review-report.sh
./scripts/lint.sh
./scripts/test.sh
./scripts/test-e2e.sh
./scripts/test-e2e-full-stack.sh
./scripts/build.sh
./scripts/check.sh
./scripts/release-preflight.sh
```

| 命令 | 要求 |
|---|---|
| `bootstrap.sh` | 检查基础工具、提示复制 `.env.example`、验证文档和脚本入口 |
| `start-project.sh` | 将新 clone 从 `framework` 初始化为 `adoption`，创建/确认 adoption 工作区并写入项目名和 owner |
| `adoption-status.sh` | 汇总 adoption subphase、当前 blocker 和 activation 缺口 |
| `adoption-check.sh` | 校验 adoption 工作区、初始需求和 spec readiness；`--activation` 阻断未确认或不完整事实源 |
| `activate-project.sh` | 在用户明确批准后切换到 `project` 并运行 activation 门禁；失败时回滚到 `adoption` |
| `project-manifest-check.sh` | 验证项目阶段、组件注册、Agent 策略和发布必需工件 |
| `harness-self-test.sh` | 验证 fail-closed、未注册组件和最小权限策略 |
| `compose-check.sh` | 验证本地和测试 Compose 配置可以解析 |
| `dev-up.sh` | 使用 Docker Compose 启动本地集成依赖和已接入的服务 |
| `dev-down.sh` | 停止本地集成环境，默认不删除数据卷 |
| `db-migration-check.sh` | 对每个已接入服务验证 migration 可从空库执行 |
| `prod-config-check.sh` | 检查生产 env 示例、默认 secret、profile 和 dev-only 配置隔离 |
| `spec-sync-check.sh` | 检查产品表面改动是否同步事实源和验证矩阵 |
| `agent-workflow-check.sh` | 检查本次 diff 是否同步了必要 spec、测试、验证矩阵和工程规范 |
| `architecture-check.sh` | 执行每个注册组件的结构和依赖边界测试 |
| `security-check.sh` | 执行 secret、Action pin 和组件安全扫描 |
| `supply-chain-check.sh` | 验证依赖/Action 固定，发布阶段生成 SBOM 并校验供应链要求 |
| `production-readiness-check.sh` | 阻断非 project、缺少 E2E、生产工件或发布策略的候选版本 |
| `review-report.sh` | 根据当前 diff 生成交付审查摘要 |
| `lint.sh` | 运行已接入前端、后端和脚本 lint |
| `test.sh` | 运行已接入单元、集成和组件测试 |
| `test-e2e.sh` | 使用 Playwright 运行前端 mocked E2E |
| `test-e2e-full-stack.sh` | 启动真实 Compose 环境并运行 full-stack E2E |
| `build.sh` | 构建前端、后端服务和 Docker 镜像 |
| `check.sh` | 合并前总入口：workflow、prod config、migration、lint、test、build |
| `release-preflight.sh` | 发布候选总入口：release blocker、验证矩阵、open decisions、生成物和全量门禁 |

在 `framework` 或 `adoption` 模式且尚未创建实际组件时，应用命令可以明确跳过。进入 `project` 模式后，任何未注册组件或缺少 lint、test、build、architecture、security、SBOM、E2E 命令的情况必须失败。

## Meeting Assistant activation 组件命令

`meeting_assistant` activation 前允许创建的最小非业务骨架为：

1. `native-app`：非业务 activation skeleton，用于承载未来原生录制控制面、权限提示和 UI 状态测试边界。
2. `processing-cli`：非业务 activation skeleton，用于承载未来本地 processing、dependency-check、artifact contract、transcription adapter、speaker-label fallback 和 export 命令边界。

这些骨架已经以 `platform` 类型注册到 `harness/project-manifest.json`，并提供 argv 形式的 `lint`、`test`、`build`、`architecture`、`security` 和 `sbom` 命令：

| Component | Gate | Command |
|---|---|---|
| `native-app` | lint | `platform/native-app/scripts/lint.sh` |
| `native-app` | test | `platform/native-app/scripts/test.sh` |
| `native-app` | build | `platform/native-app/scripts/build.sh` |
| `native-app` | architecture | `platform/native-app/scripts/architecture.sh` |
| `native-app` | security | `platform/native-app/scripts/security.sh` |
| `native-app` | sbom | `platform/native-app/scripts/sbom.sh` |
| `processing-cli` | lint | `platform/processing-cli/scripts/lint.sh` |
| `processing-cli` | test | `platform/processing-cli/scripts/test.sh` |
| `processing-cli` | build | `platform/processing-cli/scripts/build.sh` |
| `processing-cli` | architecture | `platform/processing-cli/scripts/architecture.sh` |
| `processing-cli` | security | `platform/processing-cli/scripts/security.sh` |
| `processing-cli` | sbom | `platform/processing-cli/scripts/sbom.sh` |
| `full-stack-e2e` | smoke | `platform/e2e/smoke-test.sh` |

这些命令只验证 activation skeleton 的结构、边界、SBOM 占位和清单接线，不证明任何产品行为已经实现。骨架不得在 adoption 模式实现真实录制、真实媒体处理、真实转写、真实 speaker labeling、外部模型调用或自动依赖下载。

未来 dependency-check 命令必须只检查允许来源、人工安装状态、模型/runtime 路径、workspace 可写性和 macOS 权限状态，不得自动下载模型、二进制或驱动。

## 项目清单

每个真实组件在 `harness/project-manifest.json` 中注册。命令必须是 argv 数组，不接受 shell 字符串：

```json
{
  "id": "example-service",
  "type": "backend",
  "path": "backend/services/example-service",
  "production": true,
  "requires_migrations": true,
  "architecture_test": "backend/services/example-service/src/test/java/.../ArchitectureTest.java",
  "dockerfile": "backend/services/example-service/Dockerfile",
  "commands": {
    "lint": ["./mvnw", "-DskipTests", "verify"],
    "test": ["./mvnw", "test"],
    "build": ["./mvnw", "-DskipTests", "package"],
    "architecture": ["./mvnw", "-Dtest=ArchitectureTest", "test"],
    "security": ["./mvnw", "org.owasp:dependency-check-maven:check"],
    "migration": ["./mvnw", "-Pmigration-check", "verify"],
    "sbom": ["./mvnw", "org.cyclonedx:cyclonedx-maven-plugin:makeAggregateBom"]
  }
}
```

## Docker Compose

本地依赖：

```bash
docker compose up --detach postgres
docker compose --profile cache up --detach redis
docker compose --profile messaging up --detach kafka
docker compose down
```

测试隔离环境：

```bash
docker compose -f docker-compose.yml -f docker-compose.test.yml up --detach postgres
docker compose -f docker-compose.yml -f docker-compose.test.yml down -v
```

规则：

1. `.env.example` 只用于本地开发。
2. `.env.prod.example` 只提供变量清单，不提供真实 secret。
3. `docker-compose.test.yml` 必须可重建，不依赖本地持久数据。
4. 容器内服务必须暴露健康检查，方便脚本等待依赖就绪。

## 前端命令约定

每个前端应用应提供：

```bash
npm run dev
npm run lint
npm run test
npm run test:run
npm run test:e2e
npm run build
```

`scripts/` 中的标准脚本应发现 `frontend/apps/*/package.json` 并逐个执行对应命令。

## 后端命令约定

每个 Java/Spring Boot 服务应使用 Maven wrapper 或仓库级 Maven wrapper，并提供：

```bash
./mvnw test
./mvnw verify
./mvnw spring-boot:run
```

数据库相关测试必须使用 Testcontainers、Docker Compose 或测试进程内受控依赖，不能依赖宿主机数据库。

## Agent 使用规则

1. 改动前先检查脚本和真实项目文件是否存在。
2. 有脚本时优先运行脚本，不绕过标准入口。
3. 没有具体服务代码时，在最终回复中说明对应应用验证尚未接入。
4. 修改代码后至少运行与改动相关的最小验证；跨模块或发布前改动运行 `./scripts/check.sh`。
5. 修改 Dockerfile、compose、环境变量或 profile 后，运行 Docker 相关验证或说明无法运行原因。
6. 非平凡改动必须先通过 `./scripts/agent-workflow-check.sh`。
7. 交付前运行 `./scripts/review-report.sh`，把生成内容作为 PR 或最终回复中的审查证据来源。
8. `./scripts/check.sh` 会把命令、commit、退出码和日志写入 `.harness/evidence/`；发布前 `review-report.sh --require-evidence` 必须验证这些证据。
9. 在 `adoption` 模式下优先运行 `./scripts/adoption-status.sh` 和 `./scripts/adoption-check.sh`，不要运行会创建业务实现的命令。
