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
7. 持久 `MeetingAssistantNative.xcodeproj` 提供最小 macOS app bundle target 和 app-bundle XCUITest target；`AppBundleLocatorSmokeTests` 使用 `XCUIApplication()` 启动 `.app`，通过 deterministic launch fixture 覆盖默认 blocked readiness、ready fake start/stop、start failure error locator，且不调用真实 helper/CLI/capture/runtime。

当前已实现 VS-MA-17 read-only transcript review consumer 边界：

1. `TranscriptReviewReadModel` 只读取 `transcript.json` 的 `id`、`session_id`、`source_artifact_id`、`status`、`segments[]`、`segment_id`、`start_ms`、`end_ms`、`text`、可选 `speaker_label`，以及 `speaker_labels.json` 的 `session_id`、`labels`、`segment_mapping`。
2. `TranscriptReviewViewModel` 输出稳定可见状态：heading、summary、timestamp label、transcript text、匿名 speaker label、transcript-only degradation reason、missing transcript 和 empty transcript。
3. `TranscriptReviewView` 暴露 `ma.transcript.*` accessibility identifier，供 Swift Testing 和 XCUITest 稳定断言。
4. `MeetingAssistantNativeApp` 通过 deterministic `MA_NATIVE_APP_SMOKE_FIXTURE=transcript-review|transcript-empty` fixture 验证 app-bundle locator，不调用真实 CLI、helper、capture、runtime、provider、网络或下载。

当前目录仍不得实现真实录制、屏幕捕获、系统音频捕获、麦克风捕获、转写、speaker labeling、外部模型调用、公开 `normalize_audio` 命令、复制/导出 transcript、删除会话或自动依赖下载。VS-MA-13 fake recording 和 app-bundle locator smoke 证据只能用于 `PV-MA-001`、`PV-MA-002`、`PV-MA-005` 的 partial 状态，不能替代 VS-MA-14 的真实 native capture、真实 macOS 权限负向用例或真实 runtime/model smoke。VS-MA-17 read-only transcript review 证据只能证明 native UI 可消费确定性 transcript/speaker label fixture 并显示回查状态，不能替代真实 processing runtime、copy/export 或 delete_session 证据。
