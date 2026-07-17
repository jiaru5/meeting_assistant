# 12. UI/UX 设计

本文件定义 UI/UX、可访问性、交互状态和测试定位契约。页面或本地工具业务范围来自 `04-user-journeys-and-ui.md`。

## UI 状态

Phase 1 控制面已确认为设计化 Swift/SwiftUI native app shell + local helper / processing CLI 的组合。图形入口负责原生录制控制和用户可见状态；helper/CLI 负责依赖检查、媒体处理、转写、speaker labeling 和导出。当前只有功能和调试价值的 primitive native UI 只能作为中间实现或测试 fixture，不能作为 `CAP-MA-013` 的完成口径。

## UI 原则

1. UI 或本地控制入口必须服务于实际录制、处理和导出工作流，不做营销页。
2. MVP 以清晰状态和可恢复错误为主，避免隐藏权限、依赖或处理失败。
3. 录制中状态必须稳定可见，防止用户不知道是否正在录制。
4. transcript 回查必须强调匿名 speaker labels 不是实名识别。
5. 复制或导出 transcript 到外部 GPT 工具必须是用户主动行为。

## 关键交互契约

| UI ID | 场景 | 规则 | 覆盖能力 | 验证入口 |
|---|---|---|---|---|
| UI-MA-RECORD-001 | 原生录制控制 | 开始、停止、录制中、失败和降级状态必须可区分 | `CAP-MA-002`, `CAP-MA-003` | `PV-MA-002`, `PV-MA-003` |
| UI-MA-PERMISSION-001 | macOS 权限缺失 | 明确显示缺失权限和用户修复路径，不开始对应录制 | `CAP-MA-001` | `PV-MA-001` |
| UI-MA-DEPS-001 | 依赖检查 | 显示缺失依赖、版本、模型路径或不可用能力 | `CAP-MA-005` | `PV-MA-005` |
| UI-MA-PROCESSING-001 | 处理状态 | 显示标准化音频、转写、speaker labeling 的处理中、失败、可重试或完成状态 | `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-008`, `CAP-MA-009` | `PV-MA-006`, `PV-MA-007`, `PV-MA-008`, `PV-MA-009` |
| UI-MA-TRANSCRIPT-001 | transcript 回查 | 显示时间戳、文本和匿名 speaker labels 或 transcript-only 降级原因 | `CAP-MA-010` | `PV-MA-010` |
| UI-MA-EXPORT-001 | transcript 复制/导出 | 明确由用户触发，不自动上传外部服务；生产 app 复制写入 macOS pasteboard，导出通过用户确认的保存目标，XCTest fixture 可注入 memory clipboard 和 deterministic target | `CAP-MA-011` | `PV-MA-011` |
| UI-MA-FALLBACK-001 | speaker labeling 降级 | 无可用引擎时显示 transcript-only 状态和原因 | `CAP-MA-008` | `PV-MA-008` |
| UI-MA-DELETE-001 | 删除会话 | 删除前显示目标会话和影响范围，要求用户明确确认；删除后显示结果摘要 | `CAP-MA-012` | `PV-MA-012` |
| UI-MA-SHELL-001 | 设计化原生 app shell | 同一原生 shell 覆盖预检、录制、artifacts、处理、transcript、导出和删除；主要操作必须触发现有 command/helper/adapter 契约，不使用 UI-only mock success | `CAP-MA-001`-`CAP-MA-013` | `PV-MA-013` |
| UI-MA-TASK-FLOW-001 | MVP.1 任务式个人工作流 | Meetings、New recording、Meeting detail 和 Settings/diagnostics 按 current session 和状态编排既有能力；一次只呈现当前任务和一个上下文主操作，最近会议可重开且技术详情渐进披露 | `CAP-MA-014` | `PV-MA-014` |

## 设计化原生 App Shell

设计目标是可长期使用的 native macOS 工作台，而不是营销页、Web mock、调试面板或仅为测试暴露的控件集合。视觉效果图和 `output/product/meeting-assistant-ui-ux-prd.html` 等 derived artifact 可以作为实现参考，但不是事实源；若参考图与本分卷冲突，以本分卷为准。

视觉和信息层级要求：

1. 默认使用浅色、中性、高对比 UI，状态色只用于 ready、warning、error、recording、fallback 和 success 等明确语义。
2. 页面应面向重复操作和状态扫描：保留紧凑信息密度、清晰分组、稳定主操作区和可见结果区，不做 hero/landing 页面。
3. 控件圆角和间距应克制，并优先使用原生 macOS 控件语义；不得让装饰性卡片层级盖过权限、依赖、录制和处理状态。
4. 主视图应支持一个稳定的导航模型，至少能进入 Preflight、Record meeting、Recent/session artifacts、Processing、Transcript、Exports/Delete 这些语义区域。
5. 文案必须说明状态和下一步动作，不能用泛化错误替代 `permission_denied`、`dependency_missing`、`capture_failed`、`processing_failed`、`path_conflict` 等既有错误语义。

必须覆盖的 shell 状态：

1. Preflight：展示 workspace、macOS 权限、media tool、transcription runtime/model、speaker fallback 和 no-auto-upload/no-auto-download 边界。
2. Recording setup：展示录制目标、系统音频和麦克风录制意图，以及开始录制前的阻断状态。
3. Recording live：录制中状态、session id 或可识别会话摘要、可见停止动作和音轨/目标摘要必须稳定可见。
4. Saved artifacts：停止后展示每类 artifact 的 available、missing、degraded 或 failed 状态，包含 `degradation_reason` 摘要和进入处理动作。
5. Processing：展示 normalized audio、transcript、speaker labeling、export 准备等步骤，支持失败、重试和 transcript-only fallback。
6. Transcript：展示 timestamped segments、文本、匿名 speaker labels 或降级原因，不暗示真实身份识别。
7. Export/Delete：复制、导出和删除必须由用户主动触发；删除确认必须展示目标会话和影响范围。

命令触发和测试边界：

1. 生产目标 shell 的主按钮必须调用既有 `06-api-contracts.md` 和 `07-data-and-events.md` 定义的 command/helper/adapter 或其 read model，不得在 UI 层制造与文件契约无关的成功状态。
2. 生产 app 的 transcript copy/export OS 边界必须位于注入协议后：copy 只在 `export_transcript` 成功返回可复制文本后写入 macOS pasteboard，export 只在用户确认保存目标后把该目标传给 `export_transcript`；Debug/XCTest fixture 继续使用 memory clipboard 和 deterministic target。
3. 非 XCTest app runtime 的 recording command client 默认使用 `NativeRecordingCommandClient` + Apple ScreenCaptureKit adapter；Debug/XCTest fake、controlled 或 opt-in real smoke hook 只允许测试路径使用，不能把 production 默认路径降级为 fake。
4. 非 XCTest app runtime 的 processing 和 transcript action command client 默认使用本地 process runner，分别调用既有 `generate_transcript` / `generate_speaker_labels` 和 `export_transcript` / `delete_session` 契约；显式 fake client hook 只允许 Debug/XCTest fixture 使用。
5. Debug/XCTest fixture 可以驱动 deterministic 状态和 fake client，但必须通过 build configuration、environment hook 或 test-only fixture 隔离；Release 默认行为不得依赖这些 hook。
6. 设计化 shell 的完成不能替代真实 native capture、真实 processing provider、完整 release bundle 或任意 `PV-MA-*` covered 证据；delete 仍必须通过 `delete_session` 契约执行，不得在 UI 层直接删除任意文件。
7. 每个 shell 区域必须有 XCUITest 可查询的 accessibility identifier，建议使用 `ma.preflight.*`、`ma.recording.*`、`ma.sessionArtifact.*`、`ma.processing.*`、`ma.transcript.*`、`ma.transcriptAction.*` 这类现有语义前缀。
8. 新视觉层不得删除既有可见状态、accessible name 或稳定 locator；重命名 locator 必须同步测试、验证矩阵和交付说明。

## MVP.1 产品体验契约

MVP.1 的目标不是给既有控制面换皮，而是让用户围绕会议任务工作。Preflight、Record meeting、Session artifacts、Processing、Transcript 和 Export/Delete 仍是必须覆盖的语义区域，但可以按状态组合到 Meetings、New recording、Meeting detail 和 Settings/diagnostics 中，不要求同时平铺。

信息架构和主操作：

1. 只能有一套稳定主导航；默认入口是 Meetings，主导航同时提供 New recording 和 Settings/diagnostics。
2. Meetings 的空状态必须有明确的新建录制动作；最近会议行至少显示用户可读标题或开始时间、会话状态、时长或产物摘要和 transcript 可用性，并可重新打开同一会话。
3. New recording 必须使用原生表单控件承载可选标题、当前支持的录制目标、系统音频和麦克风意图。不可用的 target 不得伪装成可选成功路径；录制 readiness 只按当前捕获意图计算，麦克风关闭时麦克风拒绝不阻断，processing 依赖缺失也不阻断录制。
4. Recording live 必须使用独立的专注状态，持续显示录制指示、已录制时长、目标/音轨摘要和唯一突出的 Stop；其他会话动作不得与 Stop 等权。
5. Saved 状态必须先解释成功、降级或缺失产物，再突出“生成 transcript”；不得自动触发 processing。存在 `mixed_audio` 时默认选择它；真正未登记 `mixed_audio` 时以用户语言呈现通过安全校验的 `normalized_audio`，或列出可用原始音频并要求用户确认处理输入。已登记但损坏的首选输入不得被当成“缺失”后静默回退。
6. Processing 使用同一会话 detail，展示整体进度、原始媒体安全边界和失败恢复；成功或 transcript-only 降级后进入 transcript 成果视图。失败重试沿用已确认的同一输入；已有 `normalized_audio` 时不得继续展示会触发 `path_conflict` 的换源入口，除非未来契约增加显式 replace confirmation。
7. Transcript 是主要成果页：时间戳、匿名 speaker label 和正文形成稳定层级；匿名身份免责声明是页面级提示，不在每段重复；Copy/Export 放在滚动长 transcript 时仍保持可见的稳定 toolbar，segments 使用惰性容器；Delete 放在次级 destructive menu 或区域。
8. 原始 session id、artifact type、命令名、错误码、runtime/model 路径和绝对文件路径只能在显式展开的 Technical details 或 Settings/diagnostics 中出现。测试 locator 可以继续使用英文稳定标识，但不得成为默认用户文案。

上下文状态与恢复：

1. 任何时候都必须能用一个短句回答当前状态，并用一个明显动作回答下一步。
2. blocked、failed、missing 和 degraded 状态必须同时表达：发生了什么、哪些数据仍安全、用户可以做什么。可恢复场景提供 Open Settings、Check again、Retry、Choose meeting 或 Start a new recording 中的适用动作。
3. Open Settings 必须匹配实际缺失权限：Screen Recording 和 Microphone 分别进入对应 macOS Privacy 面板；不能用同一个 Screen Recording 链接处理所有权限错误。
4. 录制开始失败允许修改设置后重试；停止保存失败必须保留当前 session 并允许再次停止或明确安全退出，不能把唯一恢复路径藏在 diagnostics。
5. 重新打开持久状态为 `processing` 的会话时，不得永久显示为不可恢复；当前 App 内没有活动任务且安全音频仍可用时，显示“上次处理被中断”并提供重新选择音频和重试。
6. transcript 读取失败必须是持久错误状态，并提供重新加载或返回 Meetings；不能静默保持旧 transcript 或空白页。已登记 transcript 需要文件修复时，不得以“重新生成”替代尚未定义的 replace/repair 契约。文件读取、JSON 解码和 checksum 校验在后台执行，加载期间显示持久状态并拒绝旧会话结果覆盖当前会话。
7. 删除确认只出现一套，明确显示用户可读会话标题、受影响的 workspace 内数据和 workspace 外导出保留；成功后不得继续显示旧 session 的处理、transcript 或 action 控件。
8. 进行中状态、阻断状态和 destructive 状态使用原生语义色及 control role；普通信息不使用状态色制造噪音。

任务级可测试性：

1. 新入口使用 `ma.meetings.*`、`ma.newRecording.*`、`ma.meetingDetail.*` 和 `ma.diagnostics.*` 语义前缀；既有 command 按钮 identifier 可保留，避免破坏真实本机 smoke。
2. XCUITest 必须证明一次只存在一个可点击主操作；不只断言所有控件都存在。
3. 关键任务 fixture 至少覆盖空 workspace、ready、capture-ready/processing-blocked、麦克风意图开关、blocked、recording、saved/degraded、fallback 音频选择、processing、processing failed/retry、historical processing recovery、transcript available、长 transcript、history reopen 和 delete reset。
4. 可选截图证据覆盖 Meetings empty/recent、New recording、Recording live、Saved、Processing、Transcript 和 Diagnostics；截图只能辅助层级审查，不能替代任务和状态断言。

### MVP.1 人工体验研究（可选）

任务级自动化仍须按工程策略生成并结构校验关键截图；当前 local-direct MVP 不要求完成这些截图的真人视觉审查，也不要求完成真实窗口 VoiceOver/键盘走查或 3–5 名真人任务研究，才可关闭 `PV-MA-014`。这些是后续质量研究，未执行时不得宣称已经观察到主观易用性或辅助技术体验。若开展研究，必须保留真实人工声明和 finding 记录；P0/P1 按正常缺陷修复、复测。下列可访问性产品行为本身仍是必需要求，不能因人工走查改为可选。

## 页面或本地工具状态要求

每个主要入口至少定义：

1. 就绪。
2. 权限缺失。
3. 依赖缺失。
4. 录制中。
5. 停止/保存中。
6. 处理中。
7. 产物降级。
8. 失败并提供重试指引。
9. transcript 可用。
10. 导出成功/失败。
11. 删除确认/成功/失败。

## 可访问性

如果采用图形 UI：

1. 每个窗口或主视图有唯一主 heading 或可访问标题。
2. 开始/停止录制控件有清晰 accessible name。
3. 图标按钮有 accessible name 或 tooltip。
4. 错误和状态变化对屏幕阅读器可见。
5. 键盘可触发核心操作或有等价菜单命令。

## Locator 规范

如果引入自动化 UI 测试，优先使用用户语义 locator：

1. `getByRole("button", { name })`
2. `getByRole("heading", { name })`
3. `getByText()` 用于稳定状态文案
4. `getByLabelText(name)`

只有无法表达业务语义时，才使用 `data-testid`，并在测试中说明原因。

对于 SwiftUI 原生界面，等价规则是使用可访问标题、button accessible name、label、状态文本和 XCUITest 可查询的 accessibility identifier。accessibility identifier 只能辅助稳定定位，不能替代用户可见或屏幕阅读器可理解的状态表达。

## SwiftUI 和 XCUITest 可测试性

原生 UI 状态必须能被 Swift Testing 和 XCUITest 稳定断言：

1. 每个核心操作控件必须同时具备用户可理解的 accessible name 和稳定 accessibility identifier；identifier 使用 `ma.<surface>.<role>` 形式，例如 `ma.record.startButton`。
2. 每个关键状态必须有稳定可见文案或状态 label，至少覆盖 ready、permission missing、dependency missing、recording、saving、processing、degraded、failed、transcript available、export success/failure 和 delete confirm/success/failure。
3. 状态文案可以随产品语言润色，但同一状态的语义 code、accessible label 和测试 locator 必须稳定；修改时必须同步更新 XCUITest 或 Swift Testing。
4. 权限缺失、依赖缺失、speaker-label transcript-only 降级、导出失败和删除失败不得只通过 transient toast 表达；必须有测试可查询的持久状态或结果区域。
5. 时间、路径和会话标题在 UI 测试中必须可注入 fixture 或稳定格式；测试不得依赖当前真实时间、用户主目录绝对路径或本机已有会议数据。
6. 删除确认 UI 必须在可访问文本中包含目标会话标识或标题和影响范围，并提供可测试的 confirm 与 cancel 控件。
