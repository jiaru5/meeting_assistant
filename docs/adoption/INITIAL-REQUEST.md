# 初始项目请求

> Adoption 工作区文档。本文件记录原始初始意向，不是产品事实源。

## 项目意向

- [confirmed] 项目初始想法：在 Mac 上做一个本地会议纪要软件，用于录制会议、提取音频文本，并可选生成会议纪要。
- [confirmed] 目标平台：macOS。
- [confirmed] 核心用户需要：录制线上会议或现场讨论，并在会后得到可回查的视频、音频、转写文本和可选会议纪要。
- [confirmed] 线上会议场景包括：钉钉、腾讯会议、Zoom 这类在线会议工具。
- [confirmed] 现场讨论场景包括：使用 Mac 麦克风收音的现场讨论音频录制。
- [confirmed] 屏幕录制需求包括：全屏录制，或指定到会议软件窗口，录制完整的屏幕共享视频。
- [confirmed] 音频录制需求包括：Mac 系统音频录制，以及 Mac 麦克风录音。
- [confirmed] 期望产出包括：会议视频、音频、面向音频的文本内容提取。
- [confirmed] 会议纪要生成是可选需求；如果有完整文本，用户可以手动复制到 GPT 中整理。
- [confirmed] 如果可行，希望区分不同发言人员。
- [confirmed] 技术选型要求：使用开源、免费的服务或工具。
- [confirmed] 用户此前做过 YouTube 视频音频提取，使用过本地 Whisper。
- [confirmed] 用户此前做过字幕翻译，使用过本地 Qwen2.5-14B-Instruct-4bit 模型。
- [confirmed] 用户认可模块解耦、分步骤开发的思路，不希望一开始做一个大而全的产品。
- [preference] 当前倾向：先实现可用的本地录制、媒体处理、转写流水线，再逐步增加说话人区分、会议纪要生成、桌面 UI 和原生录制能力。
- [preference] 当前倾向：通过文件和元数据解耦模块，避免录制、转写、纪要、UI 强耦合。
- [preference] 当前倾向：第一阶段可以优先使用成熟开源工具组合验证链路，而不是直接开发完整原生 Mac App。
- [hypothesis] 可能的开发路线：先做 CLI 或轻量本地工具，再做桌面 UI。
- [hypothesis] 可能的录制方案：OBS Studio + BlackHole + FFmpeg 作为早期 MVP 技术组合。
- [hypothesis] 可能的后续原生录制方案：Swift/SwiftUI + ScreenCaptureKit。
- [hypothesis] 可能的转写方案：复用本地 Whisper，或使用 whisper.cpp。
- [hypothesis] 可能的说话人区分方案：WhisperX 或 pyannote.audio。
- [hypothesis] 可能的纪要生成方案：复用本地 Qwen2.5-14B-Instruct-4bit。
- [open] 是否要面向个人自用、团队内部使用、还是可分发产品：unknown。
- [open] 是否需要商业化、闭源分发、App Store 分发或企业内部分发：unknown。
- [open] 是否要求完全离线运行：open。
- [open] 是否允许用户手动安装 OBS、BlackHole、FFmpeg、Whisper 模型、Qwen 模型等外部依赖：open。
- [open] 是否必须支持 Intel Mac：open。
- [open] 最低 macOS 版本：unknown。
- [open] 目标会议时长、最大会议时长、并发会议数量：unknown。
- [open] 转写准确率目标、说话人区分准确率目标、纪要质量标准：unknown。
- [open] 是否需要企业级安全、审计、权限隔离、数据保留策略、合规认证、SLO、RTO/RPO：open。

## 已知材料

| 材料 | 位置或链接 | 可靠性 | 备注 |
|---|---|---|---|
| 用户初始需求 | 当前对话中的原始描述 | confirmed | 原始输入，包含 Mac 会议纪要软件、屏幕录制、音频录制、转写、纪要、说话人区分、开源免费要求 |
| 用户补充方向 | 当前对话中的后续确认 | confirmed | 用户认可模块解耦和分步骤开发，不希望一次做大而全 |
| 已整理的产品需求与技术方案草稿 | `/Users/jerry/Documents/Codex/2026-06-26/mac-a-mac-zoom-b-mac/outputs/会议纪要软件产品需求与技术方案.md` | draft | 这是讨论沉淀出的建议稿，不是正式产品事实源 |
| 用户已有本地 Whisper 使用经验 | 当前对话中的口头/文本来源 | confirmed | 具体脚本、模型版本、运行方式 unknown |
| 用户已有本地 Qwen2.5-14B-Instruct-4bit 使用经验 | 当前对话中的口头/文本来源 | confirmed | 具体推理框架、量化格式、上下文长度、硬件性能 unknown |
| OBS Studio | 建议技术方案 | hypothesis | 免费开源录制工具，当前只是建议，不是最终决策 |
| BlackHole | 建议技术方案 | hypothesis | 免费开源 macOS 虚拟音频设备，当前只是建议，不是最终决策 |
| FFmpeg | 建议技术方案 | hypothesis | 免费开源媒体处理工具，当前只是建议，不是最终决策 |
| whisper.cpp | 建议技术方案 | hypothesis | 可作为本地 Whisper 推理实现，当前只是建议，不是最终决策 |
| WhisperX / pyannote.audio | 建议技术方案 | hypothesis | 可用于说话人区分，准确率和许可/模型获取方式需要后续验证 |
| ScreenCaptureKit | 后续原生方案候选 | hypothesis | macOS 系统 API，不是开源工具；是否采用 open |

## 已知约束

| 领域 | 约束 | 来源 | 是否已确认 |
|---|---|---|---|
| 平台 | 目标平台是 Mac/macOS | 初始需求 | yes |
| 录制 | 需要支持全屏录制或指定会议软件窗口录制 | 初始需求 | yes |
| 录制 | 需要录制完整屏幕共享视频 | 初始需求 | yes |
| 音频 | 需要支持线上会议系统音频录制 | 初始需求 | yes |
| 音频 | 需要支持 Mac 麦克风收音的现场讨论录制 | 初始需求 | yes |
| 输出 | 需要输出会议视频和音频 | 初始需求 | yes |
| 输出 | 需要从音频提取文本内容 | 初始需求 | yes |
| 输出 | 会议纪要整理是可选需求 | 初始需求 | yes |
| 输出 | 如果可行，希望区分不同发言人员 | 初始需求 | yes |
| 技术 | 工具和依赖应使用开源、免费服务或工具 | 初始需求 | yes |
| AI Runtime | 用户已有本地 Whisper 使用基础 | 初始需求 | yes |
| AI Runtime | 用户已有本地 Qwen2.5-14B-Instruct-4bit 使用基础 | 初始需求 | yes |
| 产品方式 | 应模块解耦并分步骤开发 | 用户补充 | yes |
| 产品方式 | 不应一开始做大而全产品 | 用户补充 | yes |
| 许可证 | OBS、BlackHole、FFmpeg 等候选工具存在 GPL/LGPL 等许可证风险 | 技术分析 | open |
| 许可证 | 如果未来闭源或商业分发，需要重新确认依赖许可证合规 | 技术分析 | open |
| 隐私 | 会议音视频和转写文本可能包含敏感信息 | 按领域推断 | open |
| 隐私 | 是否必须完全本地离线处理 | 按 local-first 偏好推断 | open |
| 安全 | 是否需要用户权限体系、数据隔离、访问审计 | 企业级关注点 | open |
| 合规 | 是否需要满足企业合规、数据保留、删除、审计要求 | 企业级关注点 | open |
| 生产 | 是否需要生产级部署、SLO、监控、告警 | 企业级关注点 | open |
| 韧性 | 是否需要定义 RTO/RPO | 企业级关注点 | open |
| 性能 | 目标会议时长和处理时延要求未知 | 缺少上下文 | open |
| 兼容性 | 最低 macOS 版本未知 | 缺少上下文 | open |
| 硬件 | 目标 Mac 型号、内存、芯片、可用 GPU/Metal 能力未知 | 缺少上下文 | open |
| UX | 第一版是否需要 GUI 未最终确认 | 讨论 | open |
| 分发 | 是否需要安装包、自动更新、签名、公证、App Store 发布未知 | 缺少上下文 | open |

## 明确非目标

| 非目标 | 原因 | 是否已确认 |
|---|---|---|
| 第一版不做大而全的一体化产品 | 用户明确认可模块解耦、分步骤开发 | yes |
| 第一版不把会议纪要生成作为硬性必需能力 | 用户说明如果已有完整文本，可以手动复制到 GPT 整理 | yes |
| 第一版不承诺自动识别真实发言人姓名 | 当前只提出“如果可以，希望区分不同发言人员”；真实身份识别需要额外声纹、参会人数据或平台信息 | open |
| 第一版不承诺说话人区分完全准确 | 线上会议远端音频通常已被会议软件混音，抢话和噪声会影响 diarization | open |
| 不使用付费云服务作为核心依赖 | 用户要求开源、免费服务或工具 | yes |
| 不把建议技术方案写成最终技术决策 | 当前方案仍处在初始需求和技术探索阶段 | yes |
| 不把本文件作为正式 product-spec 或产品事实源 | 文件说明要求这是原始初始意向 | yes |
| 不删除或忽略企业级安全、权限、数据隔离、生产要求、SLO、RTO/RPO、合规问题 | 用户明确要求保留这些问题 | yes |

## 开放上下文

- [confirmed] 本文件是 adoption workspace 的原始输入记录，不是正式产品事实源。
- [confirmed] 当前已知需求来自对话，不应被视为完整 PRD。
- [confirmed] 技术方向必须坚持开源免费，但具体依赖尚未最终决策。
- [preference] 当前倾向是本地优先，尽量避免云端处理会议内容。
- [preference] 当前倾向是先打通端到端流水线，再产品化 UI。
- [preference] 当前倾向是复用用户已有 Whisper 和 Qwen 本地能力。
- [hypothesis] OBS + BlackHole + FFmpeg 可以作为早期 MVP 录制与媒体处理组合。
- [hypothesis] whisper.cpp 可能比原始 Whisper 更适合长期本地工具化集成。
- [hypothesis] WhisperX 或 pyannote.audio 可用于说话人区分，但需要验证模型下载、许可证、准确率和本地运行成本。
- [hypothesis] Swift + ScreenCaptureKit 可作为后续 Mac 原生录制引擎，但开发成本高，且 ScreenCaptureKit 不是开源依赖。
- [open] 是否允许系统依赖通过 Homebrew 安装：unknown。
- [open] 是否允许用户安装虚拟音频驱动 BlackHole：unknown。
- [open] 是否要求应用自动配置系统音频路由：unknown。
- [open] 是否需要在录制时同时让用户正常听到会议声音：open。
- [open] 是否要求分别保存系统音频轨、麦克风轨和混合音频轨：preference，但未正式确认。
- [open] 是否需要支持只导入已有录屏/录音并处理：hypothesis，未正式确认。
- [open] 是否需要支持中英文混合会议：unknown。
- [open] 是否需要支持英文会议或其他语言会议：unknown。
- [open] 是否需要字幕文件输出格式，如 SRT、VTT：preference，未正式确认。
- [open] 是否需要时间戳级别回查能力：preference，未正式确认。
- [open] 是否需要在纪要中引用原始发言时间戳：preference，未正式确认。
- [open] 是否需要多人协作、共享会议纪要、云同步：unknown。
- [open] 是否需要项目级权限、用户登录、组织空间：unknown。
- [open] 是否需要数据加密、密钥管理、本地数据库加密：open。
- [open] 是否需要安全删除、数据留存期限、导出审计：open。
- [open] 是否需要防止会议数据被第三方模型或服务读取：open。
- [open] 是否需要企业环境下的 MDM、设备权限、合规安装方案：open。
- [open] 是否需要生产级可用性指标 SLO：open。
- [open] 是否需要 RTO/RPO：open。
- [open] 是否需要错误恢复策略，例如录制中断、转写失败、模型崩溃后的恢复：open。
- [open] 是否需要处理超长会议，例如 2-4 小时以上：unknown。
- [open] 是否需要后台任务队列、任务暂停/继续、断点续跑：preference，未正式确认。
- [open] 是否需要 App 签名、公证、自动更新：unknown。
- [open] 是否有目标发布日期、预算、人力、维护周期：unknown。
- [open] 是否需要正式竞品分析、定价、商业目标：unknown。
