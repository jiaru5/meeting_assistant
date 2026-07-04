# 4. 用户旅程和 UI

本文件定义用户旅程、本地工具入口、页面或交互范围。视觉、布局、可访问性和 locator 规则由 `12-ui-ux-design.md` 维护。

## 交互面边界

| 交互面 ID | 入口 | 角色 | 目标 | 状态 |
|---|---|---|---|---|
| SURFACE-MA-001 | Swift/SwiftUI designed native app shell | `ROLE-MA-LOCAL-USER` | 提供设计化原生工作流入口，覆盖预检、原生录制、录制中状态、停止保存、处理、回查、导出和删除确认 | confirmed for MVP; primitive debug UI is transitional only |
| SURFACE-MA-002 | Local helper / processing CLI | `ROLE-MA-LOCAL-USER` | 执行依赖检查、媒体处理、转写、speaker labeling 和导出命令 | confirmed for MVP |
| SURFACE-MA-003 | Transcript review/export surface | `ROLE-MA-LOCAL-USER` | 回查 transcript，复制或导出文本 | confirmed for MVP; evidence remains PV-gated |

Phase 1 采用设计化 Swift/SwiftUI native app shell + local helper / processing CLI 的组合。实现早期的最小或调试 UI 只用于逐步建立状态和测试边界，不能替代本分卷定义的真实录制、转写、speaker labeling 或 `CAP-MA-013` UI 完成口径。

## 用户旅程

| Journey ID | 名称 | 步骤 | 成功状态 | 异常状态 |
|---|---|---|---|---|
| JRN-MA-001 | 原生录制线上会议 | 用户启动本地工具；选择录制目标或屏幕范围；系统检查录屏、麦克风、文件权限；开始录制；结束录制；写入会话元数据和媒体产物 | 会话状态为 `recorded`，视频、系统音频、麦克风音频、混合音频按可用性登记 | 权限缺失、无法捕获某一音轨、磁盘不足、录制中断、目标窗口不可用 |
| JRN-MA-002 | 原生录制现场讨论 | 用户启动本地工具；启用麦克风录制；可选录屏；结束后保存会话和音频产物 | 麦克风音频和混合音频可回放，元数据完整 | 麦克风权限缺失、录制中断、噪音导致转写质量差 |
| JRN-MA-003 | 处理会议产物 | 用户选择一个已录制会话；运行依赖检查；选择音频源；启动转写和 best-effort speaker labeling | 生成带时间戳 transcript，分段可带匿名 speaker labels | 依赖缺失、模型缺失、音频不可处理、处理失败 |
| JRN-MA-004 | 回查和导出 transcript | 用户打开 transcript；按时间戳回查；复制或导出 transcript 到本地文件；可手动粘贴到 GPT | transcript 可复制或导出，原始媒体和 transcript 不被修改 | transcript 不存在、导出路径不可写、外部 GPT 工具不可用 |
| JRN-MA-005 | 导入已有媒体作为回退或测试路径 | 用户选择本地媒体文件；系统登记为 `imported_media` 会话；处理音频并生成 transcript | 可不依赖现场录制验证处理流水线 | 文件格式不支持、缺少音频轨、转写失败 |
| JRN-MA-006 | 删除本地会议会话 | 用户选择当前 workspace 内的会话；确认删除；系统删除会话目录内应用管理文件并返回摘要 | 会话目录内媒体、transcript、speaker labels、导出包和日志被删除；workspace 外导出文件不被自动删除 | 会话不存在、路径越界、文件权限不足、删除部分失败 |

## 旅程到能力映射

| Journey ID | 覆盖能力 | 最小完成口径 | 验证入口 |
|---|---|---|---|
| JRN-MA-001 | `CAP-MA-001`, `CAP-MA-002`, `CAP-MA-003` | 原生录制线上会议必须覆盖权限预检、开始/停止、录制中状态、媒体 artifact 登记和降级提示 | `PV-MA-001`, `PV-MA-002`, `PV-MA-003` |
| JRN-MA-002 | `CAP-MA-001`, `CAP-MA-002`, `CAP-MA-003` | 现场讨论必须至少覆盖麦克风权限、录制状态、音频产物登记和失败提示 | `PV-MA-001`, `PV-MA-002`, `PV-MA-003` |
| JRN-MA-003 | `CAP-MA-005`, `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-008`, `CAP-MA-009` | 处理路径必须先暴露依赖状态，再生成可重建处理输入、transcript、匿名 labels 或 transcript-only 降级，并保护原始媒体 | `PV-MA-005`, `PV-MA-006`, `PV-MA-007`, `PV-MA-008`, `PV-MA-009` |
| JRN-MA-004 | `CAP-MA-010`, `CAP-MA-011` | 回查路径必须显示时间戳文本和匿名 labels 或降级原因；导出或复制必须由用户主动触发 | `PV-MA-010`, `PV-MA-011` |
| JRN-MA-005 | `CAP-MA-004`, `CAP-MA-006`, `CAP-MA-007` | 导入媒体只作为回退或测试路径，不改变原生录制主路径；导入后可进入标准处理流水线 | `PV-MA-004`, `PV-MA-006`, `PV-MA-007` |
| JRN-MA-006 | `CAP-MA-012` | 删除路径必须要求用户明确确认，只删除当前 workspace 内目标会话目录中的应用管理文件，并明确 workspace 外导出文件不受影响 | `PV-MA-012` |

## 组件交互契约

1. Swift/SwiftUI app 负责用户可见的录制控制、权限提示和录制状态。
2. Local helper / processing CLI 负责非交互任务，包括依赖检查、媒体处理、转写、speaker labeling 和导出。
3. 两者只通过 `06-api-contracts.md` 的本地命令契约以及 `07-data-and-events.md` 的文件/元数据契约协作。
4. 非业务工程 skeleton 不得被当作真实录制、真实转写或真实 speaker labeling 行为。

## 设计化原生 App Shell 范围

设计化原生 app shell 是 `SURFACE-MA-001` 的 MVP 目标形态。现有只具备功能和调试价值的原始 native UI 可以作为中间实现、Debug fixture 或 XCUITest 控制面，但不能作为 `CAP-MA-013` 的完成口径。

该 shell 必须至少提供以下稳定入口：

1. Preflight：展示 macOS 权限、workspace、媒体工具、转写 runtime/model 和 speaker-label fallback 状态。
2. Record meeting：配置录制目标、系统音频和麦克风录制意图；开始后展示稳定录制中状态和停止动作。
3. Session artifacts：停止后展示 `screen_video`、`system_audio`、`microphone_audio`、`mixed_audio` 的可用、缺失、降级或失败状态，以及进入处理链路的动作。
4. Processing：展示 normalized audio、transcript、speaker labels、export 准备等流水线步骤，支持失败、降级和重试状态。
5. Transcript：展示会话标题或时间、timestamped segments、匿名 speaker labels 或 transcript-only 降级原因。
6. Export and delete：提供用户主动复制/导出 transcript，以及带影响范围说明的删除确认和结果摘要。

交互规则：

1. 生产目标 shell 的主要按钮必须触发现有允许的 command/helper/adapter 边界，包括 `check_dependencies`、`start_native_recording`、`stop_recording`、处理桥接、`export_transcript` 和 `delete_session`；不得只在 UI 本地伪造成功状态。
2. Debug、XCTest 或 fixture-only fake 可以用于自动化测试，但必须被明确隔离；不能成为 Release 默认行为或产品验收的真实录制/真实处理证据。
3. 设计化 shell 不改变命令字段、artifact type、error code、删除边界、no-auto-upload 或 no-auto-download 规则。
4. 新导航和视觉结构必须保留关键状态的可访问标题、可见文案和 XCUITest 可查询 locator。

## 关键状态要求

| State ID | 场景 | 用户可见要求 |
|---|---|---|
| UI-MA-STATE-001 | 权限未授权 | 明确指出缺失的 macOS 权限和修复入口，不开始对应录制 |
| UI-MA-STATE-002 | 依赖缺失 | 显示缺失依赖、检查命令和修复建议，不假装处理成功 |
| UI-MA-STATE-003 | 产物降级 | 指出缺失或降级的 artifact type 和原因，保留已成功产物 |
| UI-MA-STATE-004 | 处理失败 | 保留原始媒体和失败日志，允许重试 |
| UI-MA-STATE-005 | transcript 可用 | 显示或导出带时间戳文本和匿名 speaker labels |
| UI-MA-STATE-006 | 删除确认和结果 | 删除前显示目标会话和影响范围；删除后显示成功、部分失败或路径错误摘要 |

## 原生录制旅程契约

原生录制入口必须覆盖：

1. 开始前权限检查。
2. 录制目标或屏幕范围选择。
3. 录制中的持续状态。
4. 停止录制和产物落盘。
5. 产物完整性检查。
6. 降级或失败提示。

## Transcript 回查契约

transcript 回查入口必须覆盖：

1. 显示会话标题或时间。
2. 显示带时间戳的 transcript segments。
3. 显示匿名 speaker labels；不把 labels 表述为真实身份。
4. 支持复制 transcript。
5. 支持导出至少一种本地格式。
6. 明确外部 GPT 处理由用户主动发起，不由应用自动上传。

## 导航规则

1. Phase 1 可以是本地原生工具和命令组合，不要求 Web 路由。
2. 如果后续引入桌面 UI，每个主要视图必须有稳定入口和可测试的用户语义 locator。
3. 不得在 UI 中硬编码真实会议名称、用户身份、模型路径或本地绝对路径作为产品事实。
