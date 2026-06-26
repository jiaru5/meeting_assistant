# 项目状态

本文件声明当前 `docs/product-spec/` 的使用模式。AI agent 接手时必须先读取本文件，再决定是否可以开始业务实现。

## 当前模式

```text
mode: project
```

## 模式定义

| 模式 | 含义 | 允许行为 | 禁止行为 |
|---|---|---|---|
| `framework` | starter 仍处于通用框架状态，product-spec 中保留示例占位来说明写法 | 修改框架规则、完善模板、调整门禁 | 把示例占位当成真实项目事实；开始业务实现 |
| `adoption` | 正在把 starter 转写成特定项目的开发框架和事实源 | 使用 `docs/adoption/` 收集初始意向、问答、假设和 readiness；将已确认内容转写为 product-spec、ADR、验证矩阵和 manifest | 在事实源完成前实现业务代码；把未经确认的 adoption 内容当成事实 |
| `project` | product-spec 已被真实项目事实替换，可以作为唯一事实源 | 按 AGENTS 工作流开发、测试、审查和交付 | 保留 starter 示例、占位 ID 或未确认事实 |

## Adoption 子阶段

`adoption` 模式下的细分状态记录在 `harness/adoption-state.json`：

1. `intake`：已运行 `./scripts/start-project.sh`，等待用户填写 `docs/adoption/INITIAL-REQUEST.md`。
2. `discovery`：Agent 通过 3-7 个问题一轮的方式澄清需求，更新 `DISCOVERY-LEDGER.md`。
3. `spec-drafting`：只把已确认内容转写到 `docs/product-spec/`、ADR、open decisions 和验证矩阵。
4. `spec-review`：用户审查事实源和工程门禁准备状态。
5. `ready-for-activation`：`./scripts/adoption-check.sh --activation` 只剩显式确认项或已经通过。
6. `activated`：`./scripts/activate-project.sh` 已成功切换到 `project`。

## 切换到 Project 模式

进入 `project` 模式前必须完成：

1. 删除或替换 product-spec 中所有 starter 示例占位。
2. 将 `EntityName`、`GOAL-001`、`ROLE-001`、`UI-001`、`PERM-001`、`AC-001`、`OD-001`、`PV-AREA-001` 等占位换成真实项目 ID 和事实。
3. `docs/product-spec/10-open-decisions.md` 中没有阻塞实现的 `open` 项。
4. `docs/engineering/06-product-validation-matrix.md` 有真实项目 `PV-*` 行，并且不只包含 harness 基线。
5. `docs/product-spec/13-security-and-compliance.md` 已包含真实安全需求、数据分类和威胁模型。
6. `harness/project-manifest.json` 已注册真实组件、组件命令、全栈 E2E 和 owner。
7. `harness/agent-policy.json` 已按组织运行环境复核，未放宽最小权限默认值。
8. `docs/adoption/SPEC-READINESS.md` 所有必需章节为 `ready` 或明确 `not-applicable`，且没有 blocking gap。
9. `./scripts/adoption-check.sh --activation`、`./scripts/docs-check.sh`、`./scripts/project-manifest-check.sh development` 和 `./scripts/agent-workflow-check.sh` 通过。
10. 用户显式批准 `./scripts/activate-project.sh` 切换到 `project`；Agent 不能自行批准。
