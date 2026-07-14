# 3. 权限和身份

本文件定义认证、授权、数据隔离和审计身份。页面或本地工具只负责呈现权限状态，不能替代系统权限和文件访问控制。

## 身份模型

| 身份类型 | 来源 | 适用范围 | 说明 |
|---|---|---|---|
| `local_os_user` | 当前 macOS 用户账号 | Phase 1 MVP | 本地会议文件默认归当前 OS 用户所有；MVP 不引入应用账号、密码或远程身份 |
| `local_process` | 本地应用进程或脚本进程 | 本地命令、录制、处理、导出 | 必须只在用户授权目录内读写会议数据 |

## 认证和授权范围

| 范围 ID | 规则 | 适用对象 | 状态 |
|---|---|---|---|
| AUTH-MA-001 | Phase 1 不要求应用内登录；使用当前 macOS 用户和文件系统权限作为本地访问边界 | `MeetingSession`, `RecordingArtifact`, `Transcript` | confirmed for MVP |
| AUTH-MA-002 | 不提供团队账号、组织空间、共享库、远程权限模型、团队分发或团队支持；多人使用时每个人都是自己设备上的 `local_os_user` | 所有业务对象 | confirmed |
| AUTH-MA-003 | 未来如重新提出团队协作、共享或集中支持，必须先新增独立身份和权限模型，不得复用个人本地访问模型 | future team use | out of scope |

## 数据隔离

| 隔离键 | 含义 | 适用对象 | 例外 |
|---|---|---|---|
| `workspace_dir` | 当前用户指定或系统创建的本地会议工作区 | `MeetingSession`, `RecordingArtifact`, `Transcript`, `ExportPackage` | 例外必须由用户显式选择导出路径 |

规则：

1. MVP 数据隔离边界是本机当前 OS 用户和本地 workspace。
2. 应用不得默认扫描或上传 workspace 之外的会议文件。
3. 用户选择导入媒体时，只能读取用户显式选择的文件或目录。
4. 用户选择导出 transcript 时，只能写入用户显式选择或项目配置允许的路径。

## 权限矩阵

| 权限 ID | 操作 | 主体 | 条件 | 允许结果 | 拒绝结果 |
|---|---|---|---|---|---|
| PERM-MA-001 | `meeting_session.create` | `local_os_user` | 原生录制具有录屏和 workspace 文件写入权限；只有用户启用麦克风录制意图时才要求麦克风权限；导入媒体继续以用户显式选择的文件权限为边界 | 创建会话并启动录制或导入 | 返回与当前操作对应的本地权限错误和修复提示 |
| PERM-MA-002 | `meeting_session.read` | `local_os_user` | 会话位于当前 workspace 且文件可读 | 读取会话元数据和产物 | 返回不可访问或文件缺失错误 |
| PERM-MA-003 | `recording_artifact.write` | `local_process` | 目标路径位于当前会话目录 | 写入视频、音频、transcript 或 speaker labels | 拒绝写入并记录失败原因 |
| PERM-MA-004 | `transcript.export` | `local_os_user` | 用户显式选择复制或导出 | 输出 transcript 文本、Markdown 或 JSON | 返回导出失败，不自动重试到外部服务 |
| PERM-MA-005 | `meeting_session.delete` | `local_os_user` | 用户明确选择删除当前 workspace 内的目标会话 | 删除会话目录内应用管理的媒体、transcript、speaker labels、导出包和日志 | 返回删除失败或路径越界错误；不得删除 workspace 外导出文件 |

## macOS 权限

| 权限 | 用途 | MVP 要求 |
|---|---|---|
| 录屏权限 | 录制会议窗口、屏幕共享或屏幕区域 | 原生录制路径必须检测权限并给出可执行提示 |
| 麦克风权限 | 录制现场讨论或本机麦克风输入 | 必须检测权限；只有当前录制启用麦克风意图时才阻断开始录制，关闭麦克风意图后不得继续作为录制阻断项 |
| 文件访问权限 | 写入本地 workspace、读取导入媒体、导出 transcript | 必须限制在用户选择或配置的路径 |

## 审计

Phase 1 不做远程审计系统，但必须保留本地处理日志以便排错和交付证据。

| 事件 | 必须记录 | 保留要求 |
|---|---|---|
| 会话创建和录制开始/结束 | session id、时间、录制模式、权限检查摘要、结果 | 随会话元数据保存 |
| 产物生成或降级 | artifact type、status、degradation reason、路径摘要 | 随会话元数据保存 |
| 转写和 speaker labeling | 输入 artifact、模型或引擎摘要、状态、错误摘要 | 随会话元数据保存 |
| transcript 导出 | export type、目标路径摘要或 copy action、时间 | 随会话元数据保存 |
| 会话删除 | session id、删除时间、删除结果摘要 | 保留本地删除摘要；workspace 外导出文件由用户自行管理 |

## 前端或本地工具权限状态

1. 必须区分未授权、权限被拒绝、文件不可读、依赖缺失和处理失败。
2. 权限错误必须给出用户可执行的本地修复提示。
3. 不得把隐藏按钮或禁用控件视为安全控制；本地命令执行层仍需检查路径和权限。
4. 录制 readiness 与 transcript processing readiness 必须分开计算：FFmpeg、转写 runtime/model 或 speaker-labeling 状态只阻断对应处理，不得阻断一场本来可以安全保存的录制。
5. 修复入口必须打开与缺失权限对应的 macOS Privacy 面板；麦克风拒绝不能只提供 Screen Recording 设置入口。
