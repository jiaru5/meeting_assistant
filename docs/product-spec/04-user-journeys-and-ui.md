# 4. 用户旅程和 UI

本文件定义用户旅程、本地工具入口、页面或交互范围。视觉、布局、可访问性和 locator 规则由 `12-ui-ux-design.md` 维护。

## 交互面边界

| 交互面 ID | 入口 | 角色 | 目标 | 状态 |
|---|---|---|---|---|
| SURFACE-MA-001 | Minimal Swift/SwiftUI app | `ROLE-MA-LOCAL-USER` | 提供原生录制入口、权限状态、录制中状态和停止保存反馈 | confirmed for MVP |
| SURFACE-MA-002 | Local helper / processing CLI | `ROLE-MA-LOCAL-USER` | 执行依赖检查、媒体处理、转写、speaker labeling 和导出命令 | confirmed for MVP |
| SURFACE-MA-003 | Transcript review/export surface | `ROLE-MA-LOCAL-USER` | 回查 transcript，复制或导出文本 | planned |

Phase 1 采用最小 Swift/SwiftUI app + local helper / processing CLI 的组合。activation 前允许只创建非业务骨架来注册 manifest 和门禁；真实录制、转写和 speaker labeling 行为只能在 project 模式后实现。

## 用户旅程

| Journey ID | 名称 | 步骤 | 成功状态 | 异常状态 |
|---|---|---|---|---|
| JRN-MA-001 | 原生录制线上会议 | 用户启动本地工具；选择录制目标或屏幕范围；系统检查录屏、麦克风、文件权限；开始录制；结束录制；写入会话元数据和媒体产物 | 会话状态为 `recorded`，视频、系统音频、麦克风音频、混合音频按可用性登记 | 权限缺失、无法捕获某一音轨、磁盘不足、录制中断、目标窗口不可用 |
| JRN-MA-002 | 原生录制现场讨论 | 用户启动本地工具；启用麦克风录制；可选录屏；结束后保存会话和音频产物 | 麦克风音频和混合音频可回放，元数据完整 | 麦克风权限缺失、录制中断、噪音导致转写质量差 |
| JRN-MA-003 | 处理会议产物 | 用户选择一个已录制会话；运行依赖检查；选择音频源；启动转写和 best-effort speaker labeling | 生成带时间戳 transcript，分段可带匿名 speaker labels | 依赖缺失、模型缺失、音频不可处理、处理失败 |
| JRN-MA-004 | 回查和导出 transcript | 用户打开 transcript；按时间戳回查；复制或导出 transcript 到本地文件；可手动粘贴到 GPT | transcript 可复制或导出，原始媒体和 transcript 不被修改 | transcript 不存在、导出路径不可写、外部 GPT 工具不可用 |
| JRN-MA-005 | 导入已有媒体作为回退或测试路径 | 用户选择本地媒体文件；系统登记为 `imported_media` 会话；处理音频并生成 transcript | 可不依赖现场录制验证处理流水线 | 文件格式不支持、缺少音频轨、转写失败 |

## 组件交互契约

1. Swift/SwiftUI app 负责用户可见的录制控制、权限提示和录制状态。
2. Local helper / processing CLI 负责非交互任务，包括依赖检查、媒体处理、转写、speaker labeling 和导出。
3. 两者只通过 `06-api-contracts.md` 的本地命令契约以及 `07-data-and-events.md` 的文件/元数据契约协作。
4. activation 前的组件骨架不得实现真实录制、真实转写或真实 speaker labeling 行为。

## 关键状态要求

| State ID | 场景 | 用户可见要求 |
|---|---|---|
| UI-MA-STATE-001 | 权限未授权 | 明确指出缺失的 macOS 权限和修复入口，不开始对应录制 |
| UI-MA-STATE-002 | 依赖缺失 | 显示缺失依赖、检查命令和修复建议，不假装处理成功 |
| UI-MA-STATE-003 | 产物降级 | 指出缺失或降级的 artifact type 和原因，保留已成功产物 |
| UI-MA-STATE-004 | 处理失败 | 保留原始媒体和失败日志，允许重试 |
| UI-MA-STATE-005 | transcript 可用 | 显示或导出带时间戳文本和匿名 speaker labels |

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
