# 11. 架构决策记录

本文件定义变更流程和 ADR 记录。相关文件：`00-governance.md`、`10-open-decisions.md`。

ADR 记录决策背景、取舍和历史原因。当前可执行规则必须维护在对应主责分卷或 `docs/engineering/` 分卷中，不能只依赖 ADR 正文作为实现依据。

## 变更流程

任何新需求、方案变更或实现过程中发现的设计冲突，都必须按以下流程处理：

1. 定位相关主责分卷。
2. 列出新决策与现有设计的矛盾点。
3. 确认最终决策。
4. 更新本目录中的相关章节，确保领域、权限、API、页面、计算规则、数据、事件和验收标准同步一致。
5. 如果变更属于重要产品或技术决策，追加 ADR。
6. 再进行代码实现、测试用例更新或 migration 开发。

禁止流程：

1. 禁止只修改代码但不更新事实源。
2. 禁止只在聊天记录、commit message、issue、PR 描述或临时文档中记录新决策。
3. 禁止保留与事实源冲突的旧说明作为并行事实源。

## ADR 格式

```text
## ADR-YYYYMMDD-NN: 决策标题

状态：Accepted | Superseded | Proposed

背景：
- 为什么需要这项决策。

决策：
- 决定了什么。

影响：
- 对领域模型、权限、API、数据、UI、测试、migration 或运行的影响。

备选方案：
- 考虑过哪些选项，以及为什么拒绝。
```

## ADR-20260615-01: 为 Agentic Coding 使用拆分事实源和可执行门禁

状态：Accepted

背景：
- AI agentic coding 需要稳定、可搜索、可验证的项目事实。
- 产品事实、工程工作流和临时执行记录服务于不同目的。
- 单个大型 prompt 或分散的聊天决策会增加上下文漂移和实现风险。

决策：
- 使用 `AGENTS.md` 作为简短的 agent 入口和工作协议。
- 使用 `docs/product-spec/` 作为产品和应用技术事实源。
- 使用 `docs/engineering/` 作为工程执行事实源。
- 使用 `docs/engineering/06-product-validation-matrix.md` 将事实映射到验证证据。
- 使用 `scripts/` 中的脚本执行文档、规范同步、工作流、审查报告和发布预检门禁。

影响：
- Agent 必须在实现前读取相关事实源。
- 产品行为变更需要 Spec Sync 分类和验证矩阵审查。
- 工程工作流变更需要同步更新工程文档。

备选方案：
- 把所有指导放在一个 prompt 中：拒绝，因为难以验证且容易漂移。
- 把代码当作唯一事实源：拒绝，因为产品意图、权限和验收标准无法完全从代码恢复。

## ADR-20260625-01: 使用 Fail-Closed 的项目清单和 Agent 策略

状态：Accepted

背景：
- 目录自动发现和“跳过所有应用目标后仍报告成功”的脚本会制造错误的发布信心。
- 企业级 AI coding 需要明确组件 owner、验证命令、Agent 权限、供应链期望和生产就绪证据。
- 单靠文档不能证明发布关键控制已经针对当前工作区执行。

决策：
- 使用 `harness/project-manifest.json` 注册项目组件、组件门禁、full-stack E2E、供应链目标和生产就绪工件。
- 使用 `harness/agent-policy.json` 定义最小权限的文件系统、网络、凭据、工具、审批和资源上限默认值。
- 只在 `framework` 和 `adoption` 中允许空组件目标；`project` 和 `release` 检查必须 fail closed。
- 为标准检查记录命令、退出码、commit、worktree fingerprint 和日志证据。
- release 模式必须具备真实组件、CODEOWNERS、架构测试、安全命令、SBOM 命令、full-stack E2E 和生产就绪工件。

影响：
- adoption 必须在业务实现可通过 project 门禁前填充 manifest。
- 发布候选不能因静默跳过缺失目标而通过。
- Agent policy、CI 工作流和发布控制成为受保护的高影响面。
- 技术栈仍由具体项目选择，但每个必需门禁都必须注册且可执行。

备选方案：
- 继续目录发现并只输出 warning：拒绝，因为 warning 不能阻止 false-green 发布。
- 在 shell 脚本中硬编码一套前端和后端技术栈：拒绝，因为 starter 必须支持不同企业架构，同时不能弱化必需结果。

## ADR-20260626-01: Project Activation 前使用受控 Adoption 工作区

状态：Accepted

背景：
- Greenfield 项目通常从不完整产品意向开始，而不是完整的企业级 PRD。
- 如果 AI agent 把不完整假设直接写进 product-spec，后续实现可能看似合规，却编码了未经确认的产品决策。
- starter 需要可重复的方式，把原始想法转成持久事实，并在业务实现开始前设置确定性门禁。

决策：
- 新增 `docs/adoption/`，作为初始意向、discovery ledger 和 spec readiness 的非事实源工作区。
- 新增 `harness/adoption-state.json`，记录 adoption 子阶段和显式 activation 确认。
- 新增 `start-project`、`adoption-status`、`adoption-check` 和 `activate-project` 脚本。
- 从 `adoption` 切换到 `project` 前，必须通过 `adoption-check --activation` 并获得用户显式批准。
- 未确认假设留在 adoption 工作区；只有已确认内容才能转写到 product-spec、ADR、open decisions、验证矩阵或 project manifest。

影响：
- 新项目可以从不完整意向开始，而不会污染持久事实源。
- Agent discovery 成为每轮 3-7 个高优先级问题的有界循环。
- 如果仍有占位符、阻塞 open decision、缺失 readiness 行、缺失验证矩阵行或缺失 component manifest 项，project activation 必须 fail closed。
- Adoption 记录仍是有用证据，但实现只能依赖 product-spec 和 engineering 事实源。

备选方案：
- 把初始用户意向直接写入 product-spec：拒绝，因为原始想法和假设会与已确认事实无法区分。
- 要求用户在 agent 开始前填完整 PRD 模板：拒绝，因为会拖慢 discovery，并鼓励低质量填充。
- 让 agent 在自认为 spec 完整时自行 activation：拒绝，因为 activation 会改变业务实现的授权边界。

## ADR-20260626-02: Phase 1 优先原生 macOS 录制

状态：Accepted

背景：
- 产品是 Phase 1 面向个人自用的本地 macOS 会议助手。
- 用户比较过 OBS/BlackHole/FFmpeg 辅助录制路线和原生 macOS 录制路线。
- 辅助录制能更快验证流水线，但用户选择原生 macOS 录制作为第一条纵切。

决策：
- Phase 1 以原生 macOS 录制作为主要 capture 路线。
- OBS 和 BlackHole 不是 MVP 主 capture 依赖。
- capture 层必须输出 `07-data-and-events.md` 定义的文件和元数据契约。
- 具体低层 capture API 和依赖/runtime 选择仍是实现缺口；UI/control surface、媒体策略和 activation 骨架计划由 ADR-20260626-06 确定。

影响：
- 产品范围和验收标准必须验证原生录制，而不是只验证导入媒体或辅助录制。
- 实现指导必须面向 Apple Silicon 和已确认的当前宿主 macOS baseline。
- activation 需要组件骨架和验证计划，以执行原生 capture 行为或清晰限定的测试替代方案。

备选方案：
- OBS/BlackHole/FFmpeg 辅助录制优先：Phase 1 已按用户决策拒绝，但如果原生 capture 不可行，可作为后续 fallback。
- 仅导入媒体并转写优先：拒绝作为主切片，因为它不能验证核心录制目标。

## ADR-20260626-03: 在 Capture、Processing 和 Export 之间使用文件与元数据边界

状态：Accepted

背景：
- 用户偏好模块化、分步骤开发，不希望起步就是大型一体化产品。
- 会议媒体、transcript 生成、speaker labeling 和导出有不同的风险画像和依赖。

决策：
- 使用文件和元数据作为 recording、media processing、transcription、speaker labeling 和 export 之间的主要边界。
- 保留原始视频和音频产物；派生 transcript、speaker labels 和 export 可以重新生成。
- 保持模块可替换，使 native capture、transcription runtime 和 speaker labeling engine 能独立演进。

影响：
- `02-domain-model.md` 和 `07-data-and-events.md` 定义稳定 artifact 和 workspace metadata。
- 测试和验证矩阵必须验证 artifact 持久化，并验证派生处理不会覆盖原始媒体。
- 如果 artifact contract 保持稳定，未来 UI 或 native capture 变化不应要求重写 transcription/export 流水线。

备选方案：
- 存储隐式内存状态的单体桌面 app：拒绝，因为它过早耦合录制和 AI 处理。
- 远程数据库优先设计：Phase 1 拒绝，因为产品是 local-first 个人使用。

## ADR-20260626-04: 为 MVP 依赖使用 Bootstrap 和 Check 脚本

状态：Accepted

背景：
- 产品依赖本地平台能力、媒体工具、transcription runtime，可能还依赖 speaker labeling runtime。
- 用户选择 bootstrap/check 脚本策略，而不是纯手动安装或把所有依赖打包进应用。

决策：
- Phase 1 使用 bootstrap/check 脚本检测本地前置条件、依赖可用性、模型/runtime 路径、workspace 可写性和权限。
- 脚本应指导用户，但不得静默修改系统音频路由或上传数据。
- 具体依赖和命令名在组件骨架创建并注册到 `harness/project-manifest.json` 时最终确定。

影响：
- 工程命令必须在 project activation 前包含可重复的 dependency check。
- 缺失依赖必须明确失败，不能被当作跳过成功。
- 打包所有依赖推迟到产品化或团队分发确认后。

备选方案：
- 纯手动 setup：拒绝，因为更难验证和支持。
- 立即打包全部依赖：拒绝，因为在 MVP 流水线验证前引入了打包和许可证成本。

## ADR-20260626-05: MVP 中外部 GPT 使用必须由用户主动发起

状态：Accepted

背景：
- 会议纪要生成是 MVP 可选项。
- 用户确认可以手动复制 transcript 文本到 GPT。
- 自动外部模型集成会引入 API 契约、凭据、隐私和合规要求。

决策：
- MVP 可以支持 transcript copy/export，供用户主动使用外部工具。
- MVP 应用代码不得自动上传 transcript、音频或视频到 GPT 或其他外部模型 API。
- 除非未来决策更新 API、安全和隐私事实，否则自动会议纪要生成保持范围外。

影响：
- `06-api-contracts.md` 不为 MVP 定义外部 LLM API 调用。
- `13-security-and-compliance.md` 必须把外部 GPT 使用视为用户控制的导出边界。
- 未来本地 Qwen 或云端 GPT 集成需要新的 spec sync，并且很可能需要 ADR。

备选方案：
- 严格离线且不允许外部复制：拒绝，因为用户明确允许手动 GPT copy。
- 内置云 API 纪要：MVP 拒绝，因为会增加尚未确认的安全和凭据范围。

## ADR-20260626-06: Activation 使用最小原生 App 加 Processing CLI 骨架

状态：Accepted

背景：
- 用户确认 Phase 1 应优先原生 macOS 录制。
- Project activation 需要真实组件骨架、命令和 E2E 计划，但 adoption 模式不得实现业务行为。
- 媒体处理、transcription、speaker labeling 和 export 应与录制 UI 保持解耦。

决策：
- 使用最小 Swift/SwiftUI app 作为可见原生录制控制面。
- 使用 local helper / processing CLI 边界承载 dependency check、artifact processing、transcription adapter、speaker-label adapter 和 export。
- Activation-time skeleton 可以包含 `native-app` 和 `processing-cli`，但在 project 模式前不得实现真实 recording、transcription 或 speaker-labeling 行为。
- 保留原始录制格式，并为下游处理生成标准化 `.wav` `normalized_audio` artifact。
- 先使用 transcription adapter 契约，再锁定具体 runtime；现有本地 Whisper 可以作为第一个候选 adapter。
- 当没有可用本地引擎时，允许 speaker-labeling 降级为 transcript-only。
- 个人 MVP 默认 workspace 是 `~/Movies/MeetingAssistant/`，明文存储，delete-session 删除会话本地 artifact；应用级加密后置。
- 依赖优先使用允许来源和人工安装。bootstrap/check 脚本不自动下载模型、二进制或驱动。

影响：
- `04-user-journeys-and-ui.md`、`08-implementation-guidance.md` 和 `12-ui-ux-design.md` 定义 app + helper 边界。
- `07-data-and-events.md` 定义原始 artifact 保留和 `.wav` normalized audio。
- `06-api-contracts.md` 通过 command/adapter 契约隔离 transcription 和 speaker labeling。
- `13-security-and-compliance.md`、`docs/engineering/10-security-and-supply-chain.md` 和 `harness/agent-policy.json` 约束依赖获取必须人工且边界清晰。
- Manifest 和 E2E 门禁仍需要非业务骨架，activation 才能通过。

备选方案：
- 仅 native app：拒绝，因为 processing、dependency check 和 adapter 会与 UI 耦合过紧。
- 仅 CLI/helper：拒绝，因为 macOS 权限和录制状态需要可见的原生控制面。
- 在骨架前锁定具体 transcription 和 diarization runtime：拒绝，因为这会在 command contract 稳定前让模型/runtime 选择成为 blocker。
- 自动下载依赖：MVP 拒绝，因为会扩大网络、模型 provenance 和 agent-policy 范围。
