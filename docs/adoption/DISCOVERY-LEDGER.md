# Discovery 记录

> Adoption 工作区文档。本文件记录 discovery 状态，不是产品事实源。

## 当前 Discovery 轮次

| 字段 | 值 |
|---|---|
| 轮次 | 4 |
| Subphase | spec-review |
| 日期 | 2026-06-26 |
| 目标 | 补齐 activation-time 非业务骨架、manifest、工程门禁和 readiness，不实现业务代码 |
| 是否阻塞 | yes |

## Spec 转写完成审计

| 项 | 当前判断 | 说明 |
|---|---|---|
| Durable product-spec | complete for confirmed MVP facts | `01-product-scope.md` 到 `13-security-and-compliance.md` 已替换为 Meeting Assistant 项目事实；阻塞性 open decisions 已关闭。 |
| Engineering spec | complete for confirmed MVP facts | 多 agent 工作流、planned component commands、validation matrix、dependency policy 和 agent-policy 边界已记录。 |
| 未确认假设 | non-blocking | 具体 capture API、具体 transcription/diarization runtime、未来团队分发和自动纪要仍需后续 spec-change，但不阻塞当前 spec 转写完成。 |
| Activation 准备 | engineering ready; sign-off pending | 用户批准继续推进 adoption 后，非业务 skeleton、manifest components、full-stack/E2E smoke 计划和工程门禁已补齐；仍等待用户审查完整持久 spec 并显式批准 activation。 |
| 用户确认 | pending | 用户尚未审查完整持久 spec，也未批准 project activation。 |

## 已确认事实

只添加用户明确确认的事实，或从已批准来源验证过的事实。这些事实在转写到持久事实源前，不能作为实现依据。

| ID | 事实 | 来源 | 目标 product-spec 分卷 | 是否已转写 |
|---|---|---|---|---|
| CF-001 | 项目名称是 `meeting_assistant`。 | 用户确认，2026-06-26 | `docs/product-spec/01-product-scope.md` | yes |
| CF-002 | 项目 owner 是 `JeRRy`。 | 用户确认，2026-06-26 | `harness/project-manifest.json` | 部分转写：仅项目 metadata |
| CF-003 | 目标产品是本地 macOS 会议纪要工具，用于录制会议、提取音频文本，并可选生成会议纪要。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/01-product-scope.md` | yes |
| CF-004 | 目标平台是 macOS。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/08-implementation-guidance.md` | yes |
| CF-005 | 核心用户需要是录制线上会议或现场讨论，并在会后回查视频、音频、transcript 文本和可选纪要。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/01-product-scope.md`, `docs/product-spec/04-user-journeys-and-ui.md` | yes |
| CF-006 | 线上会议示例包括钉钉、腾讯会议和 Zoom。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/01-product-scope.md` | yes |
| CF-007 | 现场讨论录制应使用 Mac 麦克风。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/07-data-and-events.md` | yes |
| CF-008 | 屏幕录制应支持全屏或指定会议 app 窗口，并包含完整屏幕共享视频。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/08-implementation-guidance.md` | yes |
| CF-009 | 音频录制应包含 Mac 系统音频和 Mac 麦克风音频。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/07-data-and-events.md`, `docs/product-spec/08-implementation-guidance.md` | yes |
| CF-010 | 期望产出包括会议视频、音频和从音频提取的文本。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md` | yes |
| CF-011 | 会议纪要生成是可选项；如果已有完整 transcript，用户可以手动复制到 GPT 做摘要。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/01-product-scope.md`, `docs/product-spec/13-security-and-compliance.md` | yes |
| CF-012 | 如果可行，希望区分说话人。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/09-acceptance-criteria.md` | yes |
| CF-013 | 工具和服务应开源且免费。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/13-security-and-compliance.md` | partial |
| CF-014 | 用户有使用本地 Whisper 做 YouTube 音频提取的经验。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/08-implementation-guidance.md` | partial |
| CF-015 | 用户有使用本地 `Qwen2.5-14B-Instruct-4bit` 模型做字幕翻译的经验。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/08-implementation-guidance.md` | partial |
| CF-016 | 项目应模块化并分步骤开发，不应从一开始做成大型一体化产品。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/01-product-scope.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/11-adr.md` | yes |
| CF-017 | 第一阶段方向是先打通可用的本地录制、媒体处理和转写流水线，再扩展说话人区分、会议纪要生成、桌面 UI 和原生录制能力。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/01-product-scope.md`, `docs/product-spec/08-implementation-guidance.md` | yes |
| CF-018 | 偏好通过文件和元数据做模块解耦，避免录制、转写、纪要和 UI 强耦合。 | `docs/adoption/INITIAL-REQUEST.md` | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/11-adr.md` | yes |
| CF-019 | Phase 1 是个人自用；后续可能扩展给少量团队内部成员使用。 | 用户回答 Q-101，2026-06-26 | `docs/product-spec/01-product-scope.md`, `docs/product-spec/13-security-and-compliance.md` | yes |
| CF-020 | 允许用户手动复制 transcript 文本到 GPT 或其他外部服务。 | 用户回答 Q-103，2026-06-26 | `docs/product-spec/13-security-and-compliance.md`, `docs/product-spec/06-api-contracts.md` | yes |
| CF-021 | 会议音频产物应包含系统音频、麦克风音频和混合音频。 | 用户回答 Q-105，2026-06-26 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/05-business-rules-and-calculations.md` | yes |
| CF-022 | MVP 硬件只需要支持 Apple Silicon Mac；MVP 不要求 Intel Mac 支持。 | 用户回答 Q-106，2026-06-26 | `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/09-acceptance-criteria.md` | yes |
| CF-023 | MVP 说话人区分应采用 best-effort 匿名 speaker labels；MVP 不要求命名 speaker identity。 | 用户回答 Q-107，2026-06-26 | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/09-acceptance-criteria.md` | yes |
| CF-024 | 第一条可验证纵切应优先原生 macOS 录制，而不是 OBS/BlackHole 辅助录制。 | 用户回答 Q-102，2026-06-26 | `docs/product-spec/01-product-scope.md`, `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/11-adr.md` | yes |
| CF-025 | Phase 1 应使用 bootstrap/check 脚本检查外部依赖和本地前置条件。 | 用户回答 Q-104，2026-06-26 | `docs/product-spec/08-implementation-guidance.md`, `docs/engineering/02-dev-commands.md`, `harness/project-manifest.json` | yes |
| CF-026 | MVP 最低平台应采用当前宿主平台：Apple Silicon (`arm64`) 和 macOS 26.5.1。 | 用户回答 Q-106b 和本地 `sw_vers`，2026-06-26 | `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/09-acceptance-criteria.md`, `harness/project-manifest.json` | yes |
| CF-027 | 原生录制应采用最小 Swift/SwiftUI app + helper 结构；activation-time 骨架必须只包含非业务内容。 | 用户接受 Q-201 推荐，2026-06-26 | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/08-implementation-guidance.md`, `harness/project-manifest.json` | yes |
| CF-028 | MVP 媒体处理应保留原始录制格式，并为下游处理创建标准化派生音频产物。 | 用户接受 Q-202 推荐，2026-06-26 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/09-acceptance-criteria.md` | yes |
| CF-029 | 转写 runtime 应先通过 adapter 和 dependency-check 契约隔离，再锁定具体 runtime；现有本地 Whisper 仍是候选 adapter。 | 用户接受 Q-203 推荐，2026-06-26 | `docs/product-spec/06-api-contracts.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/engineering/06-product-validation-matrix.md` | yes |
| CF-030 | Best-effort speaker labeling 在没有可用本地引擎时可以降级为 transcript-only，且必须记录降级原因。 | 用户接受 Q-204 推荐，2026-06-26 | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/09-acceptance-criteria.md` | yes |
| CF-031 | 个人 MVP workspace 默认应是用户本地明文目录；删除会话应删除其 artifacts；加密是后续增强。 | 用户接受 Q-205 推荐，2026-06-26 | `docs/product-spec/07-data-and-events.md`, `docs/product-spec/13-security-and-compliance.md` | yes |
| CF-032 | Activation-time 非业务骨架计划应包含 native app skeleton 和 processing/dependency-check CLI skeleton。 | 用户接受 Q-206 推荐，2026-06-26 | `harness/project-manifest.json`, `docs/engineering/06-product-validation-matrix.md`, `docs/engineering/02-dev-commands.md` | yes |
| CF-033 | 依赖和 agent-policy 审查应先列出允许来源并要求人工安装；自动下载不属于初始策略。 | 用户接受 Q-207 推荐，2026-06-26 | `docs/product-spec/13-security-and-compliance.md`, `docs/engineering/10-security-and-supply-chain.md`, `harness/agent-policy.json` | yes |
| CF-034 | Adoption/spec 转写阶段统一使用 PM / Spec Owner + Discovery / Spec Draft Worker + read-only Governance Reviewer，并按需启用 Specialist。 | 用户确认，2026-06-26 | `docs/engineering/05-agent-operating-model.md` | yes |
| CF-035 | 项目的持久 Markdown spec 已中文化；后续 agent 维护 `docs/product-spec/`、`docs/engineering/` 和 `docs/adoption/` 时默认使用中文，稳定技术标识保留英文或原文。 | 用户确认，2026-06-26 | `docs/engineering/05-agent-operating-model.md` | yes |
| CF-036 | 用户批准基于 adoption 完成计划继续推进，允许创建 activation-time 非业务 skeleton、manifest/E2E smoke 接线和工程门禁；仍未批准运行 `activate-project`。 | 用户确认，2026-06-26 | `harness/project-manifest.json`, `docs/engineering/02-dev-commands.md`, `docs/engineering/06-product-validation-matrix.md`, `docs/adoption/SPEC-READINESS.md` | yes |

## 假设

假设只用于规划辅助。未经确认并转写前，不能据此实现。

| ID | 假设 | 为什么看起来合理 | 如果错误的风险 | 确认问题 | 状态 |
|---|---|---|---|---|---|
| AS-001 | 第一版实现入口可以先是 CLI 或轻量本地工具，再做桌面 UI。 | 初始需求偏好分阶段开发，并优先使用成熟工具。 | 如果 UI 期望不同，会改变组件结构、验收标准和 manifest。 | Q-201 | superseded by CF-027 and CF-032 |
| AS-002 | OBS Studio 和 BlackHole 不再是 Phase 1 主 capture 依赖。 | Q-102 选择了原生 macOS 录制优先。 | 如果原生 capture 不可行，它们仍可能作为 fallback。 | 后续 fallback 决策 | superseded |
| AS-003 | 原生 macOS 录制是 Phase 1 主 capture 路线；具体 API 和 UI 形态仍未关闭。 | Q-102 选择了选项 C。 | API 或权限限制可能阻塞系统音频和音轨分离。 | 后续实现/API 决策 | confirmed direction |
| AS-004 | 本地 Whisper 或 whisper.cpp 可作为首个转写引擎。 | 用户有本地 Whisper 经验，whisper.cpp 也在候选列表中。 | 模型大小、语言支持、性能或准确率可能达不到验收阈值。 | Q-203 | partially resolved by CF-029; concrete runtime still unconfirmed |
| AS-005 | Best-effort 匿名 speaker labels 可能需要 WhisperX 或 pyannote.audio，但具体 diarization 引擎尚未确认。 | Q-107 确认 MVP 需要 best-effort 匿名 speaker labels。 | 工具许可证、模型获取和本地运行成本如果没有边界，可能成为 MVP blocker。 | Q-204 | partially resolved by CF-030; concrete engine and threshold still unconfirmed |
| AS-006 | 本地 Qwen 后续可复用于可选会议纪要生成。 | 用户有本地 Qwen 经验，且纪要生成是可选项。 | 摘要质量、上下文长度和硬件成本可能不适合长会议。 | Q-103, Q-107 | unconfirmed |
| AS-007 | 核心处理应保持 local-first，同时允许用户主动复制/导出 transcript 到外部服务。 | Q-103 确认允许手动复制 transcript 到 GPT；应用内 cloud API 集成尚未确认。 | 如果后续由应用自动调用云端，网络权限、secret 和合规范围都会改变。 | cloud/API 集成前的后续问题 | partially confirmed |
| AS-008 | 产品应把系统音频、麦克风音频和混合音轨作为独立 artifacts 保留。 | Q-105 确认选项 B。 | capture 工具不一定总能提供全部音轨；fallback 行为仍需要业务规则。 | Q-105, Q-202 | confirmed by CF-021 and CF-028 |
| AS-009 | 即使现场录制仍是主目标，导入已有媒体也可能作为 fallback 或测试路径有价值。 | 媒体处理流水线可以在没有现场 capture 权限的情况下验证。 | 如果不需要导入，范围可以更窄；如果需要，领域和 UI 旅程必须包含它。 | Q-102 | unconfirmed |
| AS-010 | 会议媒体和 transcripts 应视为敏感本地数据。 | 会议音频、视频和文本通常包含机密内容。 | 安全、保留、加密和导出规则可能定义不足。 | Q-103, Q-105, Q-205 | promoted to `13-security-and-compliance.md` via PL-002 and PL-004; future team-use controls remain watch-only |

## 冲突

| ID | 冲突 | 来源 | 影响 | 必需决策 | 状态 |
|---|---|---|---|---|---|
| CFLC-001 | 需求要求开源/免费工具，但 Apple 原生平台 API 免费却不是开源。 | `docs/adoption/INITIAL-REQUEST.md` 的开源/免费要求；Q-102 原生 macOS 录制决策；Q-207 依赖策略决策 | 严格解释可能排除已选择的原生 capture 路线；务实解释可以允许免费 OS API，同时要求第三方工具开源/免费且人工安装。 | Apple 平台 API 可作为 OS 能力使用；第三方依赖除非另行批准，必须使用允许的免费/开源来源。 | resolved for adoption by CF-024, CF-027 and CF-033; promoted via PL-004 |
| CFLC-002 | 希望区分说话人，但线上会议音频常被会议 app 混音，可能无法可靠识别真实说话人身份。 | `docs/adoption/INITIAL-REQUEST.md` 中的说话人区分诉求；Q-107 和 Q-204 回答 | 如果没有额外参会人、声纹或平台数据，承诺命名说话人可能不可行。 | 转写 MVP 规则：允许匿名 best-effort speaker labels；没有可用本地引擎时允许 transcript-only fallback；不承诺实名 identity。 | resolved for MVP behavior by CF-023 and CF-030; engine/quality threshold still a gap |
| CFLC-003 | 手动复制到 GPT 做纪要是可接受的，但应用内 cloud/API 处理仍未确认。 | `docs/adoption/INITIAL-REQUEST.md` 的可选 GPT 手动流程；Q-103 回答；Q-207 依赖策略决策 | 产品文案可以允许用户控制的外部复制；API 契约和 secret 范围除非后续确认，否则保持范围外。 | MVP 不包含应用托管的外部模型 API；未来 cloud/API 集成必须走新的 spec-change。 | resolved for MVP by CF-020 and CF-033; future cloud/API integration remains out of scope |

## 缺口

| ID | 缺口 | 为什么阻塞 | 目标 |
|---|---|---|---|
| GAP-001 | Phase 1 受众已确认为个人自用，后续可能小范围团队内部使用；分发机制仍未关闭。 | 不阻塞当前 spec 转写或个人 MVP；团队使用进入实施范围前必须关闭。 | `docs/product-spec/01-product-scope.md`, `docs/product-spec/13-security-and-compliance.md`, `docs/product-spec/10-open-decisions.md` |
| GAP-002 | 第一条可验证纵切已确认为原生 macOS 录制优先，并确认 app + helper 和 processing/dependency-check CLI 骨架。 | 产品规范已转写完成；activation-time 非业务组件骨架、manifest、可执行命令入口和 smoke E2E 计划已补齐。仍不代表产品行为已实现。 | `harness/project-manifest.json`, `docs/engineering/06-product-validation-matrix.md` |
| GAP-003 | 允许用户主动复制 transcript 到 GPT；应用内自动 cloud/API 使用不属于 MVP。 | 不阻塞当前 spec 转写；未来自动云/API 或本地 Qwen 纪要进入范围前必须走新的 spec-change。 | `docs/product-spec/10-open-decisions.md`, `docs/product-spec/13-security-and-compliance.md` |
| GAP-004 | 外部依赖策略是 bootstrap/check 脚本 + 人工安装允许来源；精确依赖清单、版本、hash 和许可证留作后续工作。 | 不阻塞当前 spec 转写；activation-time processing skeleton 已提供可执行门禁入口，真实 dependency-check 行为在 project 模式实现。 | `docs/engineering/02-dev-commands.md`, `docs/engineering/10-security-and-supply-chain.md`, `harness/project-manifest.json` |
| GAP-005 | 音频 artifact 契约已定义；不可用音轨的底层 capture fallback 需要实现验证。 | 不阻塞当前 spec 转写；属于 project 模式实现和测试风险。 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md`, `docs/engineering/06-product-validation-matrix.md` |
| GAP-006 | MVP 最低宿主是 Apple Silicon 和 macOS 26.5.1；具体原生录制 API 能力仍需验证。 | 不阻塞当前 spec 转写；属于 skeleton 后的技术验证和实现风险。 | `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/09-acceptance-criteria.md` |
| GAP-007 | MVP 的说话人区分是 best-effort 匿名 labels，并且没有可用本地引擎时允许 transcript-only fallback；具体 diarization 引擎和质量阈值仍未关闭。 | 不阻塞当前 spec 转写；具体引擎选择可以由 adapter 和 dependency-check 后续收敛。 | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/09-acceptance-criteria.md`, `docs/engineering/06-product-validation-matrix.md` |
| GAP-008 | Q-201 到 Q-207 已转写到持久 spec，activation-time 非业务骨架和 manifest/E2E 注册已创建。 | 不再阻塞 activation 工程准备；当前只剩用户 spec-review 和显式 activation 批准。 | `harness/project-manifest.json`, `docs/engineering/06-product-validation-matrix.md`, `docs/adoption/SPEC-READINESS.md` |

## 问题队列

每轮只应询问最高优先级的 3-7 个问题。

| ID | 优先级 | 问题 | 为什么重要 | 是否阻塞 | 选项或取舍 | 推荐选项 | 目标 product-spec 分卷 | 状态 |
|---|---|---|---|---|---|---|---|---|
| Q-101 | P0 | 第一阶段产品边界是个人自用本地工具、团队内部工具，还是未来可分发产品？ | 决定权限模型、安装包、签名/公证、依赖许可证、审计、SLO 和合规深度。 | yes | A. 个人自用：最快，可先不做多用户/审计；B. 团队内部：需要更明确的数据隔离、安装和支持；C. 可分发产品：许可证、签名、公证、更新和隐私声明都要前置。 | 推荐 A 作为 Phase 1，并把 B/C 记录为后续 open decision；这样能先验证本地录制和转写链路。 | `docs/product-spec/01-product-scope.md`, `docs/product-spec/13-security-and-compliance.md`, `docs/product-spec/08-implementation-guidance.md` | answered |
| Q-102 | P0 | 第一条可验证纵切应该优先做哪条：导入已有媒体并转写、OBS/BlackHole 辅助录制加转写，还是直接做原生 macOS 录制？ | 纵切会决定 manifest 组件、验证矩阵、验收标准和需要创建的最小骨架。 | yes | A. 导入已有媒体：风险最低但不验证录制；B. OBS/BlackHole/FFmpeg 辅助录制加转写：贴近目标但依赖安装配置；C. 原生录制：最终体验更好但开发和权限最高。 | 用户选择 C。 | `docs/product-spec/01-product-scope.md`, `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/09-acceptance-criteria.md` | answered |
| Q-103 | P0 | 核心处理是否必须完全离线？是否允许用户主动把 transcript 复制到 GPT 或其他外部服务？ | 这决定数据分类、网络权限、模型集成、隐私提示和安全门禁。 | yes | A. 严格离线：最高隐私但纪要能力依赖本地模型；B. 核心离线，允许用户手动导出/复制到外部服务：清晰可控；C. 允许云 API：能力强但合规和密钥管理更重。 | 推荐 B：产品核心不依赖云，外部使用必须由用户显式导出或复制。 | `docs/product-spec/13-security-and-compliance.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/06-api-contracts.md` | answered |
| Q-104 | P0 | 第一阶段是否允许用户手动安装和配置 OBS、BlackHole、FFmpeg、Whisper/Qwen 模型等外部依赖？ | 外部依赖策略决定开发命令、安装说明、支持边界、权限申请和是否能快速进入 MVP。 | yes | A. 手动前置安装：最快但体验粗糙；B. 提供 bootstrap/check 脚本：仍轻量，但可重复验证；C. 全部打包进应用：体验好但工程和许可证成本高。 | 用户选择 B。 | `docs/product-spec/08-implementation-guidance.md`, `docs/engineering/02-dev-commands.md`, `harness/project-manifest.json` | answered |
| Q-105 | P1 | 会议产物是否需要分别保存系统音频、麦克风音频和混合音频，还是只保存混合音频即可？ | 产物契约影响录制方案、存储布局、转写输入、说话人区分质量和失败恢复。 | yes | A. 只保存混合音频：最简单但后处理空间小；B. 系统音频、麦克风音频、混合音频都保存：更利于转写和排错但设置复杂；C. 只保存分轨不保存混合：更专业但用户回听不便。 | 推荐 B，在无法分轨时允许降级为 A 并记录能力状态。 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/05-business-rules-and-calculations.md` | answered |
| Q-106 | P1 | 第一阶段目标 Mac 范围是什么：只支持 Apple Silicon，还是也必须支持 Intel Mac？最低 macOS 版本是多少？ | 决定原生录制能力、模型运行性能、FFmpeg/Whisper 二进制选择和验收时长。 | yes | A. Apple Silicon + 当前宿主 macOS；B. Apple Silicon + Intel；C. 更老 macOS。 | 用户选择 Apple Silicon 和当前宿主 macOS 版本：macOS 26.5.1。 | `docs/product-spec/08-implementation-guidance.md`, `docs/product-spec/09-acceptance-criteria.md`, `harness/project-manifest.json` | answered |
| Q-107 | P1 | 说话人区分和会议纪要生成在 MVP 中是必需、best-effort，还是明确后置？ | 这决定是否要前置 diarization、本地 LLM、质量阈值、模型许可证和性能验证。 | yes | A. MVP 只要求带时间戳 transcript：最快最稳；B. 匿名 speaker labels best-effort：有价值但需接受误差；C. 命名说话人和自动纪要必需：产品完整但依赖和质量风险最高。 | 推荐 A 作为 MVP，B 作为后续实验，C 暂不承诺。 | `docs/product-spec/01-product-scope.md`, `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/09-acceptance-criteria.md` | answered |
| Q-201 | P0 | 原生录制采用最小 Swift/SwiftUI app、Swift CLI/helper，还是二者组合？ | 决定组件骨架、macOS 权限处理、UI 契约、manifest 和 E2E 形态。 | yes | A. 最小 Swift/SwiftUI app：更贴近权限和用户体验；B. Swift CLI/helper：更轻但权限/UI 验证不足；C. app + helper：边界清晰但骨架更多。 | 推荐 C，但 activation 前只创建最小非业务骨架。 | `docs/product-spec/04-user-journeys-and-ui.md`, `docs/product-spec/08-implementation-guidance.md`, `harness/project-manifest.json` | answered |
| Q-202 | P0 | MVP 媒体格式和 workspace 默认策略怎么固定？ | 决定 artifact contract、样例测试、转写输入和数据治理。 | yes | A. 原始录制格式保留，派生音频统一为可处理格式；B. 全部统一转码；C. 全部保留原生默认格式。 | 推荐 A：原始保留 + 派生标准化，降低丢失风险。 | `docs/product-spec/02-domain-model.md`, `docs/product-spec/07-data-and-events.md`, `docs/product-spec/09-acceptance-criteria.md` | answered |
| Q-203 | P0 | 转写 runtime 选现有本地 Whisper、whisper.cpp，还是先抽象 adapter 后再确认具体 runtime？ | 决定 dependency check、模型路径、许可证、性能和测试入口。 | yes | A. 复用现有 Whisper；B. whisper.cpp；C. 先定义 adapter + dependency check，再接入具体 runtime。 | 推荐 C，先稳定 contract，再用本地现有 Whisper 做首个 adapter 候选。 | `docs/product-spec/06-api-contracts.md`, `docs/product-spec/08-implementation-guidance.md`, `docs/engineering/06-product-validation-matrix.md` | answered |
| Q-204 | P0 | speaker labeling 是否允许无可用引擎时降级为 transcript-only？ | 影响 best-effort 的可验收性和 activation 是否必须先锁定 diarization 引擎。 | yes | A. 允许降级并记录原因；B. MVP 必须接入本地 diarization；C. MVP 暂不验收 speaker labels。 | 推荐 A，符合 best-effort，同时不阻断 transcript 主链路。 | `docs/product-spec/05-business-rules-and-calculations.md`, `docs/product-spec/09-acceptance-criteria.md` | answered |
| Q-205 | P0 | workspace 默认路径、保留、删除、加密策略怎么定？ | 阻塞数据分类、安全、删除和用户审查。 | yes | A. 默认用户本地目录明文，删除会话即删除；B. 默认本地目录 + 可选加密；C. 强制加密；D. 每次用户选择路径。 | 推荐 A 作为个人 MVP，并把加密作为后续安全增强。 | `docs/product-spec/07-data-and-events.md`, `docs/product-spec/13-security-and-compliance.md` | answered |
| Q-206 | P0 | activation 前最小非业务组件骨架怎么拆？ | 决定 manifest、CI gates、full-stack/E2E 替代方案和是否能通过 activation。 | yes | A. native app skeleton；B. native app skeleton + processing/dependency-check CLI skeleton；C. 单一 CLI skeleton。 | 推荐 B，覆盖原生入口和处理流水线，同时不实现业务行为。 | `harness/project-manifest.json`, `docs/engineering/06-product-validation-matrix.md`, `docs/engineering/02-dev-commands.md` | answered |
| Q-207 | P1 | 依赖来源、版本/hash/许可证和 agent policy 如何审查？ | 阻塞供应链、安全和 agent 权限边界，尤其涉及模型下载、本地工具和网络访问。 | yes | A. activation 前只列允许来源和人工安装；B. 加 hash/版本锁定；C. 允许脚本自动下载。 | 推荐 A 先关闭权限边界，后续逐步加 hash/锁定。 | `docs/product-spec/13-security-and-compliance.md`, `docs/engineering/10-security-and-supply-chain.md`, `harness/agent-policy.json` | answered |

## Q-102 决策支持：选项 B vs 选项 C

本节作为决策证据保留。当前有效决策是 Q-102 选项 C：原生 macOS 录制优先。

| 维度 | 选项 B：OBS/BlackHole/FFmpeg 辅助录制 + 转写 | 选项 C：原生 macOS 录制优先 |
|---|---|---|
| 主目标匹配 | 更早验证真实工作流：线上会议 capture、系统音频、麦克风音频、媒体 artifacts 和 transcript 流水线。 | 更早验证最终期望的 app 方向，但在 transcript 流水线被证明前，capture 层会先成为难点。 |
| 实现速度 | 更快，因为成熟工具处理 capture 和媒体处理；项目代码可以聚焦编排、metadata 和 transcription。 | 更慢，因为在得到有用输出前，需要设计 ScreenCaptureKit、音频 capture、权限、UI/后台行为和打包。 |
| 技术风险 | 主要风险是音频路由和依赖安装，尤其是 BlackHole 配置和音轨分离。 | 主要风险是原生音频 capture，尤其是可靠的系统音频 + 麦克风 capture、权限、app 生命周期和跨 macOS 版本边界情况。 |
| 用户 setup | 需要外部工具和 bootstrap/check 流程；体验更粗糙，但如果文档清楚且可验证，个人 MVP 可接受。 | 后续用户体验可能更干净，但早期构建仍需要 macOS 录屏/音频权限和更多 native-app 骨架。 |
| 开源/免费约束 | 使用开源/免费的第三方工具，但必须跟踪依赖许可证和再分发。 | 使用免费但非开源的 Apple 平台 API；这与严格的 open-source-only 解读冲突。 |
| 模块化流水线匹配 | 强匹配：capture 输出文件和 metadata，下游 transcription/diarization 可独立处理。 | 也可行，但原生 capture 代码可能在文件契约被证明前把项目推向 app 架构。 |
| 三类音频 artifact 支持 | 如果音频路由配置得当是可行的；分轨不可用时需要 fallback 规则。 | 长期可能更好，但需要更多定制工程来保证 system/mic/mixed artifacts。 |
| 验证和 CI | 更容易验证非交互部分：依赖检查、导入样例媒体、FFmpeg 处理、transcript 生成。现场 capture 仍部分依赖人工/E2E。 | 早期更难自动化，因为 macOS 权限、窗口 capture 和真实音频设备依赖环境。 |
| 未来迁移 | 可以当作可替换 capture adapter；后续原生 capture 可输出同一 artifact contract。 | capture 后续迁移更少，但在领域和 artifact contract 稳定前，阻塞整个产品的概率更高。 |
| 决策结果 | 拒绝作为 Phase 1 主路线；如果原生 capture 不可行，保留为可能 fallback。 | 用户选择为 Phase 1 主路线。 |

## 用户回答

| 问题 ID | 回答 | 回答人 | 日期 | 是否需要后续跟进 |
|---|---|---|---|---|
| Q-000A | 项目名称确认为 `meeting_assistant`。 | user | 2026-06-26 | no |
| Q-000B | 项目 owner 确认为 `JeRRy`。 | user | 2026-06-26 | no |
| Q-101 | Phase 1 是个人自用；后续可能给少量团队内部成员使用。 | user | 2026-06-26 | no |
| Q-102 | 用户要求先详细比较选项 B 和 C 再决策。后续被选择选项 C 取代。 | user | 2026-06-26 | no |
| Q-103 | 用户可以手动复制 transcript 文本到 GPT。 | user | 2026-06-26 | no |
| Q-105 | 保留系统音频、麦克风音频和混合音频。 | user | 2026-06-26 | no |
| Q-106 | MVP 只需要 Apple Silicon 支持。最低 macOS 后续由 Q-106b 取代。 | user | 2026-06-26 | no |
| Q-107 | MVP 应包含 best-effort 匿名 speaker labels。 | user | 2026-06-26 | no |
| Q-102 | 第一条纵切选择 C：原生 macOS 录制优先。 | user | 2026-06-26 | no |
| Q-104 | 依赖策略选择 B：bootstrap/check 脚本。 | user | 2026-06-26 | no |
| Q-106b | 最低平台应使用当前系统版本；当前宿主是 arm64 上的 macOS 26.5.1。 | user and local command | 2026-06-26 | no |
| Q-201 | 用户接受推荐：原生录制结构应是 app + helper，activation 前只创建非业务骨架。 | user | 2026-06-26 | no |
| Q-202 | 用户接受推荐：保留原始录制格式，并标准化派生音频 artifacts。 | user | 2026-06-26 | no |
| Q-203 | 用户接受推荐：先定义 transcription adapter/dependency-check 契约，再锁定具体 runtime。 | user | 2026-06-26 | no |
| Q-204 | 用户接受推荐：speaker labeling 无可用本地引擎时允许 transcript-only fallback，并记录原因。 | user | 2026-06-26 | no |
| Q-205 | 用户接受推荐：个人 MVP 默认本地明文 workspace，删除会话即删除 artifacts，并后置加密。 | user | 2026-06-26 | no |
| Q-206 | 用户接受推荐：activation-time 骨架计划是 native app skeleton + processing/dependency-check CLI skeleton，不包含业务行为。 | user | 2026-06-26 | no |
| Q-207 | 用户接受推荐：activation 前列出允许来源并要求人工安装；自动下载不属于初始策略。 | user | 2026-06-26 | no |
| ADOPT-PLAN-001 | 用户要求基于完成 adoption、进入项目开发状态的计划继续推进 adoption；本轮仅补齐非业务 activation 准备，不运行 `activate-project`。 | user | 2026-06-26 | no |

## 转写记录

记录每次从 adoption 工作区转写到持久事实源的动作。

| ID | 来源 | 目标位置 | 摘要 | 确认人 | 日期 |
|---|---|---|---|---|---|
| PL-001 | 用户确认 | `harness/adoption-state.json`, `harness/project-manifest.json` | 初始化 adoption 项目元数据：project `meeting_assistant`，owner `JeRRy`。 | user | 2026-06-26 |
| PL-002 | `DISCOVERY-LEDGER.md` CF-001, CF-003..CF-023 | `docs/product-spec/01-product-scope.md` 到 `13-security-and-compliance.md` | 转写已确认的 Phase 1 产品范围、本地 macOS 平台、artifact 模型、本地命令边界、安全边界和验收标准。 | user | 2026-06-26 |
| PL-003 | `DISCOVERY-LEDGER.md` CF-024..CF-026 | `docs/product-spec/08-implementation-guidance.md`, `11-adr.md`, `docs/engineering/06-product-validation-matrix.md` | 转写原生 macOS 录制优先、bootstrap/check 依赖策略和 Apple Silicon macOS 26.5.1 MVP 平台。 | user | 2026-06-26 |
| PL-004 | `DISCOVERY-LEDGER.md` CF-027..CF-033 | `docs/product-spec/02-domain-model.md`, `04-user-journeys-and-ui.md`, `05-business-rules-and-calculations.md`, `06-api-contracts.md`, `07-data-and-events.md`, `08-implementation-guidance.md`, `09-acceptance-criteria.md`, `10-open-decisions.md`, `11-adr.md`, `12-ui-ux-design.md`, `13-security-and-compliance.md`, `docs/engineering/02-dev-commands.md`, `docs/engineering/06-product-validation-matrix.md`, `docs/engineering/10-security-and-supply-chain.md`, `harness/agent-policy.json` | 转写 app+helper 控制面、原始+normalized audio 策略、transcription adapter 策略、transcript-only speaker fallback、明文本地 workspace、骨架计划和人工 allowed-source 依赖策略。 | user | 2026-06-26 |
| PL-005 | `DISCOVERY-LEDGER.md` CF-034 | `docs/engineering/05-agent-operating-model.md`, `docs/adoption/SPEC-READINESS.md` | 转写已确认的 adoption/spec 多 agent 工作流：PM / Spec Owner + Worker + read-only Reviewer，并按需启用 Specialist。 | user | 2026-06-26 |
| PL-006 | PM spec transfer review | `docs/product-spec/13-security-and-compliance.md`, `docs/adoption/SPEC-READINESS.md`, `harness/adoption-state.json` | 补充 Phase 1 生产就绪适用性，将 product-spec 分卷标记为 ready，并把 adoption 子阶段推进到 spec-review；activation 仍保持阻断。 | user request to continue spec transfer | 2026-06-26 |
| PL-007 | `DISCOVERY-LEDGER.md` CF-035 | `docs/engineering/05-agent-operating-model.md` | 转写已确认的持久 Markdown spec 中文优先规则，并保留稳定技术标识原文。 | user | 2026-06-26 |
| PL-008 | `DISCOVERY-LEDGER.md` CF-032, CF-036 | `harness/project-manifest.json`, `docs/engineering/02-dev-commands.md`, `docs/engineering/06-product-validation-matrix.md`, `docs/adoption/SPEC-READINESS.md`, `harness/adoption-state.json` | 创建并注册 `native-app` 与 `processing-cli` 非业务 activation skeleton、smoke E2E 计划、Phase 1 本地运行准备工件和项目门禁；产品行为验证仍保持 planned。 | user | 2026-06-26 |

## 转写和 Activation 后续队列

这些条目跟踪哪些已确认 discovery 项已转写，以及哪些 activation follow-up 仍未完成。它们不是产品事实。

| ID | 来源 | 必需目标位置 | 摘要 | 状态 |
|---|---|---|---|---|
| PP-001 | CF-027 / Q-201 | `04-user-journeys-and-ui.md`, `08-implementation-guidance.md`, `harness/project-manifest.json` | App + helper 原生录制结构；activation 前只允许非业务骨架。 | promoted；非业务骨架已创建 |
| PP-002 | CF-028 / Q-202 | `02-domain-model.md`, `07-data-and-events.md`, `09-acceptance-criteria.md` | 保留原始录制，并生成标准化派生音频 artifacts。 | promoted |
| PP-003 | CF-029 / Q-203 | `06-api-contracts.md`, `08-implementation-guidance.md`, validation matrix | 具体 runtime 锁定前先定义 transcription adapter 和 dependency-check 契约。 | promoted |
| PP-004 | CF-030 / Q-204 | `05-business-rules-and-calculations.md`, `09-acceptance-criteria.md` | Speaker-label fallback 到 transcript-only，并记录原因。 | promoted |
| PP-005 | CF-031 / Q-205 | `07-data-and-events.md`, `13-security-and-compliance.md` | 本地明文个人 MVP workspace、删除语义、加密后置。 | promoted |
| PP-006 | CF-032 / Q-206 | `harness/project-manifest.json`, validation matrix, dev commands | Native app skeleton 加 processing/dependency-check CLI skeleton，无业务行为。 | promoted；manifest、骨架和门禁已补齐 |
| PP-007 | CF-033 / Q-207 | `13-security-and-compliance.md`, `10-security-and-supply-chain.md`, `harness/agent-policy.json` | 允许来源和人工安装优先；初始策略不自动下载。 | promoted |
