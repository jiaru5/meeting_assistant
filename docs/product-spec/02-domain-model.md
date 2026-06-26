# 2. 领域模型

本文件定义领域对象、字段、枚举、关系、生命周期和不变量。它是命令、数据、页面和测试的字段语义来源。

## 建模原则

1. Phase 1 领域模型以本地文件和元数据为核心，不以远程数据库或团队账号为核心。
2. 录制、媒体处理、转写、speaker labeling 和后续纪要生成通过稳定 artifact contract 解耦。
3. 核心对象表达业务状态，不包含 UI 展示名、临时进度文本或外部工具内部状态。
4. 文件路径、模型路径和依赖检查结果属于本地运行环境信息，不能被误建成跨用户共享事实。
5. 派生字段的计算口径维护在 `05-business-rules-and-calculations.md`。

## 领域上下文

| 上下文 ID | 名称 | 职责 | 拥有对象 | 对外契约 |
|---|---|---|---|---|
| BC-MA-CAPTURE | Capture Context | 编排原生 macOS 录制并登记媒体产物 | `MeetingSession`, `RecordingArtifact` | 本地命令、元数据文件 |
| BC-MA-PROCESSING | Processing Context | 对音频进行格式处理、转写和匿名 speaker labeling | `Transcript`, `TranscriptSegment`, `SpeakerLabel` | 本地命令、元数据文件 |
| BC-MA-EXPORT | Export Context | 导出 transcript 供用户回查或手动复制到外部工具 | `ExportPackage` | 本地文件 |

## 实体

### MeetingSession

一次会议或讨论的本地记录单位。

| 字段 | 类型 | 必填 | 系统维护 | 说明 |
|---|---|---|---|---|
| `id` | string | yes | yes | 本地唯一会话 ID |
| `title` | string | no | no | 用户可读标题；未命名时可由开始时间派生 |
| `source_type` | enum `MeetingSourceType` | yes | no | 会话来源 |
| `status` | enum `MeetingSessionStatus` | yes | yes | 会话生命周期状态 |
| `started_at` | timestamp | yes | yes | 录制或导入开始时间 |
| `ended_at` | timestamp | no | yes | 录制结束时间 |
| `workspace_dir` | path | yes | yes | 本地会话目录 |
| `created_at` | timestamp | yes | yes | 元数据创建时间 |
| `updated_at` | timestamp | yes | yes | 元数据更新时间 |

关系规则：

1. 一个 `MeetingSession` 可以拥有多个 `RecordingArtifact`。
2. 一个 `MeetingSession` 最多拥有一个当前有效 `Transcript`，但可以保留失败处理日志。
3. 删除或归档会话必须以 `07-data-and-events.md` 的保留和删除规则为准。

### RecordingArtifact

会议会话产生的视频、音频、文本或派生文件。

| 字段 | 类型 | 必填 | 系统维护 | 说明 |
|---|---|---|---|---|
| `id` | string | yes | yes | 本地唯一 artifact ID |
| `session_id` | string | yes | yes | 所属 `MeetingSession` |
| `artifact_type` | enum `RecordingArtifactType` | yes | yes | 产物类型 |
| `path` | path | yes | yes | 本地文件路径 |
| `format` | string | yes | yes | 文件格式，例如视频、音频或文本格式 |
| `capture_status` | enum `CaptureStatus` | yes | yes | 成功、降级、缺失或失败 |
| `degradation_reason` | string | no | yes | 某类产物无法生成时的原因摘要 |
| `duration_ms` | integer | no | yes | 媒体时长 |
| `checksum` | string | no | yes | 文件完整性校验值 |
| `created_at` | timestamp | yes | yes | 产物登记时间 |

MVP 应支持的 `artifact_type`：

1. `screen_video`：会议屏幕或窗口录制视频。
2. `system_audio`：会议软件或系统输出音频。
3. `microphone_audio`：Mac 麦克风音频。
4. `mixed_audio`：系统音频和麦克风音频混合产物。
5. `normalized_audio`：用于转写和 speaker labeling 的 `.wav` 派生音频。
6. `transcript_text`：带时间戳的转写文本。
7. `speaker_labels`：best-effort 匿名 speaker labels。
8. `metadata`：会话和处理元数据。

### Transcript

一次会话当前有效的转写结果。

| 字段 | 类型 | 必填 | 系统维护 | 说明 |
|---|---|---|---|---|
| `id` | string | yes | yes | 本地唯一 transcript ID |
| `session_id` | string | yes | yes | 所属 `MeetingSession` |
| `source_artifact_id` | string | yes | yes | 用于转写的音频产物 |
| `language` | string | no | yes | 识别出的或用户指定的语言 |
| `status` | enum `ProcessingStatus` | yes | yes | 处理状态 |
| `segments` | array `TranscriptSegment` | yes | yes | 分段文本 |
| `created_at` | timestamp | yes | yes | 生成时间 |

### TranscriptSegment

| 字段 | 类型 | 必填 | 系统维护 | 说明 |
|---|---|---|---|---|
| `segment_id` | string | yes | yes | transcript 内唯一分段 ID |
| `start_ms` | integer | yes | yes | 段落开始时间 |
| `end_ms` | integer | yes | yes | 段落结束时间 |
| `text` | string | yes | yes | 转写文本 |
| `speaker_label` | string | no | yes | 匿名 speaker label，例如 `SPEAKER_01` |
| `confidence` | number | no | yes | 引擎提供的可选置信度 |

### SpeakerLabel

匿名说话人标签，不代表真实身份。

| 字段 | 类型 | 必填 | 系统维护 | 说明 |
|---|---|---|---|---|
| `label` | string | yes | yes | 例如 `SPEAKER_01` |
| `session_id` | string | yes | yes | 所属会话 |
| `display_name` | string | no | no | 用户后续可选编辑的显示名；MVP 不要求 |
| `is_verified_identity` | boolean | yes | yes | MVP 固定为 `false` |

### ExportPackage

用户用于复制或导出的 transcript 包。

| 字段 | 类型 | 必填 | 系统维护 | 说明 |
|---|---|---|---|---|
| `id` | string | yes | yes | 本地唯一导出 ID |
| `session_id` | string | yes | yes | 所属会话 |
| `export_type` | enum `ExportType` | yes | no | 导出格式 |
| `path` | path | no | yes | 如果落盘，记录本地路径 |
| `created_at` | timestamp | yes | yes | 导出时间 |

## 枚举

| 枚举 | 值 | 含义 | 可变更规则 |
|---|---|---|---|
| `MeetingSourceType` | `native_recording`, `imported_media` | 原生录制或导入已有媒体 | 新增来源需要同步旅程、命令和验证矩阵 |
| `MeetingSessionStatus` | `created`, `recording`, `recorded`, `processing`, `transcribed`, `failed`, `deleted` | 会话生命周期 | 状态语义变更需要 ADR |
| `RecordingArtifactType` | `screen_video`, `system_audio`, `microphone_audio`, `mixed_audio`, `normalized_audio`, `transcript_text`, `speaker_labels`, `metadata` | 会话产物类型 | 新增产物需同步数据、验收和验证 |
| `CaptureStatus` | `available`, `degraded`, `missing`, `failed` | 产物可用性 | 降级规则见 `05-business-rules-and-calculations.md` |
| `ProcessingStatus` | `pending`, `running`, `succeeded`, `failed` | 转写或 speaker labeling 状态 | 失败必须记录可读原因 |
| `ExportType` | `plain_text`, `markdown`, `json` | transcript 导出格式 | 新增格式需同步命令契约和验证 |

## 不变量

| ID | 不变量 | 影响对象 | 验证入口 |
|---|---|---|---|
| DM-MA-INV-001 | 每个 `MeetingSession` 必须有本地 `workspace_dir` 和元数据文件 | `MeetingSession` | `PV-MA-002` |
| DM-MA-INV-002 | `system_audio`、`microphone_audio`、`mixed_audio` 是 MVP 目标产物；无法生成时必须登记 `capture_status` 和 `degradation_reason` | `RecordingArtifact` | `PV-MA-002` |
| DM-MA-INV-006 | `normalized_audio` 是可重建派生产物，不能替代或覆盖原始视频和音频 | `RecordingArtifact` | `PV-MA-005` |
| DM-MA-INV-003 | `TranscriptSegment.start_ms` 必须小于 `end_ms`，且同一 transcript 内分段按时间排序 | `TranscriptSegment` | `PV-MA-003` |
| DM-MA-INV-004 | MVP speaker label 不得被标记为已验证真实身份 | `SpeakerLabel` | `PV-MA-004` |
| DM-MA-INV-005 | 导出 transcript 不得改变原始 transcript 或媒体产物 | `ExportPackage`, `Transcript` | `PV-MA-005` |

## 读取模型

读取模型、projection 或 UI ViewModel 可以包含展示字段、聚合字段和跨文件字段，但不能反向定义核心领域状态。

| 读取模型 | 用途 | 来源实体 | 允许的派生字段 |
|---|---|---|---|
| `MeetingSessionSummaryView` | 会话列表或本地索引 | `MeetingSession`, `RecordingArtifact`, `Transcript` | `duration_label`, `artifact_count`, `has_transcript`, `has_speaker_labels` |
| `TranscriptReviewView` | 回查 transcript 和 speaker labels | `Transcript`, `TranscriptSegment`, `SpeakerLabel` | `speaker_display_label`, `timestamp_label` |
