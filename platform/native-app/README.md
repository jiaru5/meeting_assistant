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
8. `scripts/test.sh` 默认运行快速组件测试，不启动真实 `.app` XCUITest；需要完整 app-bundle UI smoke 时运行 `scripts/test-app-bundle.sh`，或设置 `MA_NATIVE_APP_RUN_XCUITEST=1 scripts/test.sh`。`scripts/test-app-bundle.sh` 默认复用忽略目录 `build/DerivedData/AppBundleUITests` 以减少重复 Xcode 构建时间，必要时可用 `MA_NATIVE_APP_DERIVED_DATA_PATH` 指向隔离目录。

当前已实现 VS-MA-14/VS-MA-15 controlled native capture artifact registration 部分证据：

1. `NativeCaptureAdapter` 定义原生 capture adapter 的受控 start/stop 边界，固定只登记 `screen_video`、`system_audio`、`microphone_audio`、`mixed_audio` 四类目标产物。
2. `ControlledNativeCaptureAdapter` 是组件内 deterministic adapter，用于 Swift Testing 覆盖 start failure、stop partial artifacts、interruption 和 no-media 失败；它不调用 ScreenCaptureKit、AVFoundation、OBS、BlackHole、FFmpeg、helper、processing-cli、网络或外部 provider。
3. `NativeRecordingCommandClient` 复用冻结的 `RecordingCommandClient`、`start_native_recording` 和 `stop_recording` command name；权限 denied/unknown 使用既有 `permission_denied` fail closed，start 失败使用既有 `capture_failed`，不新增 command field、error code 或 exit code。
4. `RecordingSessionStore` 在 start 成功后写入 `workspace/sessions/<session_id>/session.json`，使用 `source_type=native_recording` 和 `status=recording`；stop 后写入 `recorded` 或 `failed`、`started_at`、`ended_at`、`workspace_dir`、`created_at`、`updated_at` 和完整 artifact registry。
5. stop artifact registration 对可用文件写入 `checksum` 和 `created_at`；对 degraded/missing/failed 写入 `degradation_reason`；至少一个 available media 返回 `ok=true status=recorded`，无 available media 返回 `ok=false code=capture_failed status=failed`。
6. Swift Testing 覆盖权限 fail closed、start session metadata、四类 artifact/checksum/degradation、no-available-media failure、interrupted partial success、重复 stop 幂等，以及 session id traversal、`session.json` symlink、artifact symlink 和 artifact hardlink fail closed。
7. `RecordingControlView` 仅 additive 暴露 `ma.recording.artifact.<artifact_type>.status` 和 `.degradation` locator；既有 phase/status 文案和 start/stop locator 不移除。
8. `MeetingAssistantNativeApp` 默认继续使用 `FakeRecordingCommandClient`；`MA_NATIVE_RECORDING_CLIENT=controlled` 是 Debug/XCTest-only 测试注入路径，必须带 `MA_NATIVE_APP_XCTEST=1` 或 XCTest marker，并通过 `MA_NATIVE_RECORDING_WORKSPACE` 或既有 `MEETING_ASSISTANT_WORKSPACE` 指向显式临时 workspace。app-bundle XCUITest 会启动 `.app`、点击 Start/Stop、断言 artifact status/degradation locator，并检查 `session.json` 写入四类 artifact。Release build 下该 env hook 必须回落 fake。

当前已新增 VS-MA-14/VS-MA-15 Apple ScreenCaptureKit native capture adapter spike：

1. `AppleScreenCaptureKitNativeCaptureAdapter` 是唯一允许在 native-app 内使用 Apple 官方 `ScreenCaptureKit` / `AVFoundation` capture API 的文件；Apple framework 类型被限制在该文件内。
2. 该 adapter 实现既有 `NativeCaptureAdapter`，只复用冻结的 `start_native_recording` / `stop_recording` 语义，不新增 command 字段、error code、exit code、artifact type、schema 或 UI state。
3. 真实 runtime 使用 `SCShareableContent`、`SCContentFilter`、`SCStream` 和 `SCRecordingOutput` 生成一个临时 combined recording file；临时文件只作为 adapter-local 输入，最终 `session.json`、artifact path、checksum 和 fail-closed 路径仍由 `RecordingSessionStore` 负责。
4. 当前 ScreenCaptureKit spike 只能证明 combined recording file 形态：可用 combined file 登记为既有 `screen_video`；不可证明的 `system_audio`、`microphone_audio` 和 `mixed_audio` 登记为 `degraded` 或 `missing` 并写入 `degradation_reason`。无可用媒体时通过既有 `capture_failed` 语义 fail closed。
5. Swift Testing 使用 deterministic fake runtime 覆盖 adapter capability、非 screen target fail-closed、combined file 的 partial artifact degradation、无可用媒体的 `capture_failed` session 结果；测试不依赖真实会议数据、真实 TCC 权限或真实系统音频。
6. 该 adapter 不通过 Release env hook 自动启用；现有 app bundle 仍默认 fake。Debug/XCTest-only hook 可启用 controlled recording fixture；真实 Apple adapter 只能在额外显式设置 `MA_NATIVE_RECORDING_CLIENT=apple_screencapturekit`、`MA_NATIVE_CAPTURE_SMOKE=1` 和 `MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1` 的 opt-in app-bundle smoke 中使用。
7. 该 spike 不引入 OBS、BlackHole、FFmpeg 辅助 capture，不调用 helper/processing-cli，不做 processing、transcription、speaker labeling、导出、删除、网络请求、自动下载、真实 pasteboard 或真实文件 picker。

当前已新增 VS-MA-14/VS-MA-15 opt-in 真实 native capture smoke 入口：

1. `scripts/native-capture-smoke.sh` 只能在显式设置 `MA_NATIVE_CAPTURE_SMOKE=1` 时运行，不属于默认 `scripts/test.sh`、app-bundle XCUITest 或 Release 门禁。
2. 该脚本临时构建 Swift executable，组合既有 `NativeRecordingCommandClient`、`MacOSNativeCapturePermissionChecker`、`AppleScreenCaptureKitNativeCaptureAdapter` 和 `RecordingSessionStore`，不新增 command、artifact、error、exit code、UI state 或 app hook。
3. 默认写入忽略目录 `build/native-capture-smoke/workspace-*`；可用 `MA_NATIVE_CAPTURE_SMOKE_WORKSPACE`、`MA_NATIVE_CAPTURE_SMOKE_DURATION_SECONDS`、`MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO` 和 `MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO` 显式覆盖。默认只请求屏幕录制，降低 microphone permission 对 smoke 的影响。
4. 成功时脚本会验证 `session.json`、`screen_video` 为 `available`、录制文件非空、`sha256:` checksum 存在，并输出 JSON summary。权限 denied/unknown、macOS runtime 不足、显示处于 asleep/no-display 状态、ReplayKit stop failure 或 ScreenCaptureKit 未产出文件时必须 fail closed。
5. 该 smoke 只能提供真实 ScreenCaptureKit 输出的本地 opt-in partial evidence；不证明独立系统音频或麦克风音频、生产 app 默认启用真实 adapter、native-to-processing invocation、release bundle 或任意 `PV-MA-*` 已 `covered`。

当前已新增 VS-MA-20 opt-in app-bundle 真实 capture UI smoke 入口：

1. `AppBundleLocatorSmokeTests.testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled` 默认 `XCTSkip`，只有测试进程显式设置 `MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1` 时运行。
2. 正确执行入口是 `MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh`。该脚本会先 `build-for-testing`，再把 `MA_NATIVE_APP_REAL_CAPTURE_SMOKE=1` 注入生成的 `.xctestrun`，最后用 `test-without-building -only-testing:MeetingAssistantNativeAppUITests/AppBundleLocatorSmokeTests/testOptInAppleScreenCaptureKitRecordsFromDesignedShellWhenExplicitlyEnabled` 跑单用例；不要只依赖 shell env 直接调用 `xcodebuild test`。
3. 该测试从设计化 shell 点击既有 `ma.recording.startButton` 和 `ma.recording.stopButton`，通过 Debug/XCTest-only `MA_NATIVE_RECORDING_CLIENT=apple_screencapturekit` 选择真实 `AppleScreenCaptureKitNativeCaptureAdapter`，并仍经由 `NativeRecordingCommandClient`、`MacOSNativeCapturePermissionChecker` 和 `RecordingSessionStore`。
4. 该 smoke 设置 `MA_NATIVE_CAPTURE_SMOKE_SYSTEM_AUDIO=false` 和 `MA_NATIVE_CAPTURE_SMOKE_MICROPHONE_AUDIO=false`，默认只证明 screen-only 真实录制，降低麦克风权限对 UI smoke 的影响。
5. 成功时验证 UI 状态为 saved、`screen_video` 为 `available`、其他音频 artifact 按未请求策略为 `missing`，并校验 workspace `session.json`、`screen_video` 文件非空和 `sha256:` checksum。
6. 如果 macOS 没有给测试 app bundle Screen Recording / Screen & System Audio Recording 权限，Start 会 fail closed，UI 暴露 `ma.recording.error`，通常为 `permission_denied`；脚本会把 xcodebuild 输出保存到 `build/DerivedData/AppBundleUITests/real-capture-app-bundle-smoke.log`，并打印系统设置入口、app bundle 位置和重跑命令。这类失败是本机 TCC 环境 blocker，不得报告为真实录制通过。
7. 该 smoke 不属于默认 `scripts/test.sh`、默认 app-bundle XCUITest 或 Release 门禁；通过也仍是 partial evidence，不证明生产 app 默认启用真实 adapter、独立音频产物、native-to-processing invocation 或 release readiness。

当前已实现 VS-MA-16 native processing state consumer 边界：

1. `ProcessingCommandClient` 只表达已冻结的 `generate_transcript` 和 `generate_speaker_labels` request/response 模型，失败 `details` 使用 tolerant decode 并只展示摘要。
2. `ProcessingCommandProcessRunner` 是可注入生产桥，只通过 `Process` 调用公开命令名和冻结 flag，解析 stdout JSON；stderr 只作为桥接诊断摘要，不作为产品契约。
3. `ProcessingCommandFakeClient` 只返回 deterministic fake response，并记录请求用于测试断言；不读取 `processing-cli` 内部实现。
4. `ProcessingStateViewModel` 覆盖 idle、blocked、generatingTranscript、generatingSpeakerLabels、completed、degraded、failed，使用 `PermissionDependencyStatusState.canRunProcessing` fail closed，busy 时阻止重复 start，retry 重放上一轮请求。
5. `ProcessingStateView` 暴露 `ma.processing.*` accessibility identifier，覆盖 start、retry、transcript status、speaker label status、success、error、degradation 和 warnings。
6. `MeetingAssistantNativeApp` 的非 XCTest runtime 默认使用 `ProcessingCommandProcessRunner` 调用公开 `generate_transcript` / `generate_speaker_labels` 命令；Debug/XCTest 默认继续通过 deterministic `MA_NATIVE_APP_SMOKE_FIXTURE=processing-*` fake fixture 验证 app-bundle locator 和 processing state，不调用真实 CLI、helper、capture、runtime、provider、网络、下载、真实 pasteboard、真实文件 picker 或文件删除。
7. `MA_NATIVE_PROCESSING_CLIENT=process` 是 Debug/XCTest 测试注入路径，可配合 `MEETING_ASSISTANT_CLI_PATH` 和 `MEETING_ASSISTANT_WORKSPACE` 指向 native-owned `test-fixtures/processing-command-fixture.sh` 与临时 workspace，证明 `ProcessingCommandProcessRunner` stdout JSON 可驱动 completed、transcript-only degradation、failure 和 retry 状态；显式 `MA_NATIVE_APP_REAL_PROCESSING_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh` 则通过 provider-owned `platform/e2e/ma-cli-local.sh` 调用真实 `processing-cli`。`MA_NATIVE_PROCESSING_CLIENT=fake` 只能在 Debug/XCTest fixture 中生效，不能把非 XCTest runtime 降级为 fake。
8. 如果 real-processing app-bundle smoke 在测试 body 前失败并输出 `LocalAuthentication Code=-4` / `System authentication is running` 或 `Timed out while enabling automation mode`，该运行只能作为 macOS UI automation 环境 blocker；常见形态是 `testmanagerd` 启用 XCTest Automation Mode 时被 `loginwindow` / Touch ID / password authentication 会话抢占，或 Automation Mode 初始化在系统认证不可用时超时。需先解除系统认证或 Accessibility/Developer Tools 授权提示，再重跑同一命令，不能记为真实 provider 通过证据。

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
5. `TranscriptActionOSClients.swift` 是唯一允许的 action OS boundary：生产 app copy 在 `export_transcript` 成功返回可复制文本后写入 macOS pasteboard，export 通过 `NSSavePanel` 获取用户确认目标；XCTest/app-bundle smoke 继续注入 memory clipboard 和 deterministic target，避免测试弹系统面板或污染真实 pasteboard。
6. `MeetingAssistantNativeApp` 通过 deterministic `MA_NATIVE_APP_SMOKE_FIXTURE=transcript-action-*` fixture 验证 app-bundle locator 和用户触发状态，不调用真实 CLI、helper、capture、runtime、provider、网络、下载或真实文件删除。

当前目录仍不得实现未受控真实录制、除 `AppleScreenCaptureKitNativeCaptureAdapter.swift` 之外的 ScreenCaptureKit/AVFoundation/CoreAudio capture framework 集成、OBS/BlackHole/FFmpeg 辅助 capture、转写 provider、speaker labeling provider、外部模型调用、公开 `normalize_audio` 命令、直接文件删除或自动依赖下载。VS-MA-14/15 controlled native capture artifact registration 证据只能证明组件内受控 adapter、session/artifact 落盘契约和 fail-closed 路径；Apple ScreenCaptureKit spike 只能证明代码级官方 framework adapter 和 combined recording artifact 表达，不证明真实系统音频能力、真实 macOS 权限负向用例、native-to-processing invocation、真实 runtime/model smoke、release bundle 或发布候选 covered。VS-MA-16 native processing state 证据能证明 native consumer 可通过冻结命令响应、默认 fake fixture、Debug/XCTest process runner fixture 和显式 real-processing app-bundle route 表达处理状态；2026-07-05 real-processing app-bundle smoke 已证明 `.app` UI 可触发 provider-owned `processing-cli` wrapper 并生成 transcript/speaker artifacts，但仍不能证明真实 capture、完整 transcript/export/delete release chain、真实 runtime/model 质量或发布包。VS-MA-17 read-only transcript review 证据只能证明 native UI 可消费确定性 transcript/speaker label fixture 并显示回查状态，不能替代真实 processing runtime。VS-MA-18/VS-MA-19 native action 证据能证明 deterministic native consumer UI、fake/process command boundary、production-injected pasteboard/save-panel OS boundary 和确认/取消状态；仍不证明 production action process bridge、processing provider、真实删除执行或 release bundle。
