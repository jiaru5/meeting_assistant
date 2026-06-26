# Agent 启动 Prompt

这些 prompt 是操作入口，不是持久事实。

## 初始需求后启动 discovery

```text
读取 AGENTS.md、docs/product-spec/PROJECT-STATUS.md、docs/engineering/09-starter-adoption-guide.md 和 docs/engineering/14-greenfield-project-start.md。

当前目标是完成 adoption，不允许实现业务代码。

从 docs/adoption/INITIAL-REQUEST.md 开始：
1. 识别已知事实、假设、冲突和缺口；
2. 更新 docs/adoption/DISCOVERY-LEDGER.md 和 docs/adoption/SPEC-READINESS.md；
3. 每轮只询问最高优先级的 3-7 个问题；
4. 每个问题说明为什么重要、是否阻塞、选项/取舍、推荐选项和目标 product-spec 分卷；
5. 只有经过我确认的内容才能写入 docs/product-spec/；
6. 未决问题进入 docs/product-spec/10-open-decisions.md；
7. 持续执行，直到 ./scripts/adoption-check.sh --activation 只剩需要我显式确认的事项；
8. 未经我明确确认，不得切换 project 模式或创建业务实现代码。
```

## 继续下一轮 discovery

```text
继续 adoption discovery。
先读取 docs/adoption/DISCOVERY-LEDGER.md、docs/adoption/SPEC-READINESS.md 和相关 product-spec 主责分卷。
请只提出下一轮最高优先级的 3-7 个问题，并说明每个问题阻塞哪个章节或工程门禁。
不要实现业务代码，不要把假设写成事实。
```

## 将已确认事实转写到 spec

```text
把 docs/adoption/DISCOVERY-LEDGER.md 中已确认且未 promoted 的事实转写到对应 docs/product-spec/ 主责分卷。
同时更新 docs/product-spec/10-open-decisions.md、docs/product-spec/11-adr.md、docs/engineering/06-product-validation-matrix.md 和 docs/adoption/SPEC-READINESS.md。
未经确认的假设只保留在 adoption workspace，不得写入事实源。
```

## activation 前审查

```text
执行 project activation 前的只读审查。
运行 ./scripts/adoption-check.sh --activation，列出所有 blocker，并给出最小修复顺序。
不要运行 activate-project，不要切换 project 模式。
```

## 用户明确批准后 activation

```text
我已审查并确认 docs/product-spec/、docs/engineering/06-product-validation-matrix.md、harness/project-manifest.json 和 harness/agent-policy.json 可以作为新项目事实源和执行规范。
请运行 ./scripts/activate-project.sh，并在成功后运行标准门禁。
```
