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
./scripts/product-validation-check.py current-phase
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
./scripts/phase-preflight.sh
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
| `product-validation-check.py` | 按 `current-phase` 或 `release` 检查验证矩阵状态；当前阶段允许有 documented `partial/planned`，release 要求全部 `PV-*` 为 `covered` |
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
| `phase-preflight.sh` | 阶段收口入口：验证当前阶段矩阵状态、运行 `check.sh`、full-stack E2E 和 evidence review |
| `release-preflight.sh` | 发布候选总入口：release blocker、验证矩阵、open decisions、生成物和全量门禁 |

在 `framework` 或 `adoption` 模式且尚未创建实际组件时，应用命令可以明确跳过。进入 `project` 模式后，任何未注册组件或缺少 lint、test、build、architecture、security、SBOM、E2E 命令的情况必须失败。

## Meeting Assistant 组件命令事实归属

`harness/project-manifest.json` 是当前组件、组件路径、命令 argv 和 full-stack E2E smoke 入口的唯一工程注册表。本分卷只定义命令类型、fail-closed 规则和 skeleton 行为边界，不复制可独立维护的组件命令清单。

full-stack E2E 可在 manifest 中声明可选 `pre_start_command`，用于准备本地 smoke runtime、预加载镜像或检查外部依赖。该命令必须是 argv 数组，失败时阻断 E2E；不得在 E2E 执行阶段静默拉取未声明的外部镜像或依赖。

`./scripts/test-e2e-full-stack.sh` 本地默认设置 `MEETING_ASSISTANT_SMOKE_IMAGE=meeting-assistant-smoke:local`，由 `platform/e2e/prepare-smoke-image.sh` 验证或从已缓存允许镜像 tag 出本地 smoke image；脚本仍不得自动 pull。`platform/e2e/docker-compose.smoke.yml` 的默认镜像值必须保持 digest-pinned，以满足 release manifest 静态门禁；本地开发如需使用其他已预加载镜像，只能通过显式环境变量覆盖。

已注册的非业务 skeleton 只能承载未来原生录制控制面、本地 processing、dependency-check、artifact contract、transcription adapter、speaker-label fallback 和 export 命令边界。

注册组件必须提供 argv 形式的标准命令：

1. `lint`
2. `test`
3. `build`
4. `architecture`
5. `security`
6. `sbom`

非业务 skeleton 命令只验证结构、边界、SBOM 占位和清单接线，不证明任何产品行为已经实现。后续在 skeleton 中实现真实录制、真实媒体处理、真实转写、真实 speaker labeling、外部模型调用或依赖下载前，必须先对齐 product-spec、验证矩阵、组件测试和安全/供应链规则。

`platform/native-app/scripts/test.sh` 默认运行快速、确定性的 native-app 组件测试入口：component metadata 检查、Swift Testing 和 XCTest-hosted SwiftUI smoke。真实 `.app` 启动的 app-bundle XCUITest 因依赖 Xcode UI automation 和窗口前台状态，默认不进入本地快速 `test` gate；需要完整 native UI 证据时运行 `./platform/native-app/scripts/test-app-bundle.sh`，或设置 `MA_NATIVE_APP_RUN_XCUITEST=1 ./platform/native-app/scripts/test.sh`。`test-app-bundle.sh` 默认使用 `platform/native-app/build/DerivedData/AppBundleUITests` 下的忽略目录复用 Xcode DerivedData；如需一次性隔离构建，可用 `MA_NATIVE_APP_DERIVED_DATA_PATH` 指向临时目录。native UI、release-scope 或阶段收口证据不得只引用默认 skip 输出，必须明确记录 app-bundle XCUITest 命令。

未来 dependency-check 命令必须只检查允许来源、人工安装状态、模型/runtime 路径、workspace 可写性和 macOS 权限状态，不得自动下载模型、二进制或驱动。

## 本机 Whisper Runtime Smoke 环境

VS-MA-06 的真实 `whisper.cpp` smoke 依赖用户人工准备的本机 runtime、multilingual 模型和中英混合小样例音频。当前本机已采用 shell profile 方式持久化以下环境变量：`~/.zshrc` 中的 `meeting_assistant whisper.cpp smoke runtime` 标记块导出 `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME`、`MEETING_ASSISTANT_TRANSCRIPTION_MODEL` 和 `MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO`。

当前本机配置如下：

```bash
export MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME="$HOME/.local/bin/whisper-cli"
export MEETING_ASSISTANT_TRANSCRIPTION_MODEL="$HOME/.local/share/ai-models/whisper.cpp/large-v3-turbo/ggml-large-v3-turbo-q5_0.bin"
export MEETING_ASSISTANT_WHISPER_SMOKE_AUDIO="$HOME/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav"
```

这三项只记录本地路径，不包含 secret。它们用于让 `platform/processing-cli/scripts/smoke-whisper-cpp.sh` 和 `./scripts/check.sh` 在本机默认进入真实 smoke，而不是报告 `runtime/model env is not configured`。该配置不改变 `06-api-contracts.md` 的边界：应用和脚本仍不得自动下载模型、二进制或驱动，也不得把推荐目录当成自动发现机制；真实 runtime 仍由上述 env 显式指定。

如果后续改用 `direnv`，项目根目录的等价 `.envrc` 内容应保持为同一组三个 export，并在执行 `direnv allow` 前由开发者人工确认路径存在。未安装 `direnv` 的环境继续使用 shell profile 方案。

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
