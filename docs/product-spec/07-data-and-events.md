# 7. 数据和事件

本文件定义本地文件、元数据、事件、索引、审计、数据保留和数据治理语义。

## 数据原则

1. Phase 1 的事实存储是本地 workspace 中的媒体文件和元数据文件，不要求远程数据库。
2. 原始视频和音频文件是优先保护的数据；transcript、speaker labels 和导出包是派生产物。
3. 文件和元数据的语义必须对齐 `02-domain-model.md`。
4. 测试 fixture 和示例媒体只用于测试，不承载产品事实。
5. 后续如引入数据库、索引或云同步，必须先更新本文件、ADR 和验证矩阵。

## 数据所有权

| 组件 | 拥有数据 | 可读引用 | 禁止行为 |
|---|---|---|---|
| `native-capture` | `screen_video`, `system_audio`, `microphone_audio`, `mixed_audio`, capture metadata | macOS permission status | 直接修改 transcript 或 speaker labels |
| `media-processing` | normalized audio artifacts, processing metadata | recording artifacts | 覆盖原始录制文件 |
| `transcription` | transcript text and segment metadata | audio artifacts | 自动上传 transcript 到外部服务 |
| `speaker-labeling` | anonymous speaker labels | transcript segments and audio artifacts | 声称真实身份或覆盖 transcript text |
| `export` | export packages | transcript and metadata | 修改原始 transcript 或媒体 |

## Workspace 布局

MVP 默认 workspace 位于用户本地目录下：

```text
~/Movies/MeetingAssistant/
```

用户可以后续配置其他本地 workspace。MVP 默认不启用应用级加密；访问边界依赖当前 macOS 用户和文件系统权限。删除会话时删除该会话目录内的媒体、transcript、speaker labels、导出包和日志；workspace 外的导出文件由用户自行管理。

推荐本地目录结构：

```text
<workspace>/
  sessions/
    <session_id>/
      session.json
      artifacts/
        screen_video.<ext>
        system_audio.<ext>
        microphone_audio.<ext>
        mixed_audio.<ext>
        transcript.json
        transcript.md
        speaker_labels.json
      logs/
        capture.log
        processing.log
```

## 元数据文件

| 文件 | 所属对象 | 必填字段 | 说明 |
|---|---|---|---|
| `session.json` | `MeetingSession` | `id`, `source_type`, `status`, `started_at`, `workspace_dir`, `artifacts` | 会话主元数据；可包含 `exports` 导出包摘要，用于记录用户主动导出的本地路径 |
| `transcript.json` | `Transcript` | `id`, `session_id`, `source_artifact_id`, `segments` | 结构化 transcript |
| `speaker_labels.json` | `SpeakerLabel` | `session_id`, `labels`, `segment_mapping` | 匿名 speaker labels |
| `transcript.md` | `ExportPackage` | n/a | 用户可读 Markdown 导出 |

## 元数据可测试 schema 要求

本节只定义文件和命令测试必须能断言的最小字段集合；字段语义仍以 `02-domain-model.md` 为准。

| 对象或文件 | 最小可测试字段 | 必须断言的边界 |
|---|---|---|
| `session.json` | `id`, `source_type`, `status`, `started_at`, `workspace_dir`, `created_at`, `updated_at`, `artifacts`；如存在 `exports[]`，每项至少包含 `id`, `session_id`, `export_type`, `created_at`，落盘导出还包含 `path` | `id` 与会话目录一致；`workspace_dir` 解析后位于当前 workspace；`artifacts` 中每个条目能回指同一 `session_id`；`exports[].path` 只记录用户主动导出的本地路径摘要，workspace 外路径由用户管理，删除会话时不得被删除 |
| artifact registry entry | `id`, `session_id`, `artifact_type`, `path`, `format`, `capture_status`, `created_at`；可用文件还应有 `checksum` | `artifact_type` 属于 `RecordingArtifactType`；`path` 解析后位于当前会话目录的应用管理范围；`capture_status` 为 `degraded`、`missing` 或 `failed` 时必须有 `degradation_reason` |
| `transcript.json` | `id`, `session_id`, `source_artifact_id`, `status`, `segments`, `created_at` | `segments` 按 `start_ms` 升序；每段包含 `segment_id`, `start_ms`, `end_ms`, `text`，且 `start_ms < end_ms`；生成失败不得覆盖已有有效 transcript |
| `speaker_labels.json` | `session_id`, `labels`, `segment_mapping`；transcript-only 降级时通过对应 `speaker_labels` artifact 的 `capture_status` 和 `degradation_reason` 记录原因 | `labels[].is_verified_identity` 在 MVP 中必须为 `false`；`segment_mapping` 只能引用当前 transcript 的 segment；降级时不得修改 transcript 文本 |
| delete summary | `session_id`, `deleted`, `deleted_items`, `retained_external_exports`, `errors` 或 `warnings` | 摘要不得包含被删除文件内容；`deleted_items` 只记录当前会话目录内应用管理文件；workspace 外导出文件必须列入 retained 或不受影响说明 |

命令实现和测试可以使用 JSON Schema、typed fixtures 或等价断言方式；不能只通过字符串包含关系证明字段正确。

## Artifact 格式策略

| Artifact 类型 | MVP 要求 | 说明 |
|---|---|---|
| `screen_video` | 保留原生录制输出格式，并登记实际 `format` | 原始录制视频不因处理流水线被覆盖 |
| `system_audio` | 保留原生录制输出格式；派生处理音频使用标准化格式 | 无法捕获时登记降级 |
| `microphone_audio` | 保留原生录制输出格式；派生处理音频使用标准化格式 | 无法捕获时登记降级 |
| `mixed_audio` | 默认转写输入；派生处理音频使用标准化格式 | 由系统音频和麦克风音频混合或降级生成 |
| `normalized_audio` | WAV/PCM 派生音频，用于转写和 speaker labeling | 可重新生成，不覆盖原始音频 |
| `transcript_text` | JSON + 至少一种用户可读导出格式 | 需要时间戳 segments |
| `speaker_labels` | JSON | 匿名 labels，不代表真实身份 |

规则：

1. 原始录制产物保留原始容器和编码，并在 metadata 中记录实际格式。
2. 用于转写和 speaker labeling 的派生音频统一为 `normalized_audio`，文件扩展名为 `.wav`。
3. `normalized_audio` 是可重建派生产物，不能替代或覆盖 `system_audio`、`microphone_audio` 或 `mixed_audio` 原始/目标产物。

## 导入媒体数据规则

`import_media` 是用户显式选择本地文件后的会话登记路径，只创建 `source_type=imported_media` 的 `MeetingSession`，不自动扫描目录、下载远程媒体或上传源文件。MVP 首批支持格式和 artifact 登记规则如下：

| 类别 | 扩展名 | 登记 artifact type | 数据规则 |
|---|---|---|---|
| 音频 | `.wav`, `.m4a`, `.mp3` | `mixed_audio` | 在 workspace 会话目录保存一份 artifact 副本，记录实际 `format`，源文件不被覆盖或移动 |
| 视频/容器 | `.mp4`, `.mov` | `screen_video` | 在 workspace 会话目录保存一份 artifact 副本，记录实际 `format`，源文件不被覆盖或移动 |

导入媒体不得新增 `imported_media` artifact type。导入登记本身不承诺转码、标准化音频、转写或 speaker labeling；这些派生处理仍按后续 `normalized_audio`、`transcript_text` 和 `speaker_labels` artifact 规则生成。

## 路径、symlink 和删除边界

所有应用管理的会话目录、artifact、transcript、speaker label、导出包和日志都必须在解析真实路径后位于当前 workspace 的目标 session 目录内。以下边界必须有自动化负向用例：

1. 包含 `..` 的相对路径、解析后逃出 workspace 的绝对路径、缺失路径、目录路径和不支持扩展名必须返回 `invalid_input` 或 `path_conflict`，不得产生应用管理 artifact。
2. `import_media` 的源文件必须是用户显式选择的本地 regular file；如果源路径是 symlink，只能复制其解析后的 regular file 内容，不能在 workspace 内登记指向 workspace 外部的 symlink。
3. 应用管理 artifact 不得以 symlink 或 hardlink 的形式指向 workspace 外部文件；检测到这类路径时必须 fail closed，并保留可解释错误。
4. `delete_session` 必须先解析目标 session root，确认它位于当前 workspace 的 `sessions/<session_id>/` 下；路径不存在返回 `not_found`，路径越界或 symlink 逃逸返回 `path_conflict`。
5. 删除遍历不得 follow symlink 到 workspace 外部；如果会话目录内存在 symlink，只能删除 symlink 条目本身，不能删除其外部目标。
6. 删除会话不得删除 workspace 外导出文件、用户原始导入源文件、默认 workspace 之外的任意路径或外部工具生成的文件。

## 本地事件

Phase 1 不要求消息队列。可以在元数据或日志中记录本地事件，用于回放和排错。

| 事件 ID | 名称 | Producer | 触发条件 | Payload | 消费者责任 |
|---|---|---|---|---|---|
| EVT-MA-001 | `meeting_session.created.v1` | capture | 会话创建 | `event_id`, `session_id`, `occurred_at` | 更新本地索引 |
| EVT-MA-002 | `recording_artifact.changed.v1` | capture / processing | artifact 新增、降级或失败 | `event_id`, `session_id`, `artifact_id`, `status` | 更新元数据和回查视图 |
| EVT-MA-003 | `transcript.generated.v1` | transcription | transcript 生成成功 | `event_id`, `session_id`, `transcript_id` | 更新会话状态 |
| EVT-MA-004 | `processing.failed.v1` | processing | 转写或 speaker labeling 失败 | `event_id`, `session_id`, `code`, `summary` | 保留失败证据并允许重试 |
| EVT-MA-005 | `meeting_session.deleted.v1` | export / session management | 用户确认删除会话 | `event_id`, `session_id`, `occurred_at`, `result` | 记录删除摘要；不删除 workspace 外导出文件 |

事件规则：

1. 事件名必须包含版本。
2. 事件 payload 不携带完整 transcript 文本或不必要的媒体内容。
3. 重放事件不得覆盖原始媒体文件。
4. 删除事件只记录删除摘要，不携带被删除文件内容。

## 索引和搜索

| 索引 | 来源 | 更新策略 | 一致性要求 |
|---|---|---|---|
| `session_index` | `session.json` 和本地事件 | 会话创建、产物更新、转写完成时刷新 | 可重建；不能成为唯一事实源 |

## 数据保留和删除

| 数据类型 | 默认保留 | 删除规则 | 审计要求 |
|---|---|---|---|
| 原始视频和音频 | 保留直到用户删除会话 | 用户删除会话时删除会话目录内产物 | 本地记录删除时间和会话 ID |
| transcript 和 speaker labels | 保留直到用户删除会话或重新生成 | 随会话删除；重新生成派生产物不得覆盖原始媒体 | 本地记录生成和导出时间 |
| 处理日志 | 随会话保留 | 删除会话时删除 | 不记录密钥、完整外部凭据或无关敏感内容 |
| 导出包 | 用户选择路径后由用户负责管理 | 应用不自动删除 workspace 外导出文件 | 本地记录导出动作摘要 |

应用级加密和安全删除不属于 MVP 默认能力；更高敏感度、跨设备共享或产品化分发场景进入范围前必须重新评估。
