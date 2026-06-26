# 9. Starter Adoption 指南

本文件指导新的 AI agent 将本 starter 转写成某个特定项目的开发框架和唯一事实来源。

相关文件：

- `docs/adoption/README.md`
- `docs/adoption/INITIAL-REQUEST.md`
- `docs/adoption/DISCOVERY-LEDGER.md`
- `docs/adoption/SPEC-READINESS.md`
- `harness/adoption-state.json`
- `docs/engineering/14-greenfield-project-start.md`

## 核心原则

1. starter 的工程框架是真实规则，product-spec 中的业务内容在 `framework` 模式下只是示例占位。
2. 初始产品意向通常不完整，必须先进入 `docs/adoption/`，不能直接写成 product-spec 事实。
3. `docs/adoption/` 不是事实源，只保存原始材料、澄清问答、假设、冲突和 readiness。
4. 只有用户确认并转写到 `docs/product-spec/`、`docs/product-spec/10-open-decisions.md`、`docs/product-spec/11-adr.md`、`docs/engineering/06-product-validation-matrix.md` 或 `harness/project-manifest.json` 的内容，才能作为实现依据。
5. 在 `adoption` 完成前，不允许开始业务代码实现。
6. 进入 `project` 模式后，`docs/product-spec/` 才能被当成特定项目的唯一事实源。
7. 示例可以帮助理解写法，但必须显式删除或替换，不能和真实项目事实混在一起。

## 生命周期

```text
framework
  -> start-project
adoption/intake
  -> 用户填写 initial request
adoption/discovery
  -> Agent 每轮询问 3-7 个最高优先级问题
adoption/spec-drafting
  -> 已确认内容转写到事实源
adoption/spec-review
  -> 用户审查 product-spec、ADR、open decisions、validation matrix、manifest
adoption/ready-for-activation
  -> adoption-check --activation 通过
project
  -> activate-project 显式确认后切换
```

细分状态记录在 `harness/adoption-state.json`。不要只依赖聊天记录判断当前 adoption 进度。

## 步骤 1：确认模式和规则

读取：

```bash
AGENTS.md
docs/product-spec/PROJECT-STATUS.md
docs/product-spec/README.md
docs/engineering/README.md
docs/engineering/09-starter-adoption-guide.md
```

判断当前模式：

1. `framework`：只允许维护 starter 框架、模板和门禁。
2. `adoption`：允许转写目标项目事实源，但不允许实现业务代码。
3. `project`：允许按事实源实现业务功能。

如果 `PROJECT-STATUS.md` 不存在或模式不明确，先停止并补齐该文件。

## 步骤 2：启动目标项目 adoption

在新项目 clone 中执行：

```bash
./scripts/start-project.sh --name "项目名" --owner "团队或 owner"
```

脚本会：

1. 将 `PROJECT-STATUS.md` 从 `framework` 切换到 `adoption`。
2. 更新 `harness/adoption-state.json` 的项目名、owner 和 subphase。
3. 更新 `harness/project-manifest.json` 的项目名和 owner。
4. 确保 `docs/adoption/` 工作区存在。

此时不要实现业务代码。下一步是填写：

```text
docs/adoption/INITIAL-REQUEST.md
```

## 步骤 3：写入初始意向

`INITIAL-REQUEST.md` 可以不完整，但至少应包含：

1. 一句话说明要构建什么系统、服务谁、解决什么问题。
2. 已知用户或 actor。
3. 已知核心工作流或业务闭环。
4. 已知约束：身份权限、数据敏感度、部署环境、外部系统、合规、SLO 或恢复目标。
5. 已知非目标。
6. 可引用的已有材料。

不要为了填满模板而编造字段、权限、API 或页面。缺口进入 discovery。

## 步骤 4：Discovery 问答协议

Agent 不应一次性抛出完整 PRD 模板。每轮只问最高优先级的 3-7 个问题。

优先级顺序：

1. 产品目标、用户、核心业务闭环、系统边界。
2. 领域对象、状态、生命周期、不变量。
3. 身份、权限、租户或组织隔离、数据敏感度。
4. 外部系统、API、事件、数据所有权。
5. 页面、用户旅程、异常流、empty/error/forbidden 状态。
6. 性能、SLO、RTO/RPO、审计、合规、安全和威胁模型。
7. 技术栈、服务边界、部署方式、第一条可验证纵切。

每个问题必须记录：

| 字段 | 要求 |
|---|---|
| 问题 | 问题本身 |
| 为什么重要 | 为什么影响实现或生产可用性 |
| 是否阻塞 | 是否阻塞 project activation |
| 选项或取舍 | 可选方案和取舍 |
| 推荐选项 | Agent 的建议，必须说明理由 |
| 目标 product-spec 分卷 | 最终进入哪个主责分卷 |
| 用户答案 | 用户答案 |
| 最终决策 | 是否已确认 |

记录位置：

```text
docs/adoption/DISCOVERY-LEDGER.md
docs/adoption/SPEC-READINESS.md
```

## 步骤 5：转写规则

转写时按以下路由处理：

| 来源内容 | 去向 |
|---|---|
| 已确认事实 | 对应 `docs/product-spec/` 主责分卷 |
| 未确认假设 | `docs/adoption/DISCOVERY-LEDGER.md` |
| 阻塞或需要跟踪的问题 | `docs/product-spec/10-open-decisions.md` |
| 重要产品或技术取舍 | `docs/product-spec/11-adr.md` |
| 验收和测试覆盖 | `docs/product-spec/09-acceptance-criteria.md`、`docs/engineering/06-product-validation-matrix.md` |
| 技术栈、服务边界、部署约束 | `docs/product-spec/08-implementation-guidance.md` 和相关 engineering 分卷 |
| 组件、命令、E2E、生产工件 | `harness/project-manifest.json` |
| Agent 权限、工具、网络、审批 | `harness/agent-policy.json` |

禁止：

1. 把未确认假设写入 product-spec。
2. 把同一事实复制到多个主责分卷。
3. 保留 starter 示例行同时新增真实项目行。
4. 用聊天记录替代 open decision 或 ADR。
5. 在 `adoption` 未完成时创建业务实现代码。

## 步骤 6：Product-spec 完整性标准

进入 `project` 前，必须达到以下标准：

1. Goals 有可观察成功标准。
2. Core scenarios 有角色、正常流、异常流和边界。
3. Domain objects 有字段、生命周期、状态和不变量。
4. Permission matrix 能对齐 API、页面和服务端校验。
5. API、数据、事件和外部系统语义一致。
6. 关键行为有 `AC-*` 和 `PV-*`。
7. 安全、数据分类、威胁模型、SLO、RTO/RPO 和恢复策略已确认，或明确 `not-applicable` 且有理由。
8. 技术栈、服务边界、部署方式和第一条纵切策略已确认。
9. blocking open decisions 已关闭。
10. 用户显式审查并批准 activation。

## 步骤 7：准备 project activation

activation 前必须完成：

1. 删除或替换 product-spec 和验证矩阵中的 starter 占位。
2. `docs/adoption/SPEC-READINESS.md` 所有必需行状态为 `ready` 或明确 `not-applicable`，且“是否阻塞缺口”为 `no`。
3. `docs/product-spec/10-open-decisions.md` 没有阻塞实现的 `open` 项。
4. `docs/engineering/06-product-validation-matrix.md` 有真实项目 `PV-*` 行，且不只包含 harness 基线。
5. `harness/project-manifest.json` 有真实项目名、owner、组件骨架、组件命令、full-stack E2E 计划和生产就绪工件路径。
6. `harness/agent-policy.json` 已按组织运行环境复核。
7. 必要的 CI、CODEOWNERS、分支保护和人工审批规则已进入工程规范或待办证据。

组件骨架可以在 `adoption` 末期创建，但不得实现业务行为。它的目的只是让 manifest、命令、架构测试、Docker 和 E2E 门禁有真实目标。

运行：

```bash
./scripts/adoption-check.sh --activation
```

如果失败，按输出修复 readiness、事实源、open decisions、manifest 或验证矩阵。不要放宽门禁。

## 步骤 8：切换到 project 模式

只有用户明确批准后才能运行：

```bash
./scripts/activate-project.sh \
  --confirmed-by "用户或审批人" \
  --confirmation-text "我已审查 product-spec、工程门禁和 manifest，并批准 project activation。"
```

脚本会：

1. 写入 `harness/adoption-state.json` 的显式确认。
2. 运行 activation check。
3. 将 `PROJECT-STATUS.md` 切换到 `project`。
4. 运行 `docs-check`、`project-manifest-check development` 和 `agent-workflow-check`。
5. 如果门禁失败，回滚到 `adoption` 模式。

`PROJECT-STATUS.md` 和 `harness/adoption-state.json` 的 activation lifecycle diff 只记录模式和确认状态，不改变产品行为；workflow 门禁不应因此要求 validation matrix 更新。

Agent 不能用自己的判断代替用户确认。

## 步骤 9：第一条可验证纵切

进入 `project` 后，才能开始真实业务实现。

第一条纵切必须回指：

1. product-spec 主责分卷。
2. `AC-*` 验收标准。
3. `PV-*` 验证矩阵行。
4. 组件命令和测试入口。
5. review report 和验证证据。

如果第一条纵切发现需求缺口，回到 spec sync 流程：先更新 facts、ADR、open decisions 和验证矩阵，再实现。

## 常见错误

1. 错误：把 `INITIAL-REQUEST.md` 的原始想法直接复制进 product-spec。正确做法：先问问题、确认，再转写。
2. 错误：一次性要求用户填完整 PRD。正确做法：每轮 3-7 个高优先级问题。
3. 错误：把 Agent 假设写成 Accepted ADR。正确做法：先记录 assumption，用户确认后再决策。
4. 错误：Project mode 仍保留 `EntityName`、`GOAL-001`、`PV-AREA-001`。正确做法：让 `docs-check` 阻断并清理。
5. 错误：没有真实组件和命令就切换 project。正确做法：在 adoption 末期补最小组件骨架和 manifest，不实现业务行为。
6. 错误：用户没有明确批准就运行 `activate-project`。正确做法：只做 activation readiness report，等待确认。
