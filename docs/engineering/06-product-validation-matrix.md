# 6. 产品验证矩阵

本文件定义产品规范到自动化验证的映射，用于判断产品行为是否达到面向 PRD、交互和功能的完整验证目标。

`docs/product-spec/` 是产品事实源；本文件只记录验证覆盖状态、验证类型、证据入口和缺口。

## 状态定义

| 状态 | 含义 |
|---|---|
| `missing` | 当前没有持久化自动化验证。 |
| `planned` | 已明确验证方式，但测试用例或脚本尚未落地。 |
| `partial` | 仓库内已有部分自动化验证，但没有覆盖完整范围。 |
| `covered` | 仓库内已有测试或脚本覆盖，并纳入标准门禁。 |
| `manual-evidence` | 有截图、交互记录或人工检查作为短期证据，但没有长期回归测试。 |

## 使用规则

1. 实现或修改产品行为前，先找到对应矩阵行。
2. 如果没有对应行，先补充矩阵行，再实现代码。
3. 行为完成后，将验证状态推进到 `covered`，或写明为什么只能保留为 `manual-evidence`。
4. 产品行为、UI/UX 契约、API 契约、事件契约和验收标准变更时，必须同步检查本矩阵。
5. Playwright 截图、人工观察或本地浏览器检查只能辅助开发和审查，不能长期替代仓库测试。

## Starter 基线矩阵

| ID | 场景或规则 | 主事实源 | 验证类型 | 目标测试入口 | 当前证据 | 状态 |
|---|---|---|---|---|---|---|
| PV-HARNESS-001 | 事实源分卷、工程分卷和入口脚本存在性 | `docs/product-spec/README.md`、`docs/engineering/README.md` | 文档门禁 | `./scripts/docs-check.sh` | `docs-check` 检查必要分卷、索引和脚本入口 | `covered` |
| PV-HARNESS-002 | Agent 工作流可生成 spec sync 和 review report 证据 | `05-agent-operating-model.md`、`04-review-and-ci-gates.md` | 工程门禁 | `./scripts/agent-workflow-check.sh`、`./scripts/review-report.sh --check` | workflow gate 调用 spec sync 和 review report check | `covered` |
| PV-HARNESS-003 | Docker 优先且禁止宿主机数据库/中间件依赖 | `01-repo-structure.md`、`02-dev-commands.md` | 文档门禁、Compose 配置 | `./scripts/docs-check.sh`、`./scripts/compose-check.sh` | docs-check 扫描宿主机依赖，compose-check 解析本地和测试配置 | `covered` |
| PV-HARNESS-004 | 非 project 模式和空组件不能通过发布门禁 | `02-dev-commands.md`、`04-review-and-ci-gates.md` | Harness 自测试 | `./scripts/harness-self-test.sh` | 单元测试验证 release fail-closed 和未注册组件 | `covered` |
| PV-HARNESS-005 | Agent 使用最小文件、网络、凭据和外部写权限 | `12-agent-security.md` | 策略校验 | `./scripts/project-manifest-check.sh current` | 校验 `harness/agent-policy.json` 固定安全默认值 | `covered` |
| PV-HARNESS-006 | 真实组件必须注册质量、安全、架构和 SBOM 命令 | `01-repo-structure.md`、`10-security-and-supply-chain.md` | 清单门禁 | `./scripts/project-manifest-check.sh development` | project 模式缺少组件或命令即失败 | `covered` |
| PV-HARNESS-007 | 发布候选执行真实 Compose full-stack E2E | `03-test-strategy.md`、`11-production-readiness.md` | 运行门禁 | `./scripts/test-e2e-full-stack.sh` | project 清单驱动 `compose up --wait`、seed、测试和清理 | `covered` |
| PV-HARNESS-008 | 交付审查引用实际命令、退出码、commit、worktree fingerprint 和日志 | `04-review-and-ci-gates.md` | 证据门禁 | `./scripts/check.sh`、`./scripts/review-report.sh --require-evidence` | `.harness/evidence/` 记录并验证当前工作区命令结果 | `covered` |
| PV-HARNESS-009 | 不完整初始意向只能进入 adoption 工作区，不能直接变成产品事实或业务实现 | `09-starter-adoption-guide.md`、`14-greenfield-project-start.md` | Adoption 门禁、自测试 | `./scripts/adoption-check.sh`、`./scripts/harness-self-test.sh` | adoption check 阻断空 initial request、template marker、未完成 readiness 和无确认 activation | `covered` |
| PV-HARNESS-010 | Project activation 必须显式确认且 fail-closed；placeholder、blocking open decision、缺少 manifest 或 PV 行都会阻断 | `09-starter-adoption-guide.md`、`04-review-and-ci-gates.md` | Adoption activation 门禁 | `./scripts/adoption-check.sh --activation`、`./scripts/activate-project.sh` | activate-project 先写入确认、运行 activation check，失败回滚到 adoption | `covered` |

## Meeting Assistant 产品验证矩阵

| ID | 场景或规则 | 主事实源 | 验证类型 | 目标测试入口 | 当前证据 | 状态 |
|---|---|---|---|---|---|---|
| PV-MA-001 | 原生 macOS 录制创建会话并保存媒体产物 | `docs/product-spec/01-product-scope.md`, `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/08-implementation-guidance.md` | 原生组件测试、受控 E2E、权限检查 | 未来 `native-app` 产品行为测试 | Product-spec 已转写完成；activation skeleton 已注册但不实现录制行为 | `planned` |
| PV-MA-002 | 视频、系统音频、麦克风音频、混合音频、normalized audio 和降级原因按契约登记 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md` | 单元测试、文件契约测试 | 未来 `processing-cli` artifact contract 测试 | Product-spec 已转写完成；activation skeleton 已注册但不验证 artifact 行为 | `planned` |
| PV-MA-003 | 从可用音频通过 transcription adapter 生成带时间戳 transcript segments | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/06-api-contracts.md`, `docs/product-spec/09-acceptance-criteria.md` | 单元测试、样例媒体处理测试 | 未来 `processing-cli` transcription adapter 测试 | Product-spec 已转写完成；activation skeleton 已注册但不实现 adapter | `planned` |
| PV-MA-004 | best-effort 匿名 speaker labels 不声称真实身份；无引擎时降级 transcript-only | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/13-security-and-compliance.md` | 单元测试、样例 transcript 测试 | 未来 `processing-cli` speaker-label fallback 测试 | Product-spec 已转写完成；activation skeleton 已注册但不实现 speaker labeling | `planned` |
| PV-MA-005 | 文件化流水线保护原始媒体，派生产物可重试生成 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/11-adr.md` | 文件契约测试、处理重试测试 | 未来 `processing-cli` artifact contract 测试 | Product-spec 已转写完成；activation skeleton 已注册但不处理媒体文件 | `planned` |
| PV-MA-006 | bootstrap/check 输出平台、工具链、媒体工具、adapter/runtime、workspace、权限和允许来源状态；不自动下载 | `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/09-acceptance-criteria.md`, `docs/engineering/10-security-and-supply-chain.md` | 脚本测试、环境检查测试 | 未来 dependency-check CLI 测试 | Product-spec 已转写完成；activation skeleton 命令已注册但仅验证边界和不自动下载 | `planned` |
| PV-MA-007 | transcript 可复制/导出，应用不自动上传外部 GPT 或模型 API | `docs/product-spec/06-api-contracts.md`, `docs/product-spec/13-security-and-compliance.md` | 单元测试、导出契约测试 | 未来 `processing-cli` export 测试 | Product-spec 已转写完成；activation skeleton 已注册但不实现导出行为 | `planned` |

## 标准验证命令目标

```bash
./scripts/docs-check.sh
./scripts/adoption-check.sh
./scripts/project-manifest-check.sh
./scripts/harness-self-test.sh
./scripts/compose-check.sh
./scripts/prod-config-check.sh
./scripts/architecture-check.sh
./scripts/security-check.sh
./scripts/supply-chain-check.sh
./scripts/db-migration-check.sh
./scripts/spec-sync-check.sh
./scripts/agent-workflow-check.sh
./scripts/check.sh
./scripts/test-e2e.sh
./scripts/test-e2e-full-stack.sh
./scripts/build.sh
./scripts/release-preflight.sh
```

## 产品级完成标准

一个产品行为只有同时满足以下条件，才能视为完成：

1. 对应事实源已更新或确认不需要更新。
2. 对应矩阵行存在。
3. 关键路径有自动化验证，状态达到 `covered`。
4. 如果短期只能使用 `manual-evidence`，交付说明必须写明证据、缺口和下一步测试落点。
5. 验证不依赖宿主机数据库、中间件或本机常驻服务。
