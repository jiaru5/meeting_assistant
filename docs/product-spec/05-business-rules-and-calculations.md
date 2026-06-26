# 5. 业务规则和计算

本文件定义业务规则、状态机、派生计算、时间口径、幂等和重试语义。字段语义来自 `02-domain-model.md`，命令表达来自 `06-api-contracts.md`。

## 规则原则

1. 原始媒体文件优先保留；转写、speaker labels 和导出包都是可重新生成的派生产物。
2. 捕获不到某一目标产物时，不得把会话整体伪装为成功；必须登记降级状态和原因。
3. 匿名 speaker labels 是 best-effort 辅助信息，不代表真实身份，也不能覆盖原始 transcript。
4. 用户手动复制 transcript 到外部 GPT 工具是用户行为；应用不得自动上传会议内容。
5. 所有耗时处理必须可重试，并保留足够失败原因供用户修复依赖或权限。

## 会话状态机

| 规则 ID | 对象 | 当前状态 | 允许迁移 | 触发条件 | 副作用 |
|---|---|---|---|---|---|
| RULE-MA-STATE-001 | `MeetingSession` | `created` | `recording` | 用户启动原生录制且权限检查通过 | 创建会话目录，写入初始元数据 |
| RULE-MA-STATE-002 | `MeetingSession` | `recording` | `recorded` | 用户停止录制且至少一个媒体产物可用 | 登记媒体产物和校验摘要 |
| RULE-MA-STATE-003 | `MeetingSession` | `recording` | `failed` | 录制进程异常终止且没有可用媒体产物 | 写入失败原因 |
| RULE-MA-STATE-004 | `MeetingSession` | `recorded` | `processing` | 用户启动媒体处理或转写 | 锁定处理输入 artifact |
| RULE-MA-STATE-005 | `MeetingSession` | `processing` | `transcribed` | transcript 生成成功 | 登记 transcript 和可选 speaker labels |
| RULE-MA-STATE-006 | `MeetingSession` | `processing` | `recorded` | 处理失败但原始媒体仍可用 | 写入处理失败原因，允许重试 |
| RULE-MA-STATE-007 | `MeetingSession` | any non-deleted | `deleted` | 用户确认删除当前 workspace 内的会话 | 按 `07-data-and-events.md` 删除会话目录内应用管理文件；workspace 外导出文件不自动删除 |

## 产物完整性和降级

| 规则 ID | 名称 | 输入 | 输出 | 口径 | 验证入口 |
|---|---|---|---|---|---|
| RULE-MA-ARTIFACT-001 | 三音轨目标产物 | 原生录制结果 | `system_audio`, `microphone_audio`, `mixed_audio` artifacts | 三类音频都是 MVP 目标；无法生成时对应 artifact 记录 `degraded`、`missing` 或 `failed` 及原因 | `PV-MA-003` |
| RULE-MA-ARTIFACT-002 | 混合音频转写优先级 | 可用音频 artifacts | 转写输入 artifact | 默认使用 `mixed_audio`；若缺失，可由用户选择可用的系统音频或麦克风音频重试 | `PV-MA-006`, `PV-MA-007` |
| RULE-MA-ARTIFACT-003 | 原始媒体保护 | 录制产物、处理任务 | 派生产物 | 转写、speaker labeling 和导出不得覆盖原始视频或音频文件 | `PV-MA-009` |
| RULE-MA-ARTIFACT-004 | 标准化处理音频 | 可用音频 artifacts | `normalized_audio` | 转写和 speaker labeling 优先使用可重建的 `.wav` 标准化音频；该产物不得替代原始音轨 | `PV-MA-006`, `PV-MA-009` |

## 转写规则

| Rule ID | 名称 | 输入 | 输出 | 口径 | 验证入口 |
|---|---|---|---|---|---|
| RULE-MA-TRANSCRIPT-001 | 时间戳 transcript | 音频 artifact | `Transcript` with ordered segments | 分段必须包含 `start_ms`、`end_ms` 和 text，且按时间升序 | `PV-MA-007` |
| RULE-MA-TRANSCRIPT-002 | 失败可重试 | 音频 artifact、转写引擎 | 处理状态 | 模型缺失、依赖缺失、格式错误或运行失败不得删除原始媒体 | `PV-MA-009` |

## 匿名 Speaker Label 规则

| Rule ID | 名称 | 输入 | 输出 | 口径 | 验证入口 |
|---|---|---|---|---|---|
| RULE-MA-SPEAKER-001 | best-effort 匿名标签 | transcript segments、可用音频 | `speaker_label` | MVP 可输出 `SPEAKER_01` 这类匿名标签；不得声称真实姓名或身份 | `PV-MA-008` |
| RULE-MA-SPEAKER-002 | 标签不覆盖文本 | transcript segments、speaker labels | transcript review | speaker label 是段落附加信息，不能修改原始转写文本 | `PV-MA-008`, `PV-MA-009` |
| RULE-MA-SPEAKER-003 | 质量限制可见 | speaker labeling 结果 | 用户提示或元数据 | 如果引擎缺失、失败或无法稳定区分说话人，必须允许降级为 transcript-only，并记录原因 | `PV-MA-008` |

## 时间口径

| 规则 ID | 场景 | 时区 | 区间 | 当前时间来源 |
|---|---|---|---|---|
| RULE-MA-TIME-001 | 会话开始/结束时间 | 本机系统时区 | `[started_at, ended_at]` | 本地系统 clock |
| RULE-MA-TIME-002 | transcript segment | 相对会话媒体起点 | `[start_ms, end_ms)` | 媒体处理或转写引擎输出 |

## 幂等和重试

| 操作 | 幂等键 | 重试语义 | 冲突响应 |
|---|---|---|---|
| Start native recording | new `session_id` | 重试创建新会话；不得复用已失败会话目录除非用户显式选择 | 返回本地冲突或目录已存在错误 |
| Stop recording | `session_id` | 重复停止应返回当前最终状态 | 返回已停止状态和已有 artifacts |
| Generate transcript | `session_id` + `source_artifact_id` + engine config hash | 同配置重复执行可复用或覆盖派生产物，但不得覆盖原始媒体 | 返回处理冲突或要求用户确认 |
| Export transcript | `session_id` + `export_type` + target path | 重复导出可覆盖目标文件前必须由用户确认或使用新文件名 | 返回路径冲突 |

## 并发控制

| 对象 | 策略 | 客户端责任 | 系统责任 |
|---|---|---|---|
| `MeetingSession` | 单会话处理锁 | 不同时启动多个处理任务写同一会话元数据 | 检测 lock，失败时给出可重试错误 |
| `RecordingArtifact` | 原始媒体只追加，不就地覆盖 | 用户不要手动编辑 workspace 内原始文件 | 检测缺失或 checksum 改变并标记异常 |
