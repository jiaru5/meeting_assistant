# 8. 实现指导

本文件定义技术栈、应用边界、模块职责、依赖策略和部署约束。仓库结构、命令、测试和 CI 的落地由 `docs/engineering/` 维护。

## 平台和运行环境

| 项 | 决策 |
|---|---|
| 目标平台 | macOS |
| MVP CPU 架构 | Apple Silicon (`arm64`) |
| MVP macOS 下限 | macOS 26.5.1，来源为 adoption 时本机 `sw_vers` 输出 |
| MVP 使用模式 | 个人本地使用 |
| 后续使用模式 | 少量团队内部使用，需另行确认权限、分发和数据治理 |

## 技术方向

| 领域 | MVP 方向 | 状态 |
|---|---|---|
| 录制 | 原生 macOS 录制优先；辅助 capture adapter 只能在技术 spike 证明 native 不可行后经 spec-change/ADR 纳入 | confirmed |
| 媒体处理 | 本地媒体处理工具，候选包括 FFmpeg 或兼容能力 | 已确认方向；具体依赖后续确定 |
| 转写 | Adapter-first 本地转写；首个候选可复用现有本地 Whisper | confirmed |
| Speaker labeling | 本地 best-effort 匿名 speaker labeling；无可用引擎时降级 transcript-only | confirmed |
| 纪要生成 | 非 MVP 必需；用户可手动复制 transcript 到 GPT | confirmed |
| UI 交互面 | 最小 Swift/SwiftUI app + local helper / processing CLI | confirmed |
| 数据存储 | 本地文件和元数据，不要求远程数据库 | confirmed |
| Cloud/API | MVP 应用不自动调用外部模型 API | confirmed for MVP boundary |

## 模块边界

```mermaid
flowchart LR
  User["Local macOS User"]
  UI["Native control or local command surface"]
  Capture["native-capture"]
  Media["media-processing"]
  Transcribe["transcription"]
  Speaker["speaker-labeling"]
  Export["export"]
  Files[("workspace files and metadata")]
  External["External GPT tool (manual user copy only)"]

  User --> UI
  UI --> Capture
  Capture --> Files
  Files --> Media
  Media --> Files
  Files --> Transcribe
  Transcribe --> Files
  Files --> Speaker
  Speaker --> Files
  Files --> Export
  Export --> User
  User -. manual copy .-> External
```

Phase 2 允许用多个 worktree 并行推进，但调用方向必须保持单向和文件化边界：

```mermaid
flowchart LR
  User["Local macOS User"]
  Native["native-app\nSwiftUI / ViewModel"]
  Helper["native-helper\ncapture adapter boundary"]
  CLI["processing-cli\nCMD-MA-* command surface"]
  Workspace[("workspace files\nsession/artifact metadata")]
  Media["media-processing\nnormalized audio"]
  Transcript["transcription adapter\nfake or local runtime"]
  Speaker["speaker-labeling adapter\ntranscript-only fallback"]
  Export["export/delete"]
  External["External GPT tool\nmanual user action only"]

  User --> Native
  Native -->|"permission, dependency, recording UI"| Helper
  Native -->|"CMD-MA-004..008 via CLI bridge"| CLI
  Helper -->|"screen_video, system_audio,\nmicrophone_audio, mixed_audio"| Workspace
  CLI -->|"read/write by artifact contract"| Workspace
  Workspace --> Media
  Media --> Workspace
  Workspace --> Transcript
  Transcript --> Workspace
  Workspace --> Speaker
  Speaker --> Workspace
  Workspace --> Export
  Export --> Native
  User -. "copy/export transcript" .-> External
```

并行模块边界如下：

| 模块 | 可并行实现内容 | 冻结接口 | 禁止跨越的边界 |
|---|---|---|---|
| `native-app` | 权限/依赖状态、录制控制、处理状态、回查/导出/删除 UI 和 view model 测试 | `06-api-contracts.md` 的 `CMD-MA-*` 响应；`04-user-journeys-and-ui.md` 和 `12-ui-ux-design.md` 的 UI state contract | 不直接解释 `processing-cli` 内部状态；不绕过 command contract 改写 artifact；不自动调用外部模型 |
| `native-helper` / capture adapter | macOS capture spike、fake capture adapter、停止录制后的 artifact 登记 | `07-data-and-events.md` 的 artifact contract；`CMD-MA-001`/`CMD-MA-002` 的成功/失败响应 | 不做转写、speaker labeling、导出或业务数据解释；不静默切换到未纳入事实源的辅助 capture |
| `processing-cli` command surface | 依赖检查、导入媒体、处理、转写、speaker fallback、导出和删除命令 | `06-api-contracts.md` 的命令输入/响应/error/exit code；`07-data-and-events.md` 的文件契约 | 不反向依赖 native UI；不把 stderr、临时日志或内部 Python 对象当产品契约 |
| `media-processing` | 音频源选择、标准化音频和媒体 fixture | `mixed_audio`、`system_audio`、`microphone_audio`、`normalized_audio` artifact 语义 | 不覆盖原始媒体；不新增未定义 artifact type；不自动下载或上传媒体 |
| `transcription-adapter` | fake adapter、local transcription adapter、runtime/model preflight 和 transcript artifact | `generate_transcript` 契约；`transcript.json` segment 排序和时间范围语义 | 不生成会议纪要；不调用外部 API；失败不覆盖已有有效 transcript |
| `speaker-labeling-adapter` | transcript-only fallback 和匿名 speaker label artifact | `generate_speaker_labels` 契约；匿名 label 与降级语义 | 不声称真实身份；不修改 transcript text；不把 diarization 质量当 MVP 强承诺 |
| `export/delete` | 本地导出、复制、删除摘要和路径边界测试 | `export_transcript`、`delete_session` 契约；workspace 内外路径保留语义 | 不自动上传；删除不得越过当前 workspace；不得删除 workspace 外导出文件 |

## 组件职责

| 组件 | 职责 | 不负责 |
|---|---|---|
| `native-app` | 最小 Swift/SwiftUI app，提供原生录制控制、权限提示、录制状态和停止保存反馈 | 转写、speaker labeling、自动调用外部模型 |
| `native-helper` | 原生录制 helper 或本地服务边界，封装 capture adapter 和本地命令入口 | 业务数据解释、转写模型推理 |
| `processing-cli` | 依赖检查、音频格式处理、混音、校验、标准化处理输入、转写 adapter、speaker labeling adapter、导出 | 原生录制 UI、真实身份识别、自动上传 |
| `transcription-adapter` | 本地转写 adapter、时间戳 segments、transcript artifact | 真实身份识别、会议纪要生成 |
| `speaker-labeling-adapter` | best-effort 匿名 speaker labels；不可用时返回 transcript-only fallback | 真实姓名识别、强准确率承诺 |
| `export` | transcript 复制、Markdown/JSON/text 导出 | 自动上传到 GPT 或云服务 |
| `dependency-check` | 检查本地依赖、模型、权限和版本 | 自动安装所有依赖或自动改系统音频路由 |

## 依赖策略

| 依赖领域 | 策略 | 说明 |
|---|---|---|
| 原生 macOS 工具链 | 通过 bootstrap/check 脚本检查；人工安装 | 允许来源为 Apple 官方 Xcode/Command Line Tools |
| 媒体工具 | 通过 bootstrap/check 脚本检查；人工安装 | FFmpeg 或兼容能力是候选；脚本只检查，不自动下载 |
| 转写模型/runtime | Adapter-first，通过 bootstrap/check 脚本检查；人工安装 | 首个候选可复用现有本地 Whisper；具体 adapter 在组件骨架后落地 |
| Speaker labeling runtime | 通过 bootstrap/check 脚本检查；人工安装；允许缺失时降级 | WhisperX、pyannote.audio 或其他方案可作为后续 adapter 候选 |
| OBS/BlackHole | 不作为 MVP 主录制依赖 | 原生录制失败或用户改决策后可重新评估 |
| External GPT | 不作为应用依赖 | 仅允许用户手动复制或导出 transcript 后自行使用 |

## 原生录制方向

1. Phase 1 主路径是原生 macOS 录制，不以 OBS/BlackHole 作为主录制路径。
2. 原生录制实现必须输出 `07-data-and-events.md` 定义的文件和元数据契约。
3. 原生控制面采用最小 Swift/SwiftUI app + local helper / processing CLI 的组合。
4. 具体 capture API、录制目标支持范围、视频编码、音频捕获方式和权限细节可以在组件骨架阶段以 adapter 方式细化，但不得改变 `07-data-and-events.md` 的 artifact contract。
5. 录制层必须是可替换 adapter，不得和转写、speaker labeling 或导出强耦合。
6. 如果系统音频或目标 capture 在 MVP 环境中被技术 spike 证明不可行或不稳定，只能先记录证据，并通过 `10-open-decisions.md`、ADR、主责分卷和验证矩阵更新后，才允许把 OBS/BlackHole/FFmpeg 等辅助路径纳入实现范围。

## 原生 capture spike 和可测试性

原生 capture 进入真实实现前，必须先建立可自动化的 adapter 测试边界：

1. `native-app` 必须先有 fake capture adapter 或等价测试替身，用于确定性覆盖权限缺失、开始、录制中、停止、保存失败和降级状态。
2. 技术 spike 必须记录 macOS 版本、CPU 架构、候选 capture API、录屏/麦克风权限状态、系统音频可用性、目标窗口或屏幕能力、生成 artifact 类型和失败模式。
3. spike 产物必须能回指 `PV-MA-002`、`PV-MA-003` 和 `PV-MA-009`；如果只有人工证据，验证矩阵只能保持 `manual-evidence` 或 `partial`，不能标 `covered`。
4. 真实 native capture adapter 必须暴露可测试的 adapter identity、capture capability summary、失败 code 和降级原因，便于 XCUITest、Swift Testing 或 local smoke 断言。
5. 录制失败时不得静默切换到 `import_media`、OBS、BlackHole、FFmpeg 辅助录制或其他 capture adapter；只能返回 `capture_failed`、`permission_denied` 或 `dependency_missing` 等已定义失败。
6. 辅助 capture adapter 进入产品路径前，必须先完成 spec-change、ADR、验证矩阵更新和对应负向测试，证明代码不会在未授权情况下自动切换。

## Phase 2 实现顺序

Phase 2 按本地组件纵切推进，不先创建 Web 前端、远程后端服务或数据库：

1. `processing-cli` 先实现 `check_dependencies`、稳定命令响应、错误码和契约测试。
2. 再实现 artifact contract、导入媒体、normalized audio、transcript adapter fake、speaker-label transcript-only fallback 和导出。
3. `native-app` 负责最小 Swift/SwiftUI 控制面，并通过 Swift Testing 与 XCUITest 验证关键状态。
4. 每个真实产品行为进入实现时，必须同步更新对应 `PV-MA-*` 状态和证据。

## Bootstrap/Check 策略

Phase 1 采用 bootstrap/check 脚本，而不是一次性打包所有依赖。脚本只检查和提示，不自动下载模型、二进制或修改系统音频路由。

检查项至少包括：

1. 当前 macOS 版本和 CPU 架构。
2. 原生开发工具链是否可用。
3. 媒体处理工具是否可用。
4. 转写模型和 runtime 是否可用。
5. speaker labeling runtime 是否可用或明确不可用。
6. workspace 路径是否可写。
7. macOS 录屏、麦克风和文件访问权限状态是否可检测。
8. 依赖来源是否在允许来源清单内；版本/hash 锁定作为后续增强，不阻塞 MVP activation。

## 配置和环境

1. 本地配置不得包含真实 secret。
2. 会议 workspace 默认使用 `~/Movies/MeetingAssistant/`。
3. 依赖路径、模型路径和 workspace 路径应可配置。
4. 生产或团队内部分发前必须重新审查签名、公证、自动更新、许可证和数据策略。

## Activation 骨架边界

project activation 时已经创建最小非业务组件骨架，用于注册 manifest、门禁和 E2E 计划：

1. `native-app` skeleton：最小 Swift/SwiftUI app 结构和空录制控制入口，不实现真实录制。
2. `processing-cli` skeleton：依赖检查、处理命令和 adapter 接口骨架，不实现真实转写或 speaker labeling。
3. full-stack/E2E 在本地应用语境下定义为“component skeleton + dependency-check + artifact contract smoke test”的受控组合；不要求远程服务或数据库。

后续在这些组件内实现真实产品行为时，必须先对齐对应 `AC-MA-*` 和 `PV-MA-*`，补充自动化测试，并把验证矩阵状态从 `planned` 推进到真实覆盖状态。

## 可观测性

1. 每个本地 command 生成 `request_id`。
2. 每个 session 生成稳定 `session_id`。
3. 日志记录权限检查、依赖检查、录制开始/结束、产物生成、转写和 speaker labeling 状态。
4. 日志不得记录完整 transcript、外部凭据或不必要的敏感会议内容。
