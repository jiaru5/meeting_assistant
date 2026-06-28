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

当前目录仍不得实现真实录制、屏幕捕获、系统音频捕获、麦克风捕获、转写、speaker labeling、外部模型调用、公开 `normalize_audio` 命令或自动依赖下载。VS-MA-13 fake recording 证据只能用于 `PV-MA-002` 的 partial 状态，不能替代 VS-MA-14 的真实 native capture。
