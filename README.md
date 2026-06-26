# 分布式系统 Harness Starter

本仓库是一套面向 AI agentic coding 的通用 starter，用于前后端微服务架构的分布式系统研发。它不包含特定业务知识，而是提供可被 AI agent 严格读取、执行和验证的项目框架、事实源分卷、技术规范、工作流和门禁脚本。

## 设计来源

本 starter 抽象自 `example-smart_team-harness_engineering/` 中较成功的 harness engineering 实践，但不会复用其中的业务模型。保留的核心模式是：

1. `AGENTS.md` 作为 agent 入口和工作协议。
2. `docs/product-spec/` 作为产品和技术事实源目录。
3. `docs/engineering/` 作为工程执行事实源目录。
4. `docs/engineering/06-product-validation-matrix.md` 将规范条目映射到验证证据。
5. `docs/adoption/` 作为 greenfield 项目启动时的非事实源转写工作区，用于初始意向、问答、假设和 readiness。
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
├── scripts/
├── templates/
├── docker-compose.yml
├── docker-compose.test.yml
├── .env.example
└── .github/workflows/ci.yml
```

## 使用方式

新 AI agent 接手时，先读：

```text
AGENTS.md
docs/product-spec/PROJECT-STATUS.md
docs/engineering/09-starter-adoption-guide.md
```

推荐顺序：

1. 确认当前是 `framework`、`adoption` 还是 `project` 模式。
2. 在 `framework` 模式下，只维护 starter 框架、模板和门禁，不实现业务代码。
3. 启动新项目时先运行 `./scripts/start-project.sh --name "项目名" --owner "团队"`，再把初始意向写入 `docs/adoption/INITIAL-REQUEST.md`。
4. 在 `adoption` 模式下，通过 discovery 问答把已确认内容转写进 `docs/product-spec/`，删除或替换所有 `EXAMPLE_ONLY` 示例占位。
5. 运行 `./scripts/adoption-check.sh --activation`，通过后由用户显式批准 `./scripts/activate-project.sh`。
6. 切换到 `project` 模式后，运行 `./scripts/docs-check.sh` 和 `./scripts/agent-workflow-check.sh`。
7. 再按 `docs/engineering/01-repo-structure.md` 初始化前端应用、后端服务和共享库。
8. 每个需求先判断 `spec-change`、`spec-covered` 或 `no-product-impact`，再实现。
9. 交付前生成审查报告，把实际验证命令和结果写入 PR 或最终说明。

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
