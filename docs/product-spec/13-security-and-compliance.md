# 13. 安全和合规

本文件是项目安全需求、数据分类、威胁模型、合规边界和风险接受的产品事实源。工程扫描工具、CI 实现和供应链规则由 `docs/engineering/10-security-and-supply-chain.md` 维护。

## 安全目标

| ID | 资产或能力 | 安全目标 | 失败影响 | 验证入口 |
|---|---|---|---|---|
| SEC-MA-001 | 会议视频、音频和 transcript | 默认仅保存在用户本地 workspace，不由应用自动上传 | 会议内容泄露 | `PV-MA-007`, `PV-MA-005` |
| SEC-MA-002 | macOS 权限 | 录屏、麦克风和文件权限缺失时 fail closed | 未授权录制、录制失败或数据写错位置 | `PV-MA-001` |
| SEC-MA-003 | 外部 GPT 使用边界 | 仅允许用户主动复制或导出 transcript 后自行使用外部工具 | 应用无意上传敏感会议内容 | `PV-MA-007` |
| SEC-MA-004 | 本地依赖和模型 | bootstrap/check 必须暴露依赖来源和缺失状态 | 不可信依赖、错误模型或静默失败 | `PV-MA-006` |

## 数据分类

| ID | 数据类型 | 分类 | 存储要求 | 传输要求 | 日志规则 | 保留与删除 |
|---|---|---|---|---|---|---|
| DATA-MA-001 | 原始会议视频 | confidential by default | 默认 `~/Movies/MeetingAssistant/`，MVP 不启用应用级加密 | 不自动传输 | 不记录完整内容 | 用户删除会话时删除会话目录内文件 |
| DATA-MA-002 | 系统音频、麦克风音频、混合音频 | confidential by default | 默认 `~/Movies/MeetingAssistant/`，MVP 不启用应用级加密 | 不自动传输 | 不记录完整内容 | 用户删除会话时删除会话目录内文件 |
| DATA-MA-003 | transcript 和 speaker labels | confidential by default | 默认 `~/Movies/MeetingAssistant/`；可由用户主动复制或导出 | 仅用户主动外部复制/导出 | 日志不记录完整 transcript | 用户删除会话时删除；workspace 外导出由用户负责 |
| DATA-MA-004 | 处理日志和元数据 | internal | 本地 workspace | 不自动传输 | 不记录 secret、完整 transcript 或无关敏感内容 | 随会话删除 |
| DATA-MA-005 | 本地模型路径和依赖版本 | internal | 本地配置或日志摘要 | 不自动传输 | 可记录版本和路径摘要 | 随配置或日志清理 |

应用级加密、hash 锁定、安全删除和团队共享审计作为后续增强，不属于个人 MVP 默认能力；团队内部使用进入实施范围前必须重新审查。

## 威胁模型

| ID | 信任边界 | 威胁 | 攻击路径 | 预防控制 | 检测控制 | 残余风险 |
|---|---|---|---|---|---|---|
| THREAT-MA-001 | macOS 权限到录制进程 | 未授权或失败录制 | 权限缺失、权限被撤销、目标窗口不可用 | 启动前权限检查，失败时阻断 | 本地日志记录权限状态 | 用户需要手动修复系统权限 |
| THREAT-MA-002 | workspace 文件系统 | 会议文件泄露或误写路径 | 写入不受控目录、导出到错误路径 | 限制默认 workspace，导出需用户选择 | 本地记录导出摘要 | MVP 依赖当前 macOS 用户和文件系统权限，不提供应用级加密 |
| THREAT-MA-003 | 外部 GPT 手动复制 | 用户把敏感 transcript 发给外部服务 | 用户复制 transcript 到外部工具 | 应用明确这是用户主动行为，不自动上传 | 本地记录导出或复制动作摘要 | 外部服务处理不受本系统控制 |
| THREAT-MA-004 | 本地依赖供应链 | 不可信工具或模型处理会议内容 | 安装来源不明、模型被替换 | bootstrap/check 显示依赖和模型摘要；只允许人工安装和允许来源 | 依赖检查输出 | 版本/hash 锁定作为后续增强 |
| THREAT-MA-005 | AI speaker labeling | 错误 speaker labels 被误认为真实身份 | 混音、噪音、重叠说话导致错误标签 | UI 和导出中标记为匿名 best-effort；失败时降级 transcript-only | 处理日志记录引擎和失败状态 | 无法保证 diarization 准确率 |

## 安全验证基线

1. Phase 1 不是 Web/API 多用户系统，不适用完整 Web ASVS 范围。
2. 本地权限、文件边界、依赖供应链、AI 处理边界和外部导出边界是 MVP 安全重点。
3. 每个高风险 `SEC-MA-*` 和 `THREAT-MA-*` 必须映射到 `AC-*`、`PV-*` 或本地验证证据。
4. 不能仅以“没有发现问题”证明安全完成。

## 合规与隐私

| 约束 | 适用范围 | 数据或流程影响 | 证据 | Owner |
|---|---|---|---|---|
| 个人本地使用 | Phase 1 MVP | 不引入组织账号、云同步或远程审计 | `01-product-scope.md` | JeRRy |
| 用户主动外部复制 | transcript export/copy | 应用不自动上传，外部工具处理由用户自行决定 | `06-api-contracts.md` | JeRRy |
| 依赖人工安装和允许来源 | 原生工具链、媒体工具、转写 runtime、speaker labeling runtime | bootstrap/check 只检查和提示，不自动下载模型或二进制 | `08-implementation-guidance.md` | JeRRy |
| 未来团队内部使用 | 后续团队内部使用 | 需要重新确认权限、共享、审计、安装和数据治理 | `10-open-decisions.md` | JeRRy |

## 生产就绪适用性

Phase 1 MVP 是个人本地 macOS 工具，不包含远程生产服务、组织级账号、云同步、团队共享空间、服务端 on-call 或集中式生产数据存储。因此以下生产运行要求在个人 MVP 中为 `not-applicable`，进入团队内部分发、云/API 集成或商业化分发前必须重新确认：

| 项 | Phase 1 适用性 | 理由 | 后续触发条件 |
|---|---|---|---|
| SLO / error budget | `not-applicable` | 没有远程生产服务或多用户可用性承诺 | 团队共享、云服务或对外分发进入范围 |
| RTO / RPO | `not-applicable` | 默认数据保存在用户本地 workspace，由当前 macOS 用户管理 | 引入共享存储、自动备份或团队数据空间 |
| On-call / incident response | `not-applicable` | 个人本地工具没有生产值班面 | 引入团队支持、集中服务或外部分发 |
| Backup / restore plan | `not-applicable` | MVP 不提供应用级备份；会话删除按本地目录删除语义执行 | 引入应用管理备份、云同步或团队数据保留 |

## 风险接受

当前没有已接受的安全门禁例外。以下问题进入后续团队或产品化范围前必须重新审查：

1. 应用级加密和安全删除。
2. 依赖自动下载、hash 锁定、签名和许可证自动门禁。
3. 团队内部分发、共享和审计。
4. 更严格的 speaker labeling 质量阈值或真实身份识别。
