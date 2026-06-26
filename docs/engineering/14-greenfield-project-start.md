# 14. Greenfield 项目启动

本文件给出从 starter 启动全新企业级项目的实际操作步骤和 Agent 启动 prompt。

目标不是快速做产品原型，而是让 AI coding agent 在可控、安全、可审查的事实源和门禁下，开发能投入生产使用的系统。

## 一次性启动步骤

在新项目目录中执行：

```bash
git clone <starter-repo> <new-project>
cd <new-project>
./scripts/start-project.sh --name "项目名" --owner "团队或 owner"
```

然后填写：

```bash
$EDITOR docs/adoption/INITIAL-REQUEST.md
```

初始内容不需要完整，但必须真实。不要为了通过模板而编造产品事实。

可参考：

```text
templates/project-intake.md
templates/agent-start-prompts.md
```

## 初始需求应该写在哪里

初始需求写入：

```text
docs/adoption/INITIAL-REQUEST.md
```

不要直接写入：

```text
docs/product-spec/01-product-scope.md
docs/product-spec/02-domain-model.md
docs/product-spec/06-api-contracts.md
```

原因：初始意向通常包含假设、缺口和冲突。直接进入 product-spec 会把未确认内容变成实现依据。

## 告诉 Agent 开始 adoption 的 prompt

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

## 每轮 discovery 的输出格式

Agent 每轮输出应包含：

1. 已确认事实：可以转写到哪个 product-spec 分卷。
2. 未确认假设：留在 discovery ledger，不能实现。
3. 冲突：需要用户裁决或进入 open decisions。
4. 下一轮 3-7 个问题。
5. 每个问题的阻塞性、选项、推荐方案和目标分卷。
6. 当前 readiness 缺口。

## 从回答到事实源的转写步骤

当用户回答一轮问题后，Agent 执行：

1. 更新 `docs/adoption/DISCOVERY-LEDGER.md` 的 user answers、confirmed facts、assumptions、conflicts。
2. 只把已确认 facts 写入对应 `docs/product-spec/` 主责分卷。
3. 如果问题未决但影响实现，写入 `docs/product-spec/10-open-decisions.md`。
4. 如果形成重要产品或技术取舍，写入 `docs/product-spec/11-adr.md`。
5. 更新 `docs/engineering/06-product-validation-matrix.md` 的真实 `PV-*` 行。
6. 更新 `docs/adoption/SPEC-READINESS.md` 的状态和 blocking gap。
7. 运行 `./scripts/adoption-check.sh` 查看剩余缺口。

## Project activation 前的操作

只读检查：

```bash
./scripts/adoption-status.sh
./scripts/adoption-check.sh --activation
```

如果失败，继续补：

1. product-spec 主责分卷。
2. open decisions 和 ADR。
3. validation matrix。
4. project manifest。
5. agent policy。
6. 最小组件骨架和工程命令。

通过后，用户明确批准，再执行：

```bash
./scripts/activate-project.sh \
  --confirmed-by "审批人" \
  --confirmation-text "我已审查 product-spec、工程门禁和 manifest，并批准 project activation。"
```

## Project mode 后给 Agent 的 prompt

```text
请先读取 AGENTS.md、docs/product-spec/PROJECT-STATUS.md、docs/product-spec/README.md、docs/engineering/README.md、与当前任务相关的主责分卷、docs/engineering/06-product-validation-matrix.md。
只有当 PROJECT-STATUS.md 声明 mode: project 时，才按 project 工作流开始实现。

本次目标是实现第一条最小可验证纵切。
必须先给出 spec sync 分类，确认对应 AC-* 和 PV-*，再实现。
实现后运行最小充分验证、./scripts/agent-workflow-check.sh 和 ./scripts/review-report.sh。
```

## 企业级启动完成标准

一个 greenfield 项目只有满足以下条件，才算完成 starter adoption：

1. product-spec 无 starter 占位和未确认假设。
2. 关键需求有 `AC-*`，关键验证有真实 `PV-*`。
3. 权限、数据隔离、安全、合规、审计、SLO、恢复目标已确认或明确 N/A。
4. 技术栈、服务边界、数据所有权、外部系统契约已确认。
5. manifest 注册了真实组件、命令、full-stack E2E 和生产就绪工件。
6. Agent policy 未放宽默认最小权限，且组织 allowlist 已复核。
7. `./scripts/adoption-check.sh --activation` 通过。
8. `./scripts/activate-project.sh` 在用户明确批准后成功切换 project。
