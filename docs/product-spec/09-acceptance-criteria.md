# 9. 验收标准

本文件定义产品验收标准。验证覆盖状态由 `docs/engineering/06-product-validation-matrix.md` 维护。

## 完成定义

一个产品行为只有同时满足以下条件，才能视为完成：

1. 对应事实源已更新或确认不需要更新。
2. 对应验收标准存在。
3. 验证矩阵有对应行。
4. 关键路径有自动化验证，状态达到 `covered`。
5. 本地依赖、模型和权限检查必须可重复执行，不能在缺失依赖时报告成功。
6. 交付说明记录实际运行的命令和结果。

## MVP 验收标准

| AC ID | 能力 | 前置条件 | 操作 | 期望结果 | 验证矩阵 |
|---|---|---|---|---|---|
| AC-MA-001 | 录制前权限和环境预检 | Apple Silicon Mac，macOS 26.5.1，用户打开 Swift/SwiftUI app 或运行依赖检查 | 系统检查录屏、麦克风、文件写入、workspace、工具链和关键本地依赖状态 | 缺失项明确失败并只阻断对应操作：录屏或 workspace 写入缺失阻断原生录制；麦克风拒绝只在用户启用麦克风意图时阻断；FFmpeg、转写 runtime/model 缺失阻断 processing 但不阻断可安全保存的录制；UI 或命令输出指出缺失项和对应修复入口，不静默开始被阻断的操作 | `PV-MA-001` |
| AC-MA-002 | 原生录制启动、持续状态和停止保存 | 与当前录制目标和音轨意图对应的捕获检查通过，或缺失项已被用户修复 | 用户通过 Swift/SwiftUI app 启动原生录制并停止 | 创建 `MeetingSession`，状态从 `created` 进入 `recording` 再进入 `recorded` 或明确失败；录制中状态持续可见；停止后给出保存结果；processing 依赖未就绪不得阻止录制落盘 | `PV-MA-002` |
| AC-MA-003 | 会话和录制产物登记 | 原生录制结束，至少一个媒体产物可用或某类产物明确失败 | 系统登记录制结果 | 写入 `session.json` 和 artifact 列表；`screen_video`、`system_audio`、`microphone_audio`、`mixed_audio` 按可用性登记；无法生成的目标产物必须有 `capture_status` 和 `degradation_reason` | `PV-MA-003` |
| AC-MA-004 | 导入已有媒体作为回退或测试路径 | 用户有本地媒体文件，且文件路径由用户显式选择 | 用户运行 `import_media` | 创建 `source_type=imported_media` 的 `MeetingSession`；只接受 `.wav`、`.m4a`、`.mp3`、`.mp4`、`.mov` 本地文件；音频登记为 `mixed_audio`，视频/容器登记为 `screen_video`；workspace 保存会话内 artifact 副本且源文件不被覆盖；不自动扫描、下载、上传、转码、转写或识别说话人；不支持格式、目录、缺失或非法路径返回 `invalid_input` | `PV-MA-004` |
| AC-MA-005 | 本地依赖检查 | 新环境、依赖变化或处理前检查 | 用户运行 `check_dependencies`，自动化验证使用 `format=json` | 输出 macOS/架构、Swift 工具链、媒体工具、transcription adapter/runtime、speaker labeling runtime、workspace、权限状态和允许来源提示；缺失必需依赖时 `ok=false`；不自动下载模型、二进制或驱动 | `PV-MA-005` |
| AC-MA-006 | 标准化处理音频和输入选择 | 会话存在可用音频 artifact | 用户启动处理或选择音频源 | 默认优先使用 `mixed_audio`；缺失时允许用户选择可用音频；生成可重建的 `.wav` `normalized_audio`；不得覆盖 `system_audio`、`microphone_audio` 或 `mixed_audio` 原始/目标产物 | `PV-MA-006` |
| AC-MA-007 | 生成带时间戳 transcript | 可用 `mixed_audio`、`normalized_audio` 或用户选择的音频 artifact，transcription adapter 可用 | 用户运行 `generate_transcript` | 生成当前有效 `Transcript`；segments 按时间排序，每段包含 `start_ms`、`end_ms` 和文本；转写失败保留原始媒体和失败原因 | `PV-MA-007` |
| AC-MA-008 | best-effort 匿名 speaker labels 和 transcript-only 降级 | transcript 已生成，speaker labeling 依赖可用或明确不可用 | 用户运行 `generate_speaker_labels` | 可用时为 segments 添加 `SPEAKER_01` 这类匿名 labels；不可用或失败时降级 transcript-only 并记录原因；不得声称真实身份或把 `is_verified_identity` 置为 `true` | `PV-MA-008` |
| AC-MA-009 | 文件化流水线重试和原始媒体保护 | 已有会话和原始媒体 | 用户重新运行标准化音频、转写、speaker labeling 或导出 | 派生产物可重新生成或失败后重试；原始视频和音频不被覆盖；同一会话的并发写入冲突必须返回可解释错误 | `PV-MA-009` |
| AC-MA-010 | transcript 回查状态 | transcript 已生成，speaker labels 可用或处于 transcript-only 降级 | 用户打开 transcript 回查入口 | 显示会话标题或时间、时间戳 segments、文本和匿名 speaker labels 或降级原因；不把 speaker labels 表述为真实身份 | `PV-MA-010` |
| AC-MA-011 | transcript 复制或导出，且不自动上传外部工具 | transcript 已生成 | 用户复制或运行 `export_transcript` | 产出 `plain_text`、`markdown`、`json` 中至少一种格式或返回可复制文本；外部 GPT 处理仅由用户主动发起；应用不保存外部 API key、不自动上传 transcript、音频或视频 | `PV-MA-011` |
| AC-MA-012 | 删除本地会议会话 | 会话位于当前 workspace，用户明确选择删除该会话 | 用户运行 `delete_session` 或在本地 UI 中确认删除 | 删除该会话目录内的媒体、transcript、speaker labels、导出包和日志；返回删除摘要；workspace 外导出文件不被自动删除；路径不存在或越界时返回可解释错误 | `PV-MA-012` |
| AC-MA-013 | 设计化原生 app shell | 预检、录制、保存、处理、回查、导出和删除的 command/helper/adapter contract 已存在，或自动化测试使用受控 Debug/XCTest fixture | 用户打开 Swift/SwiftUI app，并在同一 designed native shell 中完成预检、开始/停止录制、查看 artifacts、触发处理、回查 transcript、复制/导出和删除确认 | UI 不再只是裸调试控件；必须具备稳定导航、清晰信息层级、状态面板或状态标记、可见主操作和可访问 locator；生产目标的主操作触发现有允许的 command/helper/adapter 边界，不在 UI 本地伪造成功；Debug/XCTest fake 必须与 Release 默认行为隔离；真实 capture、真实 processing、真实 OS 集成和发布放行仍以各自 `PV-MA-*` covered 证据为准 | `PV-MA-013` |
| AC-MA-014 | 任务式个人会议工作流 | Phase 1 MVP 的本地 command/helper/adapter 已通过；workspace 中可为空、存在 recorded、处理中断或 transcribed 会话 | 首次用户从 Meetings 新建会议并完成与当前捕获意图对应的预检、录制、停止保存、主动选择可用音频并生成 transcript 和回查；回访用户从最近会议重新打开一个会话继续处理、恢复中断处理或查看 transcript；用户可从 diagnostics 查看技术详情 | 应用只有一套主导航且一次呈现一个任务；每个阶段只有一个明确上下文主操作；New recording 使用用户输入标题和当前真实支持的录制/音轨配置，且 processing 依赖不阻断录制；Processing 只对已保存或确认中断且有可处理音频的会话开放，默认使用 `mixed_audio`，缺失时由用户选择安全可用音频；长 transcript 的 Copy/Export 保持在稳定操作区，segments 惰性呈现且文件读取、解码和 checksum 不阻塞主线程；用户无需 README、CLI、Finder、session id、原始 artifact type 或内部命令即可完成主路径；失败状态持续显示“发生了什么、数据是否安全、下一步动作”，技术 code/path 渐进披露；删除成功后清空当前会话并刷新最近会议；任务级 Swift Testing 与 app-bundle XCUITest 覆盖空首页、ready/blocked preflight、录制、保存、音频 fallback、处理、transcript、历史会话重开/中断恢复、失败恢复和删除 reset | `PV-MA-014` |

## MVP.1 验证边界

1. `AC-MA-014` 的当前必需证据是实际执行 test body 的任务级 Swift Testing 和 app-bundle XCUITest；local-direct 发布候选还必须通过既有本机功能与 release gate。
2. 真人截图视觉审查、真实窗口 VoiceOver/键盘走查和 3–5 名代表性用户研究是可选的后续质量研究，不是当前 `AC-MA-014`、`PV-MA-014` 或 local-direct release 的阻断条件。
3. 可选研究不得替代自动化任务证据，也不能因未执行而被表述为通过；如研究发现 P0/P1，仍按普通缺陷处理并以真实复测关闭。
4. 这不放宽 `12-ui-ux-design.md` 中的可访问性、键盘、状态表达或任何功能与安全验收要求。

## 高风险验收维度

1. macOS 权限：录屏、麦克风和文件访问缺失时必须 fail closed。
2. 录制状态：录制中、停止保存、失败和降级状态必须可区分。
3. 录制产物：视频和三类音频 artifact 必须可登记，缺失时必须可解释。
4. 本地依赖：FFmpeg 或兼容媒体能力、转写 runtime、speaker labeling runtime 缺失时必须可检测。
5. 数据保护：原始媒体不得被标准化处理、转写、speaker labeling 或导出覆盖。
6. 外部工具边界：GPT 仅是用户手动复制后的外部行为，应用不自动上传会议内容。
7. 删除边界：删除会话只作用于当前 workspace 内的目标会话目录，不能删除 workspace 外导出文件或任意用户路径。
8. Apple Silicon + macOS 26.5.1：MVP 验收环境以当前确认平台为准。
9. 组件边界：非业务工程 skeleton 只能验证命令和契约，不实现或证明真实产品行为。
10. UI 产品化：设计化 native shell 必须触发既有本地契约；视觉完成不能替代真实录制、真实处理、真实删除或 release 证据。

## 发布前验收

发布候选必须满足：

1. `10-open-decisions.md` 没有阻塞发布的问题。
2. 验证矩阵中发布范围内所有 `PV-MA-*` 行为 `covered`。
3. `./scripts/release-preflight.sh` 通过。
4. 本机 local-direct 安装候选的依赖许可证、本地签名/digest、数据保留、删除、备份恢复和事故响应完成审查；Developer ID 签名、公证和自动更新只在商业化分发重新纳入范围后适用。
