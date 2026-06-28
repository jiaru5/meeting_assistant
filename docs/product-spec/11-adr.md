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
- 打包所有依赖推迟到产品化分发确认后。

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

## ADR-20260626-07: Phase 2 使用本地组件纵切和原生 UI 测试

状态：Accepted

背景：
- Project activation 后，`native-app` 和 `processing-cli` 已存在为非业务 skeleton，但产品行为验证矩阵仍为 `planned`。
- Meeting Assistant Phase 1 是本地 macOS 工具，不是 Web/API/数据库系统；继续沿用通用 web/backend/db Phase 2 会制造错误的实现方向。
- 原生 macOS capture 是主路径，但系统音频 capture 可能存在平台能力和权限限制，需要在不破坏 native-first 决策的前提下定义 fallback 治理。

决策：
- Phase 2 改为 `processing-cli` 命令契约优先，再接最小 `native-app` Swift/SwiftUI 控制面的本地纵切。
- `processing-cli` 先落地 `check_dependencies`、稳定 JSON 响应、错误码、artifact contract、adapter fake、speaker-label transcript-only fallback 和导出契约。
- 原生 UI 自动化使用 Swift Testing 覆盖状态和 view model，使用 XCUITest 覆盖 SwiftUI 关键用户状态；Playwright 只在未来引入 Web UI 时使用。
- 原生 macOS 录制仍为主路径；辅助 capture adapter 只能在技术 spike 证明 native capture 不可行或不稳定后，经 spec-change、ADR 和验证矩阵更新纳入。

影响：
- `docs/engineering/07-development-plan.md` 不再把 Phase 2 定义为通用 Web/后端/数据库纵切。
- `docs/engineering/03-test-strategy.md` 需要包含 Processing CLI、Swift Testing 和 XCUITest 的项目测试分层。
- `docs/engineering/06-product-validation-matrix.md` 必须按真实本地组件证据推进 `PV-MA-*`，不能把 skeleton smoke 当作产品覆盖。
- `docs/product-spec/06-api-contracts.md` 需要细化 `check_dependencies` 的稳定响应和缺失依赖失败语义。

备选方案：
- 先创建 Web 前端、远程后端服务和数据库：拒绝，因为 Phase 1 产品事实是本地 macOS 文件化工具。
- 使用 Playwright 作为当前原生 UI 主测试工具：拒绝，因为当前没有 Web UI，SwiftUI 状态应通过 Swift/XCTest 体系验证。
- 在代码中直接切换到 OBS/BlackHole/FFmpeg 主录制：拒绝，因为这会绕开已确认的 native-first 产品决策。

## ADR-20260627-01: VS-MA-06 使用 whisper.cpp 和 Multilingual Whisper 模型

状态：Accepted

背景：
- `generate_transcript` 的 fake adapter 契约已经建立，但 `PV-MA-007` 仍需要真实本地 runtime smoke 才能进入 covered。
- 会议语音以中文为主，常夹杂 `HTTP`、`LLM`、`clean architecture`、`EDA` 等英文技术词汇；English-only 转写模型不能覆盖该产品场景。
- MVP 仍是本地优先工具，不允许自动下载模型、二进制或调用外部模型 API。

决策：
- VS-MA-06 的首个真实 transcription runtime 固定为 `runtime=whisper_cpp`。
- `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME` 指向用户本机的 `whisper.cpp` CLI 可执行文件或可解析命令名。
- `MEETING_ASSISTANT_TRANSCRIPTION_MODEL` 指向用户人工准备的本地 Whisper-compatible multilingual 模型文件。
- 真实 smoke 和 `PV-MA-007` covered 证据必须使用 multilingual 模型并覆盖中英混合技术词汇；English-only `.en` 模型不能作为完整覆盖证据。
- fake adapter 继续作为确定性契约测试替身；fake adapter 证据不能替代真实 runtime covered 证据。
- runtime 或模型缺失时 fail closed，按 `06-api-contracts.md` 返回 `dependency_missing`；非法 runtime 返回 `invalid_input`；runtime 执行或输出解析失败返回 `processing_failed`。

影响：
- `06-api-contracts.md` 固定 `runtime=whisper_cpp`、本地配置字段和错误语义。
- `08-implementation-guidance.md` 和 `13-security-and-compliance.md` 约束人工安装、无自动下载、无外部 API 和 multilingual 模型要求。
- `06-product-validation-matrix.md` 中 `PV-MA-007` 在真实 runtime smoke 和标准门禁落地前保持 `partial`。

备选方案：
- 继续保持未指定“本地 Whisper”候选：拒绝，因为无法定义 runtime 缺失、模型路径和验证边界。
- 使用 English-only `.en` Whisper 模型：拒绝，因为不能覆盖中英混合会议语音。
- 自动下载模型或二进制：MVP 拒绝，因为会扩大供应链、许可证和 agent 权限范围。
- 外部云转写 API：MVP 拒绝，因为会改变隐私、API、凭据和合规边界。

## ADR-20260627-02: Whisper 部署前增加非敏感硬件 Preflight

状态：Accepted

背景：
- VS-MA-06 已选择本地 `whisper.cpp` CLI 和用户人工准备的 multilingual Whisper 模型。
- 用户的会议场景需要处理中英混合语音，推荐模型等级是 `large-v3` 或 `large-v3-turbo` 同级本地模型。
- 部署模型前需要知道当前 Mac 是否适合所选模型，但安全规范禁止输出序列号、硬件 UUID、UDID 等设备唯一标识。

决策：
- `check_dependencies` 增加 `transcription.hardware` 检查项，报告 CPU 架构、芯片名称、内存等级和所选模型等级。
- Apple Silicon `arm64` 且 16 GB 及以上 unified memory 可作为 `large-v3`、`large-v3-turbo` 同级 multilingual 模型的 preflight 通过条件。
- Apple Silicon 8 GB 到 16 GB 之间报告 `constrained`，低于 8 GB 或非 Apple Silicon 对推荐模型等级报告 `unsupported`。
- 硬件 preflight 只作为部署风险判断，不替代真实模型加载、mixed-language runtime smoke、模型来源、license/hash 或 provenance 审查。

影响：
- `06-api-contracts.md` 定义 `check_dependencies` 的 `transcription.hardware` 响应语义。
- `08-implementation-guidance.md` 定义本地硬件 preflight 策略。
- `13-security-and-compliance.md` 和 `10-security-and-supply-chain.md` 限制硬件摘要不得包含设备唯一标识。
- `06-product-validation-matrix.md` 中 `PV-MA-005` 可记录硬件 preflight 自动化证据；`PV-MA-007` 在真实 multilingual mixed-language smoke 前仍保持 `partial`。

备选方案：
- 不做硬件检查：拒绝，因为部署真实模型前无法向用户解释可运行性风险。
- 使用 `system_profiler` 完整输出作为 evidence：拒绝，因为其中可能包含序列号、硬件 UUID 和 Provisioning UDID。
- 用硬件 preflight 直接推进 `PV-MA-007` covered：拒绝，因为它不能证明真实转写质量或 mixed-language 术语识别。

## ADR-20260627-03: 本机共享 Whisper Runtime、模型和 ASR Fixture 目录

状态：Accepted

背景：
- 正式 `whisper.cpp` runtime、multilingual Whisper 模型和 mixed-language smoke WAV 未来会被 `meeting_assistant` 之外的本地项目复用。
- 大型模型和本地工具不应放在单个项目仓库或项目 `.tools` 目录中，避免重复占用磁盘、误提交和项目之间路径耦合。
- MVP 仍坚持人工准备依赖，不允许 agent 或应用自动下载模型、二进制或外部脚本。

决策：
- 用户级共享 runtime 版本目录为 `~/.local/opt/whisper.cpp/<version>/bin/whisper-cli`。
- 当前 runtime 入口为 `~/.local/bin/whisper-cli` symlink，指向已人工准备和验证的版本目录。
- Whisper 模型目录为 `~/.local/share/ai-models/whisper.cpp/<model-family>/`，例如 `large-v3-turbo/` 或 `large-v3/`。
- 中英混合 ASR smoke fixture 路径为 `~/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav`。
- `generate_transcript runtime=whisper_cpp` 仍必须由 `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME` 和 `MEETING_ASSISTANT_TRANSCRIPTION_MODEL` 显式指定路径；共享目录约定不是自动发现、自动下载或自动安装机制。

影响：
- `06-api-contracts.md` 和 `08-implementation-guidance.md` 记录推荐路径和显式配置边界。
- `13-security-and-compliance.md` 和 `10-security-and-supply-chain.md` 明确大型模型和 fixture 不进入项目仓库、缓存目录或真实会议 workspace。
- `check_dependencies` 可以在缺失 runtime/model 时提示推荐路径，但不能自动创建 symlink 或复制模型。
- `PV-MA-007` covered 条件不变：仍需要真实 multilingual mixed-language smoke 纳入标准门禁。

备选方案：
- 放入 `meeting_assistant/.tools`：拒绝，因为 runtime 和模型会被多个项目复用，且会把大型资产耦合到单个项目。
- 放入 `/opt/homebrew` 或 `/usr/local`：拒绝作为手工默认路径，因为权限和包管理边界更复杂；Homebrew 可管理 runtime，但模型仍不应放入包管理目录。
- 放入 `Downloads`、`Desktop` 或 `Library/Caches`：拒绝，因为容易被清理、误删或混入临时文件。

## ADR-20260628-01: 不提供团队分发或团队支持

状态：Accepted

背景：
- `OD-MA-008` 原本保留“少量团队内部使用如何分发和支持”的 watch 决策。
- 用户确认当前使用方式是各自在本地运行，不存在团队分发或团队支持。
- 团队账号、共享空间、集中审计、安装分发和支持流程会改变产品范围、权限模型、安全边界和生产就绪要求。

决策：
- `meeting_assistant` 当前不提供团队分发、团队支持、团队账号、组织空间、共享会议库或集中审计。
- 多人使用时，每个使用者都是自己 Mac 上的 `local_os_user`，各自独立管理 workspace、依赖、模型路径、导出文件和本地问题排查。
- 未来如重新提出团队协作、共享、分发或集中支持，必须先通过 spec-change 更新主责分卷、ADR、安全和验证矩阵，不得把个人本地访问模型直接复用为团队权限模型。

影响：
- `01-product-scope.md` 将团队内部使用从后续范围收敛为“本地各自运行”。
- `03-permissions-and-identity.md` 不再保留 `future_internal_user` 作为当前角色或身份。
- `13-security-and-compliance.md` 不再把团队共享审计或团队支持作为当前后续默认增强，只保留产品化、商业化分发、跨设备共享或集中服务的重新审查触发。
- `docs/engineering/07-development-plan.md` 的后续纵切从团队内部分发准备调整为产品化分发准备。

备选方案：
- 共享安装包或私有团队分发：拒绝，因为当前没有团队分发和支持需求。
- 签名公证后统一分发：当前拒绝，保留为未来产品化分发诉求。
- 团队共享 workspace 或组织账号：拒绝，因为会引入新的权限、数据隔离、审计和支持边界。
