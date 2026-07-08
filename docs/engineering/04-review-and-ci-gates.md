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
19. 产品行为实现是否检查了 `07-development-plan.md` 中相关 `TDG-MA-*` testability gate，并在验证矩阵记录关闭条件。
20. `06-product-validation-matrix.md` 是否为 planned/partial 行写明目标测试文件或命令、阻塞缺口和关闭条件，而不是只写“未来测试”。
21. 如果本次来自并行 worktree，是否声明了 freeze 基线、frozen source、允许修改范围和 contract-change 通道。
22. 是否有普通 feature worktree 夹带修改 frozen contract；如果有，是否已升级为 `spec-change` 并补充主责分卷、ADR 或验证矩阵。
23. 如果用户触发 PM/Main Agent 或多 agent 工作流，是否先按 `05-agent-operating-model.md` 输出分阶段 `Multi-Agent Dispatch Plan`，并只启动当前阶段允许的 `spawn_now` 角色。
24. Tester、Reviewer 或最终 Risk-checker 是否等待 Implementer 稳定 diff、测试证据或 PM gate 后才启动；如果曾提前启动，是否在上游稳定后重新运行受影响的后置角色。

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
3. 实现变更是否有对应 backend、frontend、platform、E2E 或测试脚本变更。
4. 工程流程、Docker、CI 或脚本变更是否同步 `docs/engineering/`。
5. shell 脚本是否通过语法检查。
6. `scripts/review-report.sh --check` 是否可生成必要章节。
7. 项目清单和 Agent 权限策略是否有效。
8. Harness 自测试是否覆盖新增失败路径。
9. Adoption 生命周期变更是否通过 `./scripts/adoption-check.sh`，且 activation 不能绕过用户确认。
10. 当前 mode 值只能由 `docs/product-spec/PROJECT-STATUS.md` 声明；README、adoption 审计文档、platform README 和 open decisions 只能引用该文件或记录历史审计，不能复述当前 mode。
11. 仅由 `docs/product-spec/PROJECT-STATUS.md` 和 `harness/adoption-state.json` 组成的 activation lifecycle diff 不属于产品行为变更，不要求额外更新 validation matrix；仍必须通过 activation check、manifest check 和 workflow check。
12. 组件路径、组件命令和 full-stack E2E 入口只能以 `harness/project-manifest.json` 为可执行注册表；工程文档可以定义命令类型和边界，但不能复制一份可独立维护的当前命令表。
13. `platform/native-app`、`platform/processing-cli` 和 `platform/e2e` 下的产品源码、产品测试、组件元数据和 local E2E 变更必须纳入产品表面、测试覆盖和 review report 推荐验证判断。
14. 涉及 Meeting Assistant 产品行为的 diff 必须检查相关 `TDG-MA-*`：命令 schema、artifact schema、fixture、UI locator、native capture spike、路径/delete 负向用例和证据入口缺一时，相关 `PV-MA-*` 不能推进到 `covered`。
15. 并行 worktree 合并前必须能说明 frozen source 是否被修改；被修改时必须有 `spec-change`、ADR 或 open decision 证据，并重新声明 freeze 基线。

## Testability Gate 审查规则

产品行为实现、验证矩阵更新或阶段收口时，reviewer 必须执行以下检查：

1. 每个受影响 `VS-MA-*` 都能在 `07-development-plan.md` 找到相关 `TDG-MA-*`，并说明该缺口已关闭、仍阻塞，或本次只做规范/测试基础设施。
2. 每个新增或修改的 `CMD-MA-*` 都有命令 schema 断言、unknown field fail-fast、错误响应和 exit code 测试。
3. 每个新增或修改的 artifact、transcript、speaker label、export 或 delete 行为都有结构化 schema 断言和路径边界负向测试。
4. 每个 native UI 行为都有 Swift Testing 或 XCUITest 入口；短期只有人工证据时，验证矩阵状态只能是 `manual-evidence` 或 `partial`。
5. 验证矩阵不能只写“未来测试”“后续补充”或“待接入”而没有目标文件/命令、阻塞缺口和关闭条件。
6. 如果实现依赖真实 runtime、原生 capture 或本机权限状态，必须同时保留 fake/fixture 契约测试；真实环境 smoke 只能补充，不能替代确定性测试。
7. 如果发现测试入口不足，review 结论应要求先关闭 testability gate，而不是扩大业务代码实现。
8. native-app 默认 `test` gate 可跳过真实 app-bundle XCUITest 以保持本地快速反馈；审查 native UI、release-scope 或阶段收口证据时，必须单独记录 `./platform/native-app/scripts/test-app-bundle.sh` 或 `MA_NATIVE_APP_RUN_XCUITEST=1 ./platform/native-app/scripts/test.sh` 的结果。只有默认 skip 输出不能证明 `.app` 启动和 `XCUIApplication()` locator。

## 本地和 CI 必过项

项目初始化后，本地标准门禁和 CI 至少包含：

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

`./scripts/release-preflight.sh` 是 release preflight 的当前标准入口。默认 `local-direct` 分发模式面向本机直接安装候选：总门禁会生成 Release bundle、安装稳定 `MeetingAssistantNativeLocal.app` 并运行 local-direct functional preflight；显式 `developer-id` 模式才使用更重的 release-scope native capture / XCUITest 分发证据路径。若接入 GitHub Actions，`.github/workflows/release.yml` 应调用该脚本；只有 project 模式、真实组件、生产工件和对应分发模式的发布验证全部就绪后才能变绿。

## 仓库保护

代码托管平台应配置：

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

阶段收口或 Main PM 集成检查默认运行：

```bash
./scripts/phase-preflight.sh
```

`phase-preflight.sh` 允许验证矩阵保留已写明目标入口、阻塞缺口和关闭条件的 `partial` 或 `planned` 行；它只能证明当前阶段可继续集成，不能替代发布候选验收。

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

`release-preflight.sh` 只用于真正的发布候选。它必须 fail-closed：先由 `vs-stage-check.py release` 确认 `VS-MA-14` 到 `VS-MA-22` 均为 `已达退出口径`，再检查发布范围内所有 `PV-*` 均为 `covered`；默认 local-direct 分支还必须证明已安装本机 app 与当前 source Release app 匹配并通过 recording -> processing -> transcript actions functional preflight。任何未关闭 VS、任何非 `covered` PV、installed app/source app 不一致，或阶段收口证据替代发布证据时都不能变绿。

发布前必须确认：

1. `docs/product-spec/10-open-decisions.md` 没有 `open` 阻塞项。
2. 发布范围内验证矩阵行均为 `covered`。
3. 没有 `.env`、日志、`node_modules`、`dist`、`target`、Playwright 输出等生成物、secret 或本机文件被跟踪或待提交。
4. 生产 secret 注入、migration、回滚和观测告警完成审查。
5. 当前模式是 `project`，且项目清单存在生产组件和真实全栈 E2E。
6. threat model、SLO、runbook、回滚、备份恢复、事故响应和数据分类均已注册。
7. 架构、安全、SBOM、制品签名/provenance 配置和独立人工批准完成。
