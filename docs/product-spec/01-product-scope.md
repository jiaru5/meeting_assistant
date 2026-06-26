# 1. 产品范围

本文件定义产品范围、目标、非目标、用户角色和核心场景。它不定义字段、权限、命令、文件格式或 UI 细节。

## 产品一句话

`meeting_assistant` 是一个本地 macOS 会议助手，面向个人自用的第一阶段，优先通过原生 macOS 录制能力记录线上会议或现场讨论，并产出可回查的视频、系统音频、麦克风音频、混合音频、转写文本和 best-effort 匿名说话人标签；后续可扩展给少量团队内部成员使用。

## 阶段边界

| 阶段 | 范围 | 说明 |
|---|---|---|
| Phase 1 MVP | 个人自用、本地 macOS、Apple Silicon、原生 macOS 录制优先、文件化产物流水线、音频转写、best-effort 匿名 speaker labels | 当前 adoption 目标 |
| 后续团队内部使用 | 少量团队内部成员使用 | 需要后续确认安装、共享、权限、审计和数据隔离 |
| 未来原生产品化 | 更完整桌面 UI、签名、公证、自动更新、团队协作、自动纪要 | 不属于 MVP 必需能力 |

## 目标

| ID | 目标 | 成功标准 | 验证入口 |
|---|---|---|---|
| GOAL-MA-001 | 本地记录线上会议或现场讨论 | 用户能在 Apple Silicon Mac 上启动一次原生录制，并得到会议视频和音频产物 | `AC-MA-001`, `PV-MA-001` |
| GOAL-MA-002 | 保留可重处理的会议媒体产物 | 每次会议会话保存系统音频、麦克风音频、混合音频和屏幕视频；无法获得某一音轨时必须记录能力状态和降级原因 | `AC-MA-002`, `PV-MA-002` |
| GOAL-MA-003 | 从会议音频生成可回查 transcript | 用户能从混合音频或可用音轨生成带时间戳的文本转写结果 | `AC-MA-003`, `PV-MA-003` |
| GOAL-MA-004 | 提供 best-effort 匿名 speaker labels | MVP 以 `SPEAKER_01` 这类匿名标签区分发言段落，不承诺真实姓名或完全准确率 | `AC-MA-004`, `PV-MA-004` |
| GOAL-MA-005 | 保持模块解耦和可替换流水线 | 录制、媒体处理、转写、speaker labeling 和后续纪要生成通过文件和元数据衔接 | `AC-MA-005`, `PV-MA-005` |

## 非目标

| ID | 非目标 | 原因 | 重新纳入范围的条件 |
|---|---|---|---|
| NOGOAL-MA-001 | MVP 不做团队账号、组织空间、多人协作或共享会议库 | Phase 1 已确认是个人自用；团队内部使用是后续范围 | 用户确认团队使用模型、数据隔离和权限要求 |
| NOGOAL-MA-002 | MVP 不做闭源商业化分发、App Store 分发、签名、公证或自动更新 | 当前目标是先验证本地能力和文件化流水线 | 用户确认分发渠道、许可证策略和安装体验要求 |
| NOGOAL-MA-003 | MVP 不要求自动生成完整会议纪要 | 用户确认可手动复制 transcript 到 GPT；纪要生成是可选后续能力 | 用户确认本地 LLM 或外部模型集成边界和质量标准 |
| NOGOAL-MA-004 | MVP 不承诺识别真实发言人姓名 | 在线会议音频可能已被混音，且没有确认声纹、参会人身份或平台数据来源 | 用户确认实名识别数据来源、授权和准确率要求 |
| NOGOAL-MA-005 | MVP 不以 OBS/BlackHole 作为主录制路径 | 用户已选择原生 macOS 录制优先 | 原生录制被验证不可行，或用户明确改回辅助工具录制 |
| NOGOAL-MA-006 | MVP 不由应用自动调用 GPT 或其他云端模型 API | 目前只确认用户可以主动复制 transcript 到外部工具 | 用户确认云/API 集成、密钥管理、隐私告知和合规要求 |

## 用户角色

本表只描述产品视角的用户类型，不定义系统权限。权限以 `03-permissions-and-identity.md` 为准。

| 角色 ID | 名称 | 目标 | 关键使用场景 |
|---|---|---|---|
| ROLE-MA-LOCAL-USER | 本地会议记录用户 | 在自己的 Mac 上记录会议、转写、回查和导出 transcript | 录制线上会议、录制现场讨论、处理录制产物、复制 transcript |
| ROLE-MA-FUTURE-INTERNAL-USER | 后续团队内部用户 | 在团队内部小范围复用本地会议助手 | 后续需要确认安装、共享、权限、审计和数据留存 |

## 核心场景

| 场景 ID | 场景 | 参与角色 | 成功结果 | 失败或异常场景 |
|---|---|---|---|---|
| SCN-MA-001 | 原生录制线上会议 | `ROLE-MA-LOCAL-USER` | 保存屏幕视频、系统音频、麦克风音频、混合音频和会话元数据 | 屏幕录制权限缺失、音频权限缺失、无法捕获某一音轨、磁盘空间不足、录制中断 |
| SCN-MA-002 | 原生录制现场讨论 | `ROLE-MA-LOCAL-USER` | 保存麦克风音频、混合音频和会话元数据；如录制屏幕则保存视频 | 麦克风权限缺失、环境噪音过高、录制中断 |
| SCN-MA-003 | 转写会议音频 | `ROLE-MA-LOCAL-USER` | 从可用音频产物生成带时间戳 transcript | 模型缺失、依赖检查失败、音频格式不可处理、转写失败 |
| SCN-MA-004 | 匿名 speaker labeling | `ROLE-MA-LOCAL-USER` | transcript 段落可以带 best-effort 匿名 speaker labels | 混音、重叠说话或噪音导致标签不稳定；必须保留原 transcript |
| SCN-MA-005 | 手动复制 transcript 到外部 GPT 工具 | `ROLE-MA-LOCAL-USER` | 用户主动复制或导出 transcript 后，在外部工具中整理会议纪要 | 外部工具不属于本系统控制范围；应用不自动上传会议内容 |

## 范围边界

1. 系统边界：本系统负责本地录制编排、产物保存、媒体处理、转写、匿名 speaker labels、元数据维护和 transcript 导出。
2. 外部系统边界：GPT 或其他外部工具仅作为用户手动复制后的外部处理环境；MVP 应用本身不自动调用外部模型 API。
3. 数据所有权：本系统拥有本地会话元数据、媒体文件、transcript、speaker labels 和处理日志；会议软件本身的参会人、聊天、日程和账号信息不属于本系统。
4. 合规边界：Phase 1 是个人本地工具；后续团队使用前必须重新确认数据分类、保留、删除、安装、共享、权限和审计。

## 术语表

| 术语 | 定义 | 主责分卷 |
|---|---|---|
| Meeting Session | 一次会议或讨论的本地记录单位，包含录制、媒体、转写和处理状态 | `02-domain-model.md` |
| Recording Artifact | 一次会话产生的视频、音频、transcript、speaker labels 或元数据文件 | `02-domain-model.md`, `07-data-and-events.md` |
| Mixed Audio | 合并系统音频和麦克风音频后用于回听或转写的音频产物 | `02-domain-model.md`, `05-business-rules-and-calculations.md` |
| Anonymous Speaker Label | 不代表真实身份的说话人标签，例如 `SPEAKER_01` | `05-business-rules-and-calculations.md` |
| Native macOS Recording | 以 macOS 原生能力为第一阶段主录制路径，具体技术边界见 `08-implementation-guidance.md` 和 `11-adr.md` | `08-implementation-guidance.md` |
