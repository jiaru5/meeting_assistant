# Native App

本目录承载最小 Swift/SwiftUI 原生控制面。组件注册状态以 `harness/project-manifest.json` 为准。

当前已实现 VS-MA-12 权限和依赖状态面：

1. `check_dependencies` JSON 契约的 Swift `Codable` 读模型。
2. 通过 `meeting-assistant-cli check_dependencies --format json` 调用 processing-cli 的桥接 runner。
3. 权限和依赖状态 view model，覆盖 ready、blocked、checking 和 failed 状态。
4. SwiftUI 状态 surface，包含稳定 accessibility identifier，供后续 XCUITest 接入。
5. Swift Testing 覆盖 JSON 解码、缺失依赖、权限 denied/unknown、ready 状态、runner 失败和 locator 常量。

当前已实现 VS-MA-13 fake recording UI/state 边界：

1. `start_native_recording` 和 `stop_recording` 的 Swift command/client protocol，只表达 frozen UI 调用边界。
2. deterministic `FakeRecordingCommandClient`，不调用真实 CLI、helper、capture API 或 processing 内部状态。
3. `RecordingControlViewModel` 覆盖 idle、ready、starting、recording、stopping、recorded 和 failed 状态。
4. `RecordingControlView` 覆盖开始、录制中、停止、保存成功和失败状态，并暴露稳定 accessibility identifier。
5. Swift Testing 覆盖 readiness 未通过不能 start、start/stop 成功、start/stop 失败、重复触发和 locator 常量。
6. XCTest-hosted SwiftUI smoke 覆盖权限/依赖缺失状态、readiness blocked、fake recording start、recording、stop saved summary、start/stop failure，并通过生产 SwiftUI source contract 断言 `ma.permissionDependency.*` / `ma.recording.*` locator 和关键可见文案仍由视图定义使用。
7. 持久 `MeetingAssistantNative.xcodeproj` 提供最小 macOS app bundle target 和 app-bundle XCUITest target；`AppBundleLocatorSmokeTests` 使用 `XCUIApplication()` 启动 `.app`，在有内置屏幕的本机通过 `MA_NATIVE_APP_TEST_DISPLAY=built-in` 将测试窗口定位到内置屏并断言窗口中心落在内置屏 frame 内，通过 deterministic launch fixture 覆盖默认 blocked readiness、ready fake start/stop、start failure error locator，且不调用真实 helper/CLI/capture/runtime。

当前已实现 VS-MA-16 native processing state consumer 边界：

1. `ProcessingCommandClient` 只表达已冻结的 `generate_transcript` 和 `generate_speaker_labels` request/response 模型，失败 `details` 使用 tolerant decode 并只展示摘要。
2. `ProcessingCommandProcessRunner` 是可注入生产桥，只通过 `Process` 调用公开命令名和冻结 flag，解析 stdout JSON；stderr 只作为桥接诊断摘要，不作为产品契约。
3. `ProcessingCommandFakeClient` 只返回 deterministic fake response，并记录请求用于测试断言；不读取 `processing-cli` 内部实现。
4. `ProcessingStateViewModel` 覆盖 idle、blocked、generatingTranscript、generatingSpeakerLabels、completed、degraded、failed，使用 `PermissionDependencyStatusState.canRunProcessing` fail closed，busy 时阻止重复 start，retry 重放上一轮请求。
5. `ProcessingStateView` 暴露 `ma.processing.*` accessibility identifier，覆盖 start、retry、transcript status、speaker label status、success、error、degradation 和 warnings。
6. `MeetingAssistantNativeApp` 通过 deterministic `MA_NATIVE_APP_SMOKE_FIXTURE=processing-*` fixture 验证 app-bundle locator 和 processing state，不调用真实 CLI、helper、capture、runtime、provider、网络、下载、真实 pasteboard、真实文件 picker 或文件删除。

当前已实现 VS-MA-17 read-only transcript review consumer 边界：

1. `TranscriptReviewReadModel` 只读取 `transcript.json` 的 `id`、`session_id`、`source_artifact_id`、`status`、`segments[]`、`segment_id`、`start_ms`、`end_ms`、`text`、可选 `speaker_label`，以及 `speaker_labels.json` 的 `session_id`、`labels`、`segment_mapping`。
2. `TranscriptReviewWorkspaceLoader` 在 test/smoke launch context 中只读加载 workspace `sessions/<session_id>/session.json`，按 artifact registry 读取 `transcript_text` 和可选 `speaker_labels`，并拒绝 session id traversal、artifact path escape、symlink artifact 和 checksum drift。
3. `TranscriptReviewViewModel` 输出稳定可见状态：heading、summary、timestamp label、transcript text、匿名 speaker label、transcript-only degradation reason、missing transcript 和 empty transcript。
4. `TranscriptReviewView` 暴露 `ma.transcript.*` accessibility identifier，供 Swift Testing 和 XCUITest 稳定断言。
5. `MeetingAssistantNativeApp` 通过 deterministic `MA_NATIVE_APP_SMOKE_FIXTURE=transcript-review|transcript-empty` fixture、`MA_NATIVE_TRANSCRIPT_WORKSPACE` + `MA_NATIVE_TRANSCRIPT_SESSION_ID` 临时 workspace fixture，以及测试专用 `MA_NATIVE_APP_TEST_DISPLAY` 窗口定位 env 验证 app-bundle locator，不调用真实 CLI、helper、capture、runtime、provider、网络或下载。

当前已实现 VS-MA-18/VS-MA-19 deterministic native action consumer 边界：

1. `TranscriptActionCommandClient` 只表达已冻结的 `export_transcript` 和 `delete_session` 调用模型；copy 使用 `export_type=plain_text` 且 `target_path=nil`，export 使用注入的目标路径，delete 使用 `confirm=true`。
2. `TranscriptActionFakeCommandClient` 只返回 deterministic fake response，并记录请求用于测试断言；不调用 `processing-cli`、helper、provider、网络 API、外部 GPT/Qwen/API、真实 clipboard、真实文件 picker 或直接删除文件。
3. `TranscriptReviewActionsViewModel` 覆盖用户主动触发的 copying、exporting、delete confirmation、deleting、success、failure、cancel 状态；copy 只在成功 content 返回后写入注入 clipboard；export cancel/no destination 不发命令；delete cancel 不发命令；delete failure summary 保持可见。
4. `TranscriptReviewActionsView` 暴露 `ma.transcriptAction.*` accessibility identifier，覆盖 copy/export/delete 按钮、状态、成功、失败、delete prompt、confirm 和 cancel。
5. `MeetingAssistantNativeApp` 通过 deterministic `MA_NATIVE_APP_SMOKE_FIXTURE=transcript-action-*` fixture 验证 app-bundle locator 和用户触发状态，不调用真实 CLI、helper、capture、runtime、provider、网络、下载、真实 pasteboard 或真实文件删除。

当前目录仍不得实现真实录制、屏幕捕获、系统音频捕获、麦克风捕获、转写 provider、speaker labeling provider、外部模型调用、公开 `normalize_audio` 命令、真实 clipboard mutation、真实导出目标 picker、直接文件删除或自动依赖下载。VS-MA-13 fake recording 和 app-bundle locator smoke 证据只能用于 `PV-MA-001`、`PV-MA-002`、`PV-MA-005` 的 partial 状态，不能替代 VS-MA-14 的真实 native capture、真实 macOS 权限负向用例或真实 runtime/model smoke。VS-MA-16 native processing state 证据只能证明 native consumer 可通过冻结命令响应和 fake/process bridge 边界表达处理状态，不能证明真实 capture、真实 provider 质量或发布包。VS-MA-17 read-only transcript review 证据只能证明 native UI 可消费确定性 transcript/speaker label fixture 并显示回查状态，不能替代真实 processing runtime。VS-MA-18/VS-MA-19 native action 证据只能证明 deterministic native consumer UI、fake command boundary、injected clipboard/destination 和确认/取消状态，不证明 processing provider、真实 pasteboard、真实文件 picker 或真实删除执行。
