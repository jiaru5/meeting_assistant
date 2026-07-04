# 1. 产品范围

本文件定义产品范围、目标、非目标、用户角色和核心场景。它不定义字段、权限、命令、文件格式或 UI 细节。

## 产品一句话

`meeting_assistant` 是一个本地 macOS 会议助手，面向个人自用的第一阶段，优先通过原生 macOS 录制能力记录线上会议或现场讨论，通过设计化原生 Swift/SwiftUI app shell 承载预检、录制、处理、回查、导出和删除，并产出可回查的视频、系统音频、麦克风音频、混合音频、转写文本和 best-effort 匿名说话人标签；多人使用时各自在本地 Mac 上独立运行，不提供团队分发或团队支持。

## 阶段边界

| 阶段 | 范围 | 说明 |
|---|---|---|
| Phase 1 MVP | 个人自用、本地 macOS、Apple Silicon、原生 macOS 录制优先、设计化原生 app shell、文件化产物流水线、音频转写、best-effort 匿名 speaker labels | MVP 实现目标 |
| 本地各自运行 | 多个使用者各自在自己的 Mac 上独立运行 | 不提供团队分发、共享空间、团队账号、集中审计或团队支持 |
| 未来原生产品化 | 签名、公证、自动更新、自动纪要和商业化分发体验 | 不属于 MVP 必需能力 |

## 目标

| ID | 目标 | 成功标准 | 验证入口 |
|---|---|---|---|
| GOAL-MA-001 | 本地记录线上会议或现场讨论 | 用户能在 Apple Silicon Mac 上完成录制前检查、启动原生录制、停止录制，并得到会议视频和音频产物或明确失败原因 | `AC-MA-001`, `AC-MA-002`, `PV-MA-001`, `PV-MA-002` |
| GOAL-MA-002 | 保留可重处理的会议媒体产物 | 每次会议会话保存系统音频、麦克风音频、混合音频和屏幕视频；无法获得某一音轨时必须记录能力状态和降级原因 | `AC-MA-003`, `AC-MA-006`, `AC-MA-009`, `PV-MA-003`, `PV-MA-006`, `PV-MA-009` |
| GOAL-MA-003 | 从会议音频生成可回查 transcript | 用户能从混合音频或可用音轨生成带时间戳的文本转写结果，并在本地回查 | `AC-MA-007`, `AC-MA-010`, `PV-MA-007`, `PV-MA-010` |
| GOAL-MA-004 | 提供 best-effort 匿名 speaker labels | MVP 以 `SPEAKER_01` 这类匿名标签区分发言段落，不承诺真实姓名或完全准确率 | `AC-MA-008`, `PV-MA-008` |
| GOAL-MA-005 | 保持模块解耦和可替换流水线 | 录制、媒体处理、转写、speaker labeling 和导出通过命令、文件和元数据衔接 | `AC-MA-004`, `AC-MA-005`, `AC-MA-009`, `AC-MA-011`, `PV-MA-004`, `PV-MA-005`, `PV-MA-009`, `PV-MA-011` |
| GOAL-MA-006 | 让用户控制本地会议数据生命周期 | 用户能删除本地会话目录内的媒体、transcript、speaker labels、导出包和日志；workspace 外导出文件不由应用自动删除 | `AC-MA-012`, `PV-MA-012` |
| GOAL-MA-007 | 用设计化原生 UI 承载完整本地工作流 | 用户不需要依赖原始调试 UI，也能在一个状态清晰、层级稳定、可访问的原生 shell 中触发预检、录制、处理、回查、导出和删除 | `AC-MA-013`, `PV-MA-013` |

## MVP 产品能力矩阵

本表定义 Phase 1 MVP 的产品能力边界，是后续技术方案、代码实现、自动化测试和审查工作的能力索引。字段、命令、文件、UI 状态和安全细节仍由对应主责分卷维护；本表不复制那些细节。

| 能力 ID | 能力 | 用户价值 | 主入口 | 主责分卷 | 验收 | 验证 |
|---|---|---|---|---|---|---|
| CAP-MA-001 | 录制前权限和环境预检 | 开始录制前知道录屏、麦克风、文件写入和关键依赖是否可用 | Swift/SwiftUI app, `check_dependencies` | `04-user-journeys-and-ui.md`, `06-api-contracts.md`, `13-security-and-compliance.md` | `AC-MA-001` | `PV-MA-001` |
| CAP-MA-002 | 原生录制启动、持续状态和停止保存 | 用户能启动和停止一次原生 macOS 录制，并看到录制中和保存结果 | Swift/SwiftUI app, `start_native_recording`, `stop_recording` | `04-user-journeys-and-ui.md`, `06-api-contracts.md`, `08-implementation-guidance.md` | `AC-MA-002` | `PV-MA-002` |
| CAP-MA-003 | 会话和录制产物登记 | 录制结束后能得到可回查的会话元数据和视频、音频 artifact 状态 | `stop_recording`, workspace metadata | `02-domain-model.md`, `05-business-rules-and-calculations.md`, `07-data-and-events.md` | `AC-MA-003` | `PV-MA-003` |
| CAP-MA-004 | 导入已有媒体作为回退或测试路径 | 不依赖现场录制也能验证处理流水线 | `import_media` | `04-user-journeys-and-ui.md`, `06-api-contracts.md`, `07-data-and-events.md` | `AC-MA-004` | `PV-MA-004` |
| CAP-MA-005 | 本地依赖检查 | 用户和 agent 能稳定判断工具链、媒体工具、runtime、workspace 和权限状态 | `check_dependencies` | `06-api-contracts.md`, `08-implementation-guidance.md`, `13-security-and-compliance.md` | `AC-MA-005` | `PV-MA-005` |
| CAP-MA-006 | 标准化处理音频和输入选择 | 转写和 speaker labeling 使用可重建 `.wav` 输入，不破坏原始音频 | `processing-cli` artifact processing | `05-business-rules-and-calculations.md`, `07-data-and-events.md` | `AC-MA-006` | `PV-MA-006` |
| CAP-MA-007 | 生成带时间戳 transcript | 用户能从可用音频得到按时间排序的 transcript segments | `generate_transcript` | `02-domain-model.md`, `05-business-rules-and-calculations.md`, `06-api-contracts.md` | `AC-MA-007` | `PV-MA-007` |
| CAP-MA-008 | best-effort 匿名 speaker labels 和 transcript-only 降级 | 用户能看到匿名说话人辅助信息；不可用时仍保留 transcript | `generate_speaker_labels` | `02-domain-model.md`, `05-business-rules-and-calculations.md`, `13-security-and-compliance.md` | `AC-MA-008` | `PV-MA-008` |
| CAP-MA-009 | 文件化流水线重试和原始媒体保护 | 处理失败或重新生成派生产物时，原始视频和音频不被覆盖 | workspace metadata, processing commands | `05-business-rules-and-calculations.md`, `07-data-and-events.md` | `AC-MA-009` | `PV-MA-009` |
| CAP-MA-010 | transcript 回查状态 | 用户能本地回查会话标题、时间戳文本和匿名 speaker labels | Transcript review/export surface | `04-user-journeys-and-ui.md`, `12-ui-ux-design.md` | `AC-MA-010` | `PV-MA-010` |
| CAP-MA-011 | transcript 复制或导出，且不自动上传外部工具 | 用户能主动把 transcript 带出本系统；应用不自动调用 GPT 或云端模型 | `export_transcript`, Transcript review/export surface | `06-api-contracts.md`, `07-data-and-events.md`, `13-security-and-compliance.md` | `AC-MA-011` | `PV-MA-011` |
| CAP-MA-012 | 删除本地会议会话 | 用户能删除本地 workspace 内某个会话目录及其应用管理的产物 | `delete_session` | `03-permissions-and-identity.md`, `06-api-contracts.md`, `07-data-and-events.md`, `13-security-and-compliance.md` | `AC-MA-012` | `PV-MA-012` |
| CAP-MA-013 | 设计化原生 app shell | 用户在接近效果图目标的原生界面中完成预检、录制、保存、处理、回查、导出和删除，而不是依赖仅有功能的调试控件 | Swift/SwiftUI app | `04-user-journeys-and-ui.md`, `12-ui-ux-design.md` | `AC-MA-013` | `PV-MA-013` |

## 非目标

| ID | 非目标 | 原因 | 重新纳入范围的条件 |
|---|---|---|---|
| NOGOAL-MA-001 | MVP 不做团队账号、组织空间、多人协作、共享会议库、团队分发或团队支持 | 已确认多人使用时也是各自本地运行，不形成团队产品边界 | 用户重新提出团队协作、共享、分发或支持诉求，并按 spec-change 更新事实源和 ADR |
| NOGOAL-MA-002 | MVP 不做闭源商业化分发、App Store 分发、签名、公证或自动更新 | 当前目标是先验证本地能力和文件化流水线 | 用户确认分发渠道、许可证策略和安装体验要求 |
| NOGOAL-MA-003 | MVP 不要求自动生成完整会议纪要 | 用户确认可手动复制 transcript 到 GPT；纪要生成是可选后续能力 | 用户确认本地 LLM 或外部模型集成边界和质量标准 |
| NOGOAL-MA-004 | MVP 不承诺识别真实发言人姓名 | 在线会议音频可能已被混音，且没有确认声纹、参会人身份或平台数据来源 | 用户确认实名识别数据来源、授权和准确率要求 |
| NOGOAL-MA-005 | MVP 不以 OBS/BlackHole 作为主录制路径 | 用户已选择原生 macOS 录制优先 | 原生录制被验证不可行，或用户明确改回辅助工具录制；回退必须先通过 spec-change、ADR 和验证矩阵更新 |
| NOGOAL-MA-006 | MVP 不由应用自动调用 GPT 或其他云端模型 API | 目前只确认用户可以主动复制 transcript 到外部工具 | 用户确认云/API 集成、密钥管理、隐私告知和合规要求 |

## 用户角色

本表只描述产品视角的用户类型，不定义系统权限。权限以 `03-permissions-and-identity.md` 为准。

| 角色 ID | 名称 | 目标 | 关键使用场景 |
|---|---|---|---|
| ROLE-MA-LOCAL-USER | 本地会议记录用户 | 在自己的 Mac 上记录会议、转写、回查和导出 transcript | 录制线上会议、录制现场讨论、处理录制产物、复制 transcript |

## 核心场景

| 场景 ID | 场景 | 参与角色 | 成功结果 | 失败或异常场景 |
|---|---|---|---|---|
| SCN-MA-001 | 原生录制线上会议 | `ROLE-MA-LOCAL-USER` | 保存屏幕视频、系统音频、麦克风音频、混合音频和会话元数据 | 屏幕录制权限缺失、音频权限缺失、无法捕获某一音轨、磁盘空间不足、录制中断 |
| SCN-MA-002 | 原生录制现场讨论 | `ROLE-MA-LOCAL-USER` | 保存麦克风音频、混合音频和会话元数据；如录制屏幕则保存视频 | 麦克风权限缺失、环境噪音过高、录制中断 |
| SCN-MA-003 | 转写会议音频 | `ROLE-MA-LOCAL-USER` | 从可用音频产物生成带时间戳 transcript | 模型缺失、依赖检查失败、音频格式不可处理、转写失败 |
| SCN-MA-004 | 匿名 speaker labeling | `ROLE-MA-LOCAL-USER` | transcript 段落可以带 best-effort 匿名 speaker labels | 混音、重叠说话或噪音导致标签不稳定；必须保留原 transcript |
| SCN-MA-005 | 手动复制 transcript 到外部 GPT 工具 | `ROLE-MA-LOCAL-USER` | 用户主动复制或导出 transcript 后，在外部工具中整理会议纪要 | 外部工具不属于本系统控制范围；应用不自动上传会议内容 |

## 范围边界

1. 系统边界：本系统负责本地录制编排、产物保存、媒体处理、转写、匿名 speaker labels、元数据维护和 transcript 导出。
2. 外部系统边界：GPT 或其他外部工具仅作为用户手动复制后的外部处理环境；MVP 应用本身不自动调用外部模型 API。
3. 数据所有权：本系统拥有本地会话元数据、媒体文件、transcript、speaker labels 和处理日志；会议软件本身的参会人、聊天、日程和账号信息不属于本系统。
4. 合规边界：Phase 1 是个人本地工具；多人使用时各自本地运行，不提供团队共享、集中审计、安装分发或支持流程。

## 术语表

| 术语 | 定义 | 主责分卷 |
|---|---|---|
| Meeting Session | 一次会议或讨论的本地记录单位，包含录制、媒体、转写和处理状态 | `02-domain-model.md` |
| Recording Artifact | 一次会话产生的视频、音频、transcript、speaker labels 或元数据文件 | `02-domain-model.md`, `07-data-and-events.md` |
| Mixed Audio | 合并系统音频和麦克风音频后用于回听或转写的音频产物 | `02-domain-model.md`, `05-business-rules-and-calculations.md` |
| Anonymous Speaker Label | 不代表真实身份的说话人标签，例如 `SPEAKER_01` | `05-business-rules-and-calculations.md` |
| Native macOS Recording | 以 macOS 原生能力为第一阶段主录制路径，具体技术边界见 `08-implementation-guidance.md` 和 `11-adr.md` | `08-implementation-guidance.md` |
