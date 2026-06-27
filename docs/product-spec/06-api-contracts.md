# 6. API 契约

本文件定义本地命令、内部接口、错误、兼容性和外部集成边界。领域语义来自 `02-domain-model.md`，权限语义来自 `03-permissions-and-identity.md`。

## 契约原则

1. Phase 1 是本地 macOS 工具，不要求远程 HTTP API。
2. 本地命令或原生 UI action 必须对齐同一组 command contract，便于后续替换 UI 或录制引擎。
3. 应用不得在 MVP 中自动调用 GPT 或其他外部模型 API；用户可以主动复制或导出 transcript。
4. 命令输入、输出和错误结构必须稳定，方便自动化验证和后续 UI 集成。
5. 未知写入字段或不支持的命令参数必须 fail fast。

## 本地命令契约

命令名是产品契约；实际实现可以是 CLI、原生 UI action 或内部 application service。

| 命令 ID | 命令 | 权限 | 说明 |
|---|---|---|---|
| CMD-MA-001 | `start_native_recording` | `meeting_session.create` | 创建会话并启动原生 macOS 录制 |
| CMD-MA-002 | `stop_recording` | `meeting_session.create` | 停止当前会话录制并登记媒体产物 |
| CMD-MA-003 | `import_media` | `meeting_session.create` | 将用户选择的已有媒体登记为会话，作为处理回退或测试路径 |
| CMD-MA-004 | `check_dependencies` | local process | 检查 Phase 1 所需依赖、模型和权限状态 |
| CMD-MA-005 | `generate_transcript` | `recording_artifact.write` | 通过 transcription adapter 从可用音频生成 transcript |
| CMD-MA-006 | `generate_speaker_labels` | `recording_artifact.write` | 为 transcript 生成 best-effort 匿名 speaker labels |
| CMD-MA-007 | `export_transcript` | `transcript.export` | 导出 transcript 到本地文件或复制缓冲区 |
| CMD-MA-008 | `delete_session` | `meeting_session.delete` | 删除当前 workspace 内目标会话目录中的应用管理产物 |

## 命令到能力映射

本表只说明命令如何承接 `01-product-scope.md` 的能力 ID。命令字段、错误结构和外部集成边界仍以本文件其他章节为准。

| 命令 | 主要能力 | 必须验证的产品结果 | 验证入口 |
|---|---|---|---|
| `start_native_recording` | `CAP-MA-001`, `CAP-MA-002` | 录制前权限和环境不足时 fail closed；检查通过后创建会话并进入录制中状态 | `PV-MA-001`, `PV-MA-002` |
| `stop_recording` | `CAP-MA-002`, `CAP-MA-003` | 停止当前录制，写入会话状态、媒体产物登记和降级原因 | `PV-MA-002`, `PV-MA-003` |
| `import_media` | `CAP-MA-004`, `CAP-MA-006` | 登记用户显式选择的媒体，作为处理回退或测试路径；不改变原生录制主路径 | `PV-MA-004`, `PV-MA-006` |
| `check_dependencies` | `CAP-MA-001`, `CAP-MA-005` | 稳定输出本地依赖、workspace、权限和允许来源状态；必需依赖缺失时 `ok=false` | `PV-MA-001`, `PV-MA-005` |
| `generate_transcript` | `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-009` | 使用可用音频或 `normalized_audio` 生成按时间排序的 transcript；失败不覆盖原始媒体 | `PV-MA-006`, `PV-MA-007`, `PV-MA-009` |
| `generate_speaker_labels` | `CAP-MA-008`, `CAP-MA-009` | 输出匿名 labels 或 transcript-only 降级原因；不声称真实身份、不覆盖 transcript 文本 | `PV-MA-008`, `PV-MA-009` |
| `export_transcript` | `CAP-MA-010`, `CAP-MA-011` | 导出或返回可复制 transcript；不自动上传到 GPT 或外部模型 API | `PV-MA-010`, `PV-MA-011` |
| `delete_session` | `CAP-MA-012` | 删除当前 workspace 内目标会话目录中的应用管理文件；不删除 workspace 外导出文件 | `PV-MA-012` |

## 命令输入

### `start_native_recording`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `title` | string | no | 可选会议标题 |
| `capture_target` | enum `screen`, `window`, `area` | no | 录制目标；具体支持取决于原生录制实现 |
| `workspace_dir` | path | no | 用户指定工作区；缺省使用本地默认工作区 |
| `capture_system_audio` | boolean | yes | 是否尝试捕获系统音频 |
| `capture_microphone_audio` | boolean | yes | 是否尝试捕获麦克风音频 |

### `stop_recording`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | yes | 目标会话 |

### `import_media`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `path` | path | yes | 用户显式选择的本地媒体文件 |
| `title` | string | no | 可选会话标题 |

MVP 首批 `import_media` 只支持用户显式提供的本地文件路径，不自动扫描目录、下载远程媒体或上传源文件。支持格式白名单如下：

| 类别 | 扩展名 | 登记 artifact type |
|---|---|---|
| 音频 | `.wav`, `.m4a`, `.mp3` | `mixed_audio` |
| 视频/容器 | `.mp4`, `.mov` | `screen_video` |

导入成功时创建 `source_type=imported_media` 的 `MeetingSession`，在 workspace 会话目录内保存一份 artifact 副本，并登记实际 `format`；源文件不得被覆盖或移动。`import_media` 不新增 `imported_media` artifact type，也不承诺转码、转写或说话人识别；标准化音频、转写和 speaker labels 仍由后续处理纵切以及 `generate_transcript`、`generate_speaker_labels` 等对应命令能力承担。

不支持格式、目录路径、缺失路径和非法路径必须返回 `invalid_input`。

### `check_dependencies`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `workspace_dir` | path | no | 要检查的会议 workspace；缺省使用默认 workspace |
| `format` | enum `json`, `pretty` | no | 输出格式；自动化验证使用 `json` |

### `generate_transcript`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | yes | 目标会话 |
| `source_artifact_id` | string | no | 默认使用 `mixed_audio`；缺失时用户可选择可用音频 |
| `language` | string | no | 可选语言提示 |
| `runtime` | string | no | 可选转写 runtime 名称；缺省由本地 adapter 配置选择 |

### `generate_speaker_labels`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | yes | 目标会话 |
| `transcript_id` | string | yes | 已生成 transcript |
| `allow_transcript_only_fallback` | boolean | yes | MVP 固定允许在 speaker labeling 不可用时保留 transcript-only |

### `export_transcript`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | yes | 目标会话 |
| `export_type` | enum `plain_text`, `markdown`, `json` | yes | 导出格式 |
| `target_path` | path | no | 如为空，则可复制到剪贴板或返回文本 |

### `delete_session`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | yes | 目标会话 |
| `workspace_dir` | path | no | 要删除的会话所在 workspace；缺省使用默认 workspace 或当前配置 workspace |
| `confirm` | boolean | yes | 必须为 `true`，表示用户明确确认删除该会话 |

## 命令响应

所有命令返回稳定结构：

```json
{
  "ok": true,
  "request_id": "local-...",
  "session_id": "session-...",
  "artifacts": [],
  "warnings": []
}
```

`check_dependencies` 成功或失败都必须返回稳定 `checks` 列表。缺失必需依赖时 `ok` 为 `false`，不能把缺失项当成成功。

```json
{
  "ok": false,
  "request_id": "local-...",
  "command": "check_dependencies",
  "code": "dependency_missing",
  "checks": [
    {
      "id": "media_tool.ffmpeg",
      "status": "missing",
      "required": true,
      "message": "FFmpeg executable was not found"
    }
  ],
  "warnings": []
}
```

失败返回：

```json
{
  "ok": false,
  "request_id": "local-...",
  "code": "permission_denied",
  "message": "可读错误摘要",
  "details": []
}
```

## 错误响应

| code | 场景 |
|---|---|
| `permission_denied` | macOS 录屏、麦克风或文件权限缺失 |
| `dependency_missing` | FFmpeg、转写模型、speaker labeling 引擎或其他 Phase 1 依赖缺失 |
| `invalid_input` | 参数格式错误、路径非法或媒体文件不支持 |
| `artifact_missing` | 所需视频、音频或 transcript 产物不存在 |
| `capture_failed` | 原生录制启动或结束失败 |
| `processing_failed` | 转写或 speaker labeling 失败 |
| `path_conflict` | 会话目录、导出路径或 lock 冲突 |
| `not_found` | 目标会话、产物或路径不存在 |
| `internal_error` | 未预期错误 |

## 外部集成边界

| 外部系统 | 集成方式 | MVP 状态 | 约束 |
|---|---|---|---|
| GPT 或其他外部 LLM 工具 | 用户手动复制或导出 transcript 后自行使用 | 允许的用户动作 | 应用不自动上传、不保存外部账号或 API key |
| Transcription adapter | 本地依赖或模型 | planned | 先稳定 adapter contract；首个候选可复用现有本地 Whisper，具体 runtime 由 dependency check 报告 |
| Speaker labeling engine | 本地依赖或模型 | planned with fallback | 无可用引擎时允许降级为 transcript-only，并记录原因 |
| FFmpeg 或兼容媒体处理工具 | 本地依赖 | planned | 通过 bootstrap/check 脚本验证 |

## 兼容性规则

1. 新增可选 response 字段默认兼容。
2. 删除或重命名命令、字段、错误 code 属于破坏性变更，必须 ADR。
3. 产物文件格式改变必须同步 `07-data-and-events.md`、验收标准和验证矩阵。
4. 如果后续引入 HTTP API 或本地服务 API，必须先在本文件新增契约，再实现。
