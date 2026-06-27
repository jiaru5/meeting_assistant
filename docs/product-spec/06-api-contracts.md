# 6. API 契约

本文件定义本地命令、内部接口、错误、兼容性和外部集成边界。领域语义来自 `02-domain-model.md`，权限语义来自 `03-permissions-and-identity.md`。

## 契约原则

1. Phase 1 是本地 macOS 工具，不要求远程 HTTP API。
2. 本地命令或原生 UI action 必须对齐同一组 command contract，便于后续替换 UI 或录制引擎。
3. 应用不得在 MVP 中自动调用 GPT 或其他外部模型 API；用户可以主动复制或导出 transcript。
4. 命令输入、输出和错误结构必须稳定，方便自动化验证和后续 UI 集成。
5. 未知写入字段或不支持的命令参数必须 fail fast。
6. 每个 `CMD-MA-*` 在实现前必须定义成功响应关键字段、失败响应关键字段、错误码和 CLI exit code 断言；缺少这些断言时不能把对应 `PV-MA-*` 标为 `covered`。
7. 命令 schema 测试必须覆盖 unknown field、非法 enum、缺失必填字段和不支持参数；失败时不得产生会话、artifact、导出或删除副作用。

## 契约 Freeze 和变更条件

并行 worktree 开发时，command contract 的 frozen source 只包括本文件中定义的命令 ID、输入字段、成功响应关键字段、失败响应关键字段、错误码、CLI exit code 和兼容性规则。领域字段和 artifact 语义仍分别以 `02-domain-model.md` 和 `07-data-and-events.md` 为主责来源；UI 状态契约以 `04-user-journeys-and-ui.md` 和 `12-ui-ux-design.md` 为主责来源。

冻结后的 feature worktree 必须把本文件当成调用方和被调用方的共同边界：调用方只能依赖已冻结字段、错误码和 exit code；被调用方必须至少提供对应契约测试、fixture 或 fake adapter 证明边界可用。任何 worktree 发现需要改变冻结契约时，必须停止产品实现，改走 `spec-change`，先更新主责分卷、ADR 或 open decision，再继续实现。

契约变更分级如下：

| 变更级别 | 允许条件 | 必须动作 |
|---|---|---|
| 兼容变更 | 新增可选成功响应字段、补充 warning、扩展非必需诊断信息，且调用方忽略未知响应字段仍能工作 | 更新本文件的响应断言或测试说明；补契约测试；验证矩阵只能按实际证据推进 |
| 契约级变更 | 新增命令、输入字段、错误码、exit code、artifact 语义，或改变既有字段的必填性、枚举、失败副作用 | 暂停相关 worktree；按 `spec-change` 更新本文件及相关主责分卷；必要时追加 ADR；调用方和被调用方基于同一冻结版本重开实现 |
| 破坏性变更 | 删除、重命名命令/字段/error code，改变既有语义或让旧调用方无法按原契约处理结果 | 必须 ADR；更新验证矩阵、契约测试和集成计划；不得在普通功能 worktree 中夹带合并 |

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

`check_dependencies` 必须暴露本地 transcription runtime 的部署前置条件，但该检查不能替代真实 runtime smoke：

1. 必须报告 `transcription.runtime`、`transcription.model`、`transcription.model.multilingual` 和 `transcription.hardware` 等检查项。
2. `transcription.hardware` 只报告不含序列号、硬件 UUID、UDID 等敏感标识的本机能力摘要，例如 CPU 架构、芯片名称和内存等级；不得上传或保存到外部系统。
3. 对 `large-v3`、`large-v3-turbo` 同级 multilingual 模型，Apple Silicon `arm64` 且 16 GB 及以上 unified memory 可作为本地运行 preflight 通过条件；8 GB 到 16 GB 之间只能报告 `constrained`，低于 8 GB 或非 Apple Silicon 报告不适合该推荐模型等级。
4. 硬件 preflight 是部署建议和风险提示，不改变 `runtime=whisper_cpp` 的错误码语义；是否能作为 `PV-MA-007` covered 证据仍取决于真实 multilingual mixed-language smoke 纳入标准门禁。

### `generate_transcript`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | yes | 目标会话 |
| `source_artifact_id` | string | no | 默认使用 `mixed_audio`；缺失时用户可选择可用音频 |
| `language` | string | no | 可选语言提示 |
| `runtime` | enum `whisper_cpp` | no | 可选真实转写 runtime；缺省继续使用当前 adapter 默认策略 |

VS-MA-06 的首个真实本地转写 runtime 选择为 `whisper_cpp`。本地配置必须使用人工准备的 `whisper.cpp` CLI 可执行文件和本地模型文件，不自动下载模型、二进制或调用外部 API：

| 配置 | 必填条件 | 说明 |
|---|---|---|
| `runtime=whisper_cpp` | 显式请求真实 runtime 时必填 | 其他 runtime 值必须返回 `invalid_input` |
| `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME` | `runtime=whisper_cpp` 时必填 | 指向 `whisper.cpp` CLI 可执行文件，或可在 `PATH` 中解析的命令名 |
| `MEETING_ASSISTANT_TRANSCRIPTION_MODEL` | `runtime=whisper_cpp` 时必填 | 指向用户人工准备的本地 Whisper-compatible multilingual 模型文件 |

本机共享放置约定用于复用正式 runtime、模型和 smoke fixture，但不作为自动发现或下载机制：

| 资产 | 推荐位置 | 说明 |
|---|---|---|
| `whisper.cpp` runtime | `~/.local/opt/whisper.cpp/<version>/bin/whisper-cli`，并通过 `~/.local/bin/whisper-cli` 建立 symlink | runtime 可跨项目复用；升级版本时只调整 symlink |
| Whisper multilingual 模型 | `~/.local/share/ai-models/whisper.cpp/<model-family>/...` | 例如 `large-v3-turbo` 或量化 `large-v3`；模型文件不得提交到项目仓库 |
| 中英混合 smoke WAV | `~/.local/share/ai-fixtures/asr/zh-en-tech/mixed-zh-en-tech.wav` | fixture 必须是不含真实会议敏感内容的小样例 |

即使文件位于推荐目录，`generate_transcript runtime=whisper_cpp` 仍必须由 `MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME` 和 `MEETING_ASSISTANT_TRANSCRIPTION_MODEL` 显式指定目标路径。

会议语音以中文为主但常混入英文技术词汇，例如 `HTTP`、`LLM`、`clean architecture`、`EDA`。用于真实 smoke 和 `PV-MA-007` covered 证据的模型必须是 multilingual Whisper-compatible 模型，不能使用 English-only `.en` 模型作为完整覆盖证据；优先选择能稳定处理中英混合语音的 `large-v3` 或 `large-v3-turbo` 同级本地模型。较小 multilingual 模型只能作为低质量或开发 smoke 证据，不能单独证明产品级识别质量。

`runtime=whisper_cpp` 的错误语义：

1. 非 `whisper_cpp` 的 runtime 值必须返回 `invalid_input`，不得创建或覆盖 transcript artifact。
2. runtime 可执行文件、模型路径缺失、不可读或不可执行必须返回 `dependency_missing`。
3. runtime 进程执行失败、输出无法解析或 transcript segments 不满足排序与时间范围契约时，必须返回 `processing_failed`。
4. 失败不得覆盖原始媒体、已有有效 transcript artifact 或未选择替换的派生 artifact。
5. fake adapter 仍是确定性契约测试替身；fake adapter 证据不得作为真实 runtime covered 证据。

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
  "command": "start_native_recording",
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
  "message": "Required dependency is missing",
  "checks": [
    {
      "id": "media_tool.ffmpeg",
      "status": "missing",
      "required": true,
      "message": "FFmpeg executable was not found"
    }
  ],
  "details": [],
  "warnings": []
}
```

失败返回：

```json
{
  "ok": false,
  "request_id": "local-...",
  "command": "start_native_recording",
  "code": "permission_denied",
  "message": "可读错误摘要",
  "details": [],
  "warnings": []
}
```

响应规则：

1. 自动化入口使用 JSON 输出时，命令必须向 stdout 输出单个 JSON object；stderr 只能用于非结构化调试摘要，不能作为产品契约来源。
2. 每个响应都必须包含 `ok`、`request_id`、`command` 和 `warnings`；失败响应还必须包含 `code`、`message` 和 `details`。
3. `request_id` 只需在单次命令内可追踪，测试可以断言格式或存在性，不依赖固定值。
4. 成功响应中新增可选字段是兼容变更；删除、重命名或改变必填字段语义属于破坏性变更。
5. unknown field、非法 enum、缺失必填字段和不支持参数必须返回 `ok=false`、`code=invalid_input`，并使用非零 exit code。
6. 失败响应不得包含 stack trace、完整 transcript、媒体内容、外部凭据或不必要的本机敏感信息。

CLI exit code 断言：

| exit code | 适用结果 |
|---|---|
| `0` | `ok=true` |
| `1` | `internal_error` 或未归类的未预期错误 |
| `2` | `invalid_input` |
| `3` | `not_found`, `artifact_missing`, `path_conflict` |
| `4` | `permission_denied`, `dependency_missing` |
| `5` | `capture_failed`, `processing_failed` |

如果同一失败同时匹配多个 code，响应 `code` 和 exit code 必须选择最具体且最接近根因的一项。

### 每个命令的最小响应断言

| 命令 | 成功响应关键字段 | 失败响应关键字段 |
|---|---|---|
| `start_native_recording` | `session_id`, `status`, `capture_target`, `artifacts`, `warnings` | `code`, `message`, `details`; 权限或依赖不足时分别使用 `permission_denied` 或 `dependency_missing`，启动失败使用 `capture_failed` |
| `stop_recording` | `session_id`, `status`, `artifacts`; 不可用目标产物必须在对应 artifact 中给出 `capture_status` 和 `degradation_reason` | `code`, `message`, `details`; 缺失会话使用 `not_found`，重复或冲突使用可解释的当前最终状态或 `path_conflict` |
| `import_media` | `session_id`, `source_type`, `artifacts`; artifact 至少包含 `id`, `artifact_type`, `format`, `path`, `checksum` | `code`, `message`, `details`; 不支持格式、目录、缺失路径、非法路径和 unknown field 使用 `invalid_input` |
| `check_dependencies` | `command`, `checks`, `warnings`; 每个 check 至少包含 `id`, `status`, `required`, `message` | `code`, `message`, `checks`, `warnings`; 缺失必需依赖使用 `dependency_missing` |
| `generate_transcript` | `session_id`, `transcript_id`, `artifact_id`, `segment_count`, `warnings` | `code`, `message`, `details`; 缺失音频或 transcript 输入使用 `artifact_missing`；非法 runtime 使用 `invalid_input`；runtime 或模型缺失使用 `dependency_missing`；adapter 或 runtime 执行失败使用 `processing_failed` |
| `generate_speaker_labels` | `session_id`, `transcript_id`, `label_status`, `speaker_labels_artifact_id`, `warnings`; transcript-only 降级时 `label_status=transcript_only` 并给出 `degradation_reason` | `code`, `message`, `details`; 缺失 transcript 使用 `artifact_missing`，adapter 失败使用 `processing_failed`，但允许按规则降级为成功的 transcript-only 响应 |
| `export_transcript` | `session_id`, `export_type`, `export_package_id`, `target_path` 或 `content`, `warnings` | `code`, `message`, `details`; 缺失 transcript 使用 `artifact_missing`，导出路径冲突使用 `path_conflict` |
| `delete_session` | `session_id`, `deleted`, `deleted_items`, `retained_external_exports`, `warnings`; 删除完成或部分失败必须返回摘要 | `code`, `message`, `details`; `confirm` 非 `true` 使用 `invalid_input`，越界或 symlink 逃逸使用 `path_conflict`，目标不存在使用 `not_found` |

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
| Transcription adapter | 本地 `whisper.cpp` CLI + 用户人工准备的 multilingual Whisper-compatible 模型 | planned | 先稳定 adapter contract；真实 runtime 使用 `runtime=whisper_cpp` 和本地路径配置；不自动下载，不调用外部 API |
| Speaker labeling engine | 本地依赖或模型 | planned with fallback | 无可用引擎时允许降级为 transcript-only，并记录原因 |
| FFmpeg 或兼容媒体处理工具 | 本地依赖 | planned | 通过 bootstrap/check 脚本验证 |

## 兼容性规则

1. 新增可选 response 字段默认兼容。
2. 删除或重命名命令、字段、错误 code 属于破坏性变更，必须 ADR。
3. 产物文件格式改变必须同步 `07-data-and-events.md`、验收标准和验证矩阵。
4. 如果后续引入 HTTP API 或本地服务 API，必须先在本文件新增契约，再实现。
