# Adoption 工作区

本目录是从 starter 启动真实项目时的转写工作区。它用于保存初始意向、澄清问答、假设、冲突和 readiness 状态。

本目录不是产品事实源，也不是工程事实源。

- 产品、领域、权限、API、数据、页面、验收标准和 ADR 的唯一事实源仍然是 `docs/product-spec/`。
- 工程结构、命令、测试、CI、Agent 工作流和验证矩阵的唯一事实源仍然是 `docs/engineering/`。
- 本目录中的原始回答、假设和草稿不能直接作为实现依据；只有经过用户确认并转写到主责分卷的内容才能驱动实现。

## 文件角色

| 文件 | 角色 | 是否可作为事实源 |
|---|---|---|
| `INITIAL-REQUEST.md` | 用户自由写入的初始产品意向、材料链接、约束和非目标；允许不完整 | 否 |
| `DISCOVERY-LEDGER.md` | 记录已确认事实、未确认假设、冲突、问题队列、用户回答和转写记录 | 否 |
| `SPEC-READINESS.md` | 逐章检查 product-spec 是否达到可实现、可验证、可投产要求 | 否 |

## 标准流程

```text
framework
  -> ./scripts/start-project.sh --name "项目名" --owner "团队"
adoption/intake
  -> 用户填写 docs/adoption/INITIAL-REQUEST.md
adoption/discovery
  -> Agent 每轮询问最高优先级的 3-7 个问题
adoption/spec-drafting
  -> Agent 只把已确认内容转写到 docs/product-spec/
adoption/spec-review
  -> 用户审查 product-spec、open decisions、ADR 和验证矩阵
adoption/ready-for-activation
  -> ./scripts/adoption-check.sh --activation 通过
project
  -> ./scripts/activate-project.sh 显式确认后切换
```

## Agent 规则

1. 不要把 `INITIAL-REQUEST.md` 中的未经确认内容直接写入 product-spec。
2. 每轮只问 3-7 个最高优先级问题，避免一次性输出完整模板。
3. 每个问题必须说明：为什么重要、是否阻塞、建议选项或取舍、目标 product-spec 分卷。
4. 假设只能留在 `DISCOVERY-LEDGER.md`，不得提升为事实。
5. 冲突和未决问题进入 `docs/product-spec/10-open-decisions.md`，关闭后回写主责分卷和 ADR。
6. 未经用户明确确认，不得运行 `activate-project`，不得创建业务实现代码。
