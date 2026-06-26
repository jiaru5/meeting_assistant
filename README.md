# Meeting Assistant Harness

本仓库是 `meeting_assistant` 项目的 AI agentic coding 工作区。产品和应用技术事实写入 `docs/product-spec/`，工程执行规则写入 `docs/engineering/`；当前模式只由 `docs/product-spec/PROJECT-STATUS.md` 声明。

本文件只是仓库入口说明，不是产品或工程事实源。若本文件与 `docs/product-spec/`、`docs/engineering/`、`harness/project-manifest.json` 或 `harness/agent-policy.json` 冲突，以主责事实源为准。

## 事实源模型

本项目保留的核心事实源模型是：

1. `AGENTS.md` 作为 agent 入口和工作协议。
2. `docs/product-spec/` 作为产品、领域、权限、API、数据、页面、验收标准和 ADR 的事实源目录。
3. `docs/engineering/` 作为工程执行事实源目录。
4. `docs/engineering/06-product-validation-matrix.md` 将规范条目映射到验证证据。
5. `docs/adoption/` 保留为非事实源的 adoption 审计工作区，用于原始意向、问答、假设和 readiness 记录。
6. `scripts/` 将规范同步、adoption 检查、审查报告、CI 门禁和发布预检产品化。
7. Docker 优先，数据库和中间件不依赖宿主机常驻服务。
8. `harness/project-manifest.json` 让组件、质量命令、E2E 和生产工件可执行校验。
9. `harness/agent-policy.json` 固定 Agent 最小权限、非可信输入和人工审批边界。
10. 安全、供应链、生产就绪和 Harness 自测试是发布门禁的一部分。

## 目录

```text
.
├── AGENTS.md
├── docs/
│   ├── adoption/
│   ├── product-spec/
│   └── engineering/
├── frontend/
├── backend/
├── platform/
├── harness/
├── scripts/
├── templates/
├── docker-compose.yml
├── docker-compose.test.yml
├── .env.example
└── .env.prod.example
```

## 使用方式

新 AI agent 接手时，先读：

```text
AGENTS.md
docs/product-spec/PROJECT-STATUS.md
docs/product-spec/README.md
docs/engineering/README.md
```

推荐顺序：

1. 读取 `docs/product-spec/PROJECT-STATUS.md`，确认 `framework`、`adoption` 或 `project` 模式。
2. 如果模式允许实现，从 `docs/product-spec/README.md` 和 `docs/engineering/README.md` 定位主责分卷。
3. 每个需求先判断 `spec-change`、`spec-covered` 或 `no-product-impact`。
4. 对照 `docs/engineering/06-product-validation-matrix.md` 找到对应 `PV-MA-*` 行。
5. 实现时按 `harness/project-manifest.json` 注册组件和命令，不依赖目录猜测。
6. 交付前运行最小充分验证、`./scripts/agent-workflow-check.sh` 和 `./scripts/review-report.sh`。

从 starter 启动全新项目或重走 adoption 流程时，再使用 `docs/engineering/09-starter-adoption-guide.md` 和 `docs/engineering/14-greenfield-project-start.md`。

## 快速校验

```bash
./scripts/docs-check.sh
./scripts/adoption-check.sh
./scripts/project-manifest-check.sh current
./scripts/harness-self-test.sh
./scripts/agent-workflow-check.sh
./scripts/review-report.sh --check
```

`framework` 和 `adoption` 模式允许应用命令明确跳过；`project` 和 `release` 阶段严格 fail-closed。没有注册真实组件、架构测试、安全扫描、SBOM、full-stack E2E 或生产就绪工件时，门禁不会给出发布绿灯。
