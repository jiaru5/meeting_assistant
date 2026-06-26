# 10. 未决决策

本文件只记录仍未确认的产品或技术问题。已关闭的问题必须回到对应主责分卷维护，重要决策追加到 `11-adr.md`。

## 当前状态

当前项目处于 adoption/spec-review。当前核心产品方向已确认；`watch` 项不阻塞当前 spec review，但在对应能力进入范围前必须关闭。activation-time 非业务组件骨架、manifest、验证命令和 E2E smoke 计划已注册；activation 仍会被用户 product-spec review 和用户 activation sign-off 阻断。

## 未决决策

| ID | 状态 | 问题 | 影响范围 | 选项 | owner | 关闭条件 |
|---|---|---|---|---|---|---|
| OD-MA-001 | closed | 原生 macOS 录制的技术边界是什么？ | `04-user-journeys-and-ui.md`, `08-implementation-guidance.md`, manifest | 决策：最小 Swift/SwiftUI app + local helper / processing CLI；具体 capture API 以 adapter 方式落地，不改变 artifact contract | JeRRy | 已写入旅程、implementation guidance 和 ADR |
| OD-MA-002 | closed | 媒体编码、容器和文件扩展名如何固定？ | `02-domain-model.md`, `07-data-and-events.md`, `09-acceptance-criteria.md` | 决策：原始录制格式保留；派生处理音频统一为 `.wav` normalized audio | JeRRy | 已写入 artifact format policy、领域模型和验收标准 |
| OD-MA-003 | closed | 转写 runtime 和模型路径如何确定？ | `06-api-contracts.md`, `08-implementation-guidance.md`, manifest | 决策：adapter-first；首个候选可复用现有本地 Whisper；具体 runtime 由 dependency check 报告 | JeRRy | 已写入 command contract、implementation guidance 和验证矩阵 |
| OD-MA-004 | closed | best-effort speaker labeling 使用哪个本地引擎，最低质量阈值是什么？ | `05-business-rules-and-calculations.md`, `09-acceptance-criteria.md`, `13-security-and-compliance.md` | 决策：MVP 允许无可用引擎时降级 transcript-only 并记录原因；不承诺真实身份或强准确率 | JeRRy | 已写入规则、验收和安全分卷 |
| OD-MA-005 | closed | MVP control surface 是完整桌面 UI、菜单栏工具、最小窗口、CLI/helper，还是组合？ | `04-user-journeys-and-ui.md`, `12-ui-ux-design.md`, manifest | 决策：最小 Swift/SwiftUI app + local helper / processing CLI | JeRRy | 已写入 UI/UX 和旅程分卷 |
| OD-MA-006 | closed | workspace 默认路径、数据保留、删除和本地加密策略是什么？ | `07-data-and-events.md`, `13-security-and-compliance.md` | 决策：默认 `~/Movies/MeetingAssistant/`，MVP 明文，删除会话即删除会话目录内文件，加密后续增强 | JeRRy | 已写入数据和安全分卷 |
| OD-MA-007 | closed | activation 前的最小组件骨架和 full-stack/E2E 替代方案是什么？ | `harness/project-manifest.json`, `docs/engineering/06-product-validation-matrix.md` | 决策：activation 前可创建 native app skeleton + processing/dependency-check CLI skeleton，且不得实现业务行为 | JeRRy | 已写入 implementation guidance、验证矩阵、manifest 和 activation skeleton；产品行为仍待 project 模式实现 |
| OD-MA-010 | closed | 依赖来源、版本/hash、许可证和 agent policy 如何审查？ | `13-security-and-compliance.md`, `docs/engineering/10-security-and-supply-chain.md`, `harness/agent-policy.json` | 决策：允许来源 + 人工安装；bootstrap/check 不自动下载；版本/hash 锁定后续增强 | JeRRy | 已写入安全、供应链和 agent policy |
| OD-MA-008 | watch | 少量团队内部使用如何分发和支持？ | `01-product-scope.md`, `03-permissions-and-identity.md`, `13-security-and-compliance.md` | A. 共享安装包；B. 私有源码运行；C. 签名公证分发 | JeRRy | 团队使用进入实施范围前关闭 |
| OD-MA-009 | watch | 是否未来由应用自动调用 GPT 或本地 Qwen 生成会议纪要？ | `06-api-contracts.md`, `13-security-and-compliance.md` | A. 仅手动复制；B. 本地 Qwen；C. 外部 API；D. 双模式 | JeRRy | 会议纪要自动化进入实施范围前关闭 |

状态取值：

1. `open`：阻塞实现或 activation。
2. `watch`：不阻塞当前实现，但需要后续确认。
3. `closed`：已关闭，必须回写主责分卷。
