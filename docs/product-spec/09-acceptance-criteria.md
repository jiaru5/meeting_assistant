# 9. 验收标准

本文件定义产品验收标准。验证覆盖状态由 `docs/engineering/06-product-validation-matrix.md` 维护。

## 完成定义

一个产品行为只有同时满足以下条件，才能视为完成：

1. 对应事实源已更新或确认不需要更新。
2. 对应验收标准存在。
3. 验证矩阵有对应行。
4. 关键路径有自动化验证，状态达到 `covered`。
5. 本地依赖、模型和权限检查必须可重复执行，不能在缺失依赖时报告成功。
6. 交付说明记录实际运行的命令和结果。

## MVP 验收标准

| AC ID | 场景 | 前置条件 | 操作 | 期望结果 | 验证矩阵 |
|---|---|---|---|---|---|
| AC-MA-001 | 原生录制创建会议会话 | Apple Silicon Mac，macOS 26.5.1，录屏/麦克风/文件权限满足或可检测 | 用户通过最小 Swift/SwiftUI app 启动原生录制并停止 | 生成 `MeetingSession`、`screen_video`、音频 artifact 登记和会话元数据；缺失权限时明确失败 | `PV-MA-001` |
| AC-MA-002 | 三类音频产物和降级记录 | 原生录制完成 | 系统登记媒体产物 | `system_audio`、`microphone_audio`、`mixed_audio` 均成功登记；无法生成的产物必须有 `capture_status` 和 `degradation_reason`；处理输入可派生 `normalized_audio` | `PV-MA-002` |
| AC-MA-003 | 生成带时间戳 transcript | 可用 `mixed_audio`、`normalized_audio` 或用户选择的音频 artifact，transcription adapter 可用 | 用户运行转写 | 生成按时间排序的 transcript segments，每段包含 `start_ms`、`end_ms` 和文本 | `PV-MA-003` |
| AC-MA-004 | best-effort 匿名 speaker labels | transcript 已生成，speaker labeling 依赖可用或明确不可用 | 用户运行 speaker labeling | 可用时为 segments 添加匿名 labels；不可用或失败时降级 transcript-only 并记录原因；不得声称真实身份 | `PV-MA-004` |
| AC-MA-005 | 文件化流水线可重试 | 已有会话和原始媒体 | 用户重新运行转写、speaker labeling 或导出 | 派生产物可重新生成，原始视频和音频不被覆盖 | `PV-MA-005` |
| AC-MA-006 | bootstrap/check 依赖检查 | 新环境或依赖变化 | 用户运行依赖检查 | 输出 macOS/架构、工具链、媒体工具、transcription adapter/runtime、speaker labeling runtime、workspace、权限状态和允许来源提示；不自动下载依赖 | `PV-MA-006` |
| AC-MA-007 | 用户手动导出 transcript | transcript 已生成 | 用户复制或导出 transcript | 产出 text/Markdown/JSON 中至少一种格式；应用不自动上传到 GPT 或外部 API | `PV-MA-007` |

## 高风险验收维度

1. macOS 权限：录屏、麦克风和文件访问缺失时必须 fail closed。
2. 录制产物：视频和三类音频 artifact 必须可登记，缺失时必须可解释。
3. 本地依赖：FFmpeg 或兼容媒体能力、转写 runtime、speaker labeling runtime 缺失时必须可检测。
4. 数据保护：原始媒体不得被转写、speaker labeling 或导出覆盖。
5. 外部工具边界：GPT 仅是用户手动复制后的外部行为，应用不自动上传会议内容。
6. Apple Silicon + macOS 26.5.1：MVP 验收环境以当前确认平台为准。
7. 组件边界：activation 前允许的骨架只能验证命令和契约，不实现真实业务行为。

## 发布前验收

发布候选必须满足：

1. `10-open-decisions.md` 没有阻塞发布的问题。
2. 验证矩阵中发布范围内所有 `PV-MA-*` 行为 `covered`。
3. `./scripts/release-preflight.sh` 通过。
4. 依赖许可证、签名/公证、数据保留、删除、备份恢复和事故响应完成审查。
