# 4. 审查和 CI 门禁

本文件定义代码审查重点、CI 门禁和交付说明要求。

## 审查清单

每次实现完成后，agent 必须自查：

1. 是否读取并遵守相关 `docs/product-spec/` 和 `docs/engineering/` 分卷。
2. 是否需要更新事实源或追加 ADR。
3. 本次产品表面改动属于 `spec-change`、`spec-covered` 还是 `no-product-impact`。
4. 是否新增事实源未定义的实体、字段、角色、状态、页面、事件或持久化字段。
5. 是否所有租户内查询都包含隔离条件或明确授权例外。
6. 是否所有权限都在服务端校验。
7. 是否所有跨实体引用都做了隔离域校验。
8. 是否把读取投影、聚合、翻译或展示字段误放进核心领域模型。
9. 是否补充足够的单元、集成、组件、契约或 E2E 测试。
10. 是否使用 Docker 验证部署相关改动。
11. 是否避免提交 secret、个人路径、临时日志和一次性调试文件。
12. 是否避免引入宿主机数据库、中间件或本机常驻服务依赖。
13. 是否更新或确认 `06-product-validation-matrix.md`。
14. 是否为生产配置、健康检查、日志脱敏和可观测性留下验证证据。
15. 是否所有真实组件和命令已注册到 `harness/project-manifest.json`。
16. 是否遵守 Agent 最小权限、网络 allowlist 和人工审批边界。
17. 是否通过架构、安全和供应链门禁。
18. 如果处于 `adoption` 模式，是否只把已确认内容转写到事实源，且没有创建业务实现代码。

## 自动化审查输出

agent 完成非平凡改动后，必须生成可复制到 PR 或交付说明中的审查摘要。摘要至少包含：

1. Spec alignment：列出本次改动依据的 `docs/product-spec/` 和 `docs/engineering/` 文件，并说明是否需要 ADR。
2. Changed surface：列出改动涉及的模块、API、数据库、消息、Docker、CI、页面或测试入口。
3. Permission and data isolation：说明权限、租户隔离、服务间身份和审计是否受影响。
4. Test evidence：列出已运行命令、结果、worktree fingerprint、失败后的修复和未运行项。
5. Residual risk：列出仍需产品或技术确认的事项；没有时写明没有新增未决决策。

## Agent 工作流门禁

`./scripts/agent-workflow-check.sh` 是 agent 节奏的强制门禁。它必须检查：

1. 产品表面改动是否通过 `./scripts/spec-sync-check.sh`。
2. 产品行为变更是否检查验证矩阵。
3. 实现变更是否有对应测试或测试脚本变更。
4. 工程流程、Docker、CI 或脚本变更是否同步 `docs/engineering/`。
5. shell 脚本是否通过语法检查。
6. `scripts/review-report.sh --check` 是否可生成必要章节。
7. 项目清单和 Agent 权限策略是否有效。
8. Harness 自测试是否覆盖新增失败路径。
9. Adoption 生命周期变更是否通过 `./scripts/adoption-check.sh`，且 activation 不能绕过用户确认。
10. 仅由 `docs/product-spec/PROJECT-STATUS.md` 和 `harness/adoption-state.json` 组成的 activation lifecycle diff 不属于产品行为变更，不要求额外更新 validation matrix；仍必须通过 activation check、manifest check 和 workflow check。

## CI 必过项

项目初始化后，CI 至少包含：

```text
docs-check
adoption-check
project-manifest-check
harness-self-test
compose-check
agent-workflow-check
prod-config-check
architecture-check
security-check
supply-chain-check
lint
test
build
review-report
```

服务和前端应用接入后，应逐步补齐：

```text
db-migration-check
api-contract
message-contract
mocked-e2e
full-stack-e2e
docker-build
release-preflight
```

`.github/workflows/release.yml` 是 release preflight 入口。它在 starter/framework 阶段按预期失败；只有 project 模式、真实组件、生产工件和发布验证全部就绪后才能变绿。

## 仓库保护

adoption 阶段必须在代码托管平台配置：

1. 保护默认分支，禁止 Agent 或普通开发者直接 push。
2. 只允许通过 PR 合并，并要求至少一个独立人工 reviewer。
3. Agent 发起人、Agent 自身或自动化账号不能满足独立批准要求。
4. 要求 CODEOWNERS、required checks、过期批准失效和对话解决。
5. `.github/workflows/`、`harness/` 和 `docs/product-spec/` 由对应 owner 保护。
6. `production` environment 配置 required reviewers；发布凭据只在批准后的受控 job 中可用。

这些平台设置不能仅由仓库文本证明，项目 owner 必须在进入 `project` 和首次发布前保留配置证据。

## 阻塞规则

出现以下情况时，agent 不应继续扩大实现范围：

1. 事实源内部冲突且无法从 ADR 判断最新决策。
2. 用户要求与事实源明确冲突。
3. 需要选择新的产品模型、权限规则、API 语义或持久化字段。
4. 标准验证持续失败，且失败原因不明确。
5. 需要 secret、外部账号或生产凭据。
6. Agent 请求任意网络、完整主机权限或绕过 CI/安全门禁。

## 合并前标准

合并前默认运行：

```bash
./scripts/check.sh
```

如果改动影响 E2E、Docker 或跨模块集成，还必须运行：

```bash
./scripts/test-e2e.sh
./scripts/test-e2e-full-stack.sh
./scripts/build.sh
```

如果这些脚本尚未接入具体应用，agent 必须在交付说明中列出跳过项和接入条件。

## Adoption 前置标准

从 starter 启动新项目时，project activation 前默认运行：

```bash
./scripts/adoption-status.sh
./scripts/adoption-check.sh --activation
```

有 blocker 时不得运行 `activate-project`。通过后仍需要用户显式批准：

```bash
./scripts/activate-project.sh --confirmed-by "审批人" --confirmation-text "..."
```

## 发布前标准

发布候选默认运行：

```bash
./scripts/release-preflight.sh
```

发布前必须确认：

1. `docs/product-spec/10-open-decisions.md` 没有 `open` 阻塞项。
2. 发布范围内验证矩阵行均为 `covered`。
3. 没有 `.env`、日志、`node_modules`、`dist`、`target`、Playwright 输出等生成物、secret 或本机文件被跟踪或待提交。
4. 生产 secret 注入、migration、回滚和观测告警完成审查。
5. 当前模式是 `project`，且项目清单存在生产组件和真实全栈 E2E。
6. threat model、SLO、runbook、回滚、备份恢复、事故响应和数据分类均已注册。
7. 架构、安全、SBOM、制品签名/provenance 配置和独立人工批准完成。
