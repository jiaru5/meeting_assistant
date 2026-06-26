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
| `session.json` | `MeetingSession` | `id`, `source_type`, `status`, `started_at`, `workspace_dir`, `artifacts` | 会话主元数据 |
| `transcript.json` | `Transcript` | `id`, `session_id`, `source_artifact_id`, `segments` | 结构化 transcript |
| `speaker_labels.json` | `SpeakerLabel` | `session_id`, `labels`, `segment_mapping` | 匿名 speaker labels |
| `transcript.md` | `ExportPackage` | n/a | 用户可读 Markdown 导出 |

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

应用级加密和安全删除不属于 MVP 默认能力；后续团队内部使用或更高敏感度场景进入范围前必须重新评估。
