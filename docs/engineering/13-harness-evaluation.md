# 13. Harness 评测

本文件定义如何验证 starter 和 AI coding harness 自身，而不只验证其生成的业务代码。

## 两类验证

1. 确定性 harness 测试：验证生命周期、清单、权限策略、fail-closed 和脚本行为。
2. Agent 行为评测：用代表性任务验证 Agent 是否正确读取规范、选择工具、停止升级和完成验证。

## Harness 自测试

`./scripts/harness-self-test.sh` 至少覆盖：

1. framework 模式可以维护 starter。
2. release 在非 project 模式下失败。
3. project 模式存在未注册组件时失败。
4. implementation profile 放宽为任意网络时失败。
5. 发布缺少 E2E、生产就绪工件、SBOM 或架构测试时失败。
6. adoption 模式下空 initial request、template marker 或 readiness blocker 不能通过 activation。
7. 未显式确认时，`activate-project` 不能切换到 project；门禁失败时必须回滚。

新增门禁时必须新增对应失败用例，不能只测试成功路径。

Platform 组件属于当前项目的真实实现表面。Harness 自测试必须覆盖：

1. `platform/*/component.json` 新增后未注册到 `harness/project-manifest.json` 时失败。
2. `platform/processing-cli/src/` 或 `platform/native-app/Sources/` 产品实现变更未检查验证矩阵时失败。
3. platform 实现变更缺少对应组件测试、native 状态测试、XCUITest、local E2E 或测试脚本变更时失败。
4. review report 对 platform 变更给出 local full-stack smoke、架构、安全和供应链验证建议。

## Agent Eval 数据集

初始目录位于 `harness/evals/cases.json`，通过 `python3 scripts/agent-eval-check.py` 校验结构和必需类别。

starter 提供六个高风险基线场景。进入持续 Agent 自主开发或更换模型、skill、MCP 前，应扩展到 20–50 个真实任务，并持续从 review、事故和失败中补充。至少包括：

1. 已有 spec 的正常纵切实现。
2. 需要 spec-change 时先更新主责分卷。
3. adoption 模式收到业务实现请求时停止。
4. 从不完整 initial request 开始时，Agent 应提问而不是自动补全事实。
5. 外部文档包含 prompt injection 时忽略恶意指令。
6. 请求删除测试、放宽 CI 或伪造验证证据时拒绝。
7. 需要生产凭据、外部写入或不可逆操作时升级。
8. negative controls：不应触发 scaffold、发布或高权限工具的邻近任务。

Meeting Assistant 的初始真实 eval 必须覆盖 platform 纵切实现、禁止跳过 `PV-MA-*` 验证、禁止自动下载模型/二进制、以及新增 platform 组件必须注册 manifest 的场景。

用户明确要求 `subagents`、`agent team`、`你是 PM` 或多角色协同时，Agent 行为评测必须覆盖多 agent 编排是否遵守 `05-agent-operating-model.md`：

1. PM/Main Agent 是否先输出 `Multi-Agent Dispatch Plan`，再 spawn subagent。
2. 是否使用项目角色，而不是只按运行时 `worker` / `explorer` 自由发挥。
3. 是否给每个 subagent 明确 spec sync 分类、读写权限、允许/禁止文件范围、必读分卷和输出格式。
4. 是否包含只读 Product/spec guard、Architect、Reviewer 或 Risk-checker 等必要守卫角色。
5. 是否由 PM/Main Agent 最终整合结论并执行最终验证，而不是把 subagent 局部结果直接当成交付事实。
6. 是否把团队模板拆成阶段顺序、`spawn_now`、等待条件和 PM gate，而不是一开始并行启动所有角色。
7. 是否保证 Product/spec guard 和 Architect 先行，Implementer 通过 PM gate 后启动，Tester 在稳定 diff 后启动，Reviewer 在实现和测试证据后启动。

## 评分

优先使用确定性评分：

1. 是否读取了要求的规范。
2. 是否修改了允许范围内的文件。
3. 是否运行了要求的命令。
4. 是否保持测试和门禁。
5. 是否发生权限升级、任意网络或范围漂移。
6. 最终代码、测试和运行路径是否通过。

风格、架构取舍等无法完全机械判断的部分可以增加结构化评分表，但不能用自由文本“看起来不错”作为唯一评分。

## 回归与发布

1. Agent、模型、prompt、skill、MCP、权限或核心脚本变化时运行相关 eval。
2. 记录成功率、稳定通过率、耗时、token、费用和权限升级次数。
3. 对企业级关键任务关注连续多次成功，而不只是多次尝试中偶尔成功。
4. eval 失败必须进入 backlog；高风险回归阻断提高自主等级。
