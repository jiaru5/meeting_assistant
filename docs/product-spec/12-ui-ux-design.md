# 12. UI/UX 设计

本文件定义 UI/UX、可访问性、交互状态和测试定位契约。页面或本地工具业务范围来自 `04-user-journeys-and-ui.md`。

## UI 状态

Phase 1 控制面已确认为最小 Swift/SwiftUI app + local helper / processing CLI 的组合。图形入口负责原生录制控制和用户可见状态；helper/CLI 负责依赖检查、媒体处理、转写、speaker labeling 和导出。

## UI 原则

1. UI 或本地控制入口必须服务于实际录制、处理和导出工作流，不做营销页。
2. MVP 以清晰状态和可恢复错误为主，避免隐藏权限、依赖或处理失败。
3. 录制中状态必须稳定可见，防止用户不知道是否正在录制。
4. transcript 回查必须强调匿名 speaker labels 不是实名识别。
5. 复制或导出 transcript 到外部 GPT 工具必须是用户主动行为。

## 关键交互契约

| UI ID | 场景 | 规则 | 覆盖能力 | 验证入口 |
|---|---|---|---|---|
| UI-MA-RECORD-001 | 原生录制控制 | 开始、停止、录制中、失败和降级状态必须可区分 | `CAP-MA-002`, `CAP-MA-003` | `PV-MA-002`, `PV-MA-003` |
| UI-MA-PERMISSION-001 | macOS 权限缺失 | 明确显示缺失权限和用户修复路径，不开始对应录制 | `CAP-MA-001` | `PV-MA-001` |
| UI-MA-DEPS-001 | 依赖检查 | 显示缺失依赖、版本、模型路径或不可用能力 | `CAP-MA-005` | `PV-MA-005` |
| UI-MA-PROCESSING-001 | 处理状态 | 显示标准化音频、转写、speaker labeling 的处理中、失败、可重试或完成状态 | `CAP-MA-006`, `CAP-MA-007`, `CAP-MA-008`, `CAP-MA-009` | `PV-MA-006`, `PV-MA-007`, `PV-MA-008`, `PV-MA-009` |
| UI-MA-TRANSCRIPT-001 | transcript 回查 | 显示时间戳、文本和匿名 speaker labels 或 transcript-only 降级原因 | `CAP-MA-010` | `PV-MA-010` |
| UI-MA-EXPORT-001 | transcript 复制/导出 | 明确由用户触发，不自动上传外部服务 | `CAP-MA-011` | `PV-MA-011` |
| UI-MA-FALLBACK-001 | speaker labeling 降级 | 无可用引擎时显示 transcript-only 状态和原因 | `CAP-MA-008` | `PV-MA-008` |
| UI-MA-DELETE-001 | 删除会话 | 删除前显示目标会话和影响范围，要求用户明确确认；删除后显示结果摘要 | `CAP-MA-012` | `PV-MA-012` |

## 页面或本地工具状态要求

每个主要入口至少定义：

1. 就绪。
2. 权限缺失。
3. 依赖缺失。
4. 录制中。
5. 停止/保存中。
6. 处理中。
7. 产物降级。
8. 失败并提供重试指引。
9. transcript 可用。
10. 导出成功/失败。
11. 删除确认/成功/失败。

## 可访问性

如果采用图形 UI：

1. 每个窗口或主视图有唯一主 heading 或可访问标题。
2. 开始/停止录制控件有清晰 accessible name。
3. 图标按钮有 accessible name 或 tooltip。
4. 错误和状态变化对屏幕阅读器可见。
5. 键盘可触发核心操作或有等价菜单命令。

## Locator 规范

如果引入自动化 UI 测试，优先使用用户语义 locator：

1. `getByRole("button", { name })`
2. `getByRole("heading", { name })`
3. `getByText()` 用于稳定状态文案
4. `getByLabelText(name)`

只有无法表达业务语义时，才使用 `data-testid`，并在测试中说明原因。

对于 SwiftUI 原生界面，等价规则是使用可访问标题、button accessible name、label、状态文本和 XCUITest 可查询的 accessibility identifier。accessibility identifier 只能辅助稳定定位，不能替代用户可见或屏幕阅读器可理解的状态表达。

## SwiftUI 和 XCUITest 可测试性

原生 UI 状态必须能被 Swift Testing 和 XCUITest 稳定断言：

1. 每个核心操作控件必须同时具备用户可理解的 accessible name 和稳定 accessibility identifier；identifier 使用 `ma.<surface>.<role>` 形式，例如 `ma.record.startButton`。
2. 每个关键状态必须有稳定可见文案或状态 label，至少覆盖 ready、permission missing、dependency missing、recording、saving、processing、degraded、failed、transcript available、export success/failure 和 delete confirm/success/failure。
3. 状态文案可以随产品语言润色，但同一状态的语义 code、accessible label 和测试 locator 必须稳定；修改时必须同步更新 XCUITest 或 Swift Testing。
4. 权限缺失、依赖缺失、speaker-label transcript-only 降级、导出失败和删除失败不得只通过 transient toast 表达；必须有测试可查询的持久状态或结果区域。
5. 时间、路径和会话标题在 UI 测试中必须可注入 fixture 或稳定格式；测试不得依赖当前真实时间、用户主目录绝对路径或本机已有会议数据。
6. 删除确认 UI 必须在可访问文本中包含目标会话标识或标题和影响范围，并提供可测试的 confirm 与 cancel 控件。
