# 10. 未决决策

本文件只记录仍未确认的产品或技术问题。已关闭的问题必须回到对应主责分卷维护，重要决策追加到 `11-adr.md`。

## 决策状态规则

当前 mode 值只由 `PROJECT-STATUS.md` 声明。`watch` 项不阻塞个人 MVP 纵切，但在对应能力进入实现范围前必须先关闭并回写主责分卷、ADR 和验证矩阵。

## 未决决策

| ID | 状态 | 问题 | 影响范围 | 选项 | owner | 关闭条件 |
|---|---|---|---|---|---|---|
| OD-MA-001 | closed | 原生 macOS 录制的技术边界是什么？ | `04-user-journeys-and-ui.md`, `08-implementation-guidance.md`, manifest | 决策：最小 Swift/SwiftUI app + local helper / processing CLI；具体 capture API 以 adapter 方式落地，不改变 artifact contract | JeRRy | 已写入旅程、implementation guidance 和 ADR |
| OD-MA-002 | closed | 媒体编码、容器和文件扩展名如何固定？ | `02-domain-model.md`, `07-data-and-events.md`, `09-acceptance-criteria.md` | 决策：原始录制格式保留；派生处理音频统一为 `.wav` normalized audio | JeRRy | 已写入 artifact format policy、领域模型和验收标准 |
| OD-MA-003 | closed | 转写 runtime 和模型路径如何确定？ | `06-api-contracts.md`, `08-implementation-guidance.md`, manifest | 决策：adapter-first；VS-MA-06 首个真实 runtime 固定为本地 `whisper.cpp` CLI，模型路径由 `MEETING_ASSISTANT_TRANSCRIPTION_MODEL` 指向用户人工准备的 multilingual Whisper-compatible 模型；真实 covered 证据必须覆盖中英混合会议语音，不使用 English-only `.en` 模型 | JeRRy | 已写入 command contract、implementation guidance 和验证矩阵 |
| OD-MA-004 | closed | best-effort speaker labeling 使用哪个本地引擎，最低质量阈值是什么？ | `05-business-rules-and-calculations.md`, `09-acceptance-criteria.md`, `13-security-and-compliance.md` | 决策：MVP 允许无可用引擎时降级 transcript-only 并记录原因；不承诺真实身份或强准确率 | JeRRy | 已写入规则、验收和安全分卷 |
| OD-MA-005 | closed | MVP control surface 是完整桌面 UI、菜单栏工具、最小窗口、CLI/helper，还是组合？ | `04-user-journeys-and-ui.md`, `12-ui-ux-design.md`, manifest | 决策：最小 Swift/SwiftUI app + local helper / processing CLI | JeRRy | 已写入 UI/UX 和旅程分卷 |
| OD-MA-006 | closed | workspace 默认路径、数据保留、删除和本地加密策略是什么？ | `07-data-and-events.md`, `13-security-and-compliance.md` | 决策：默认 `~/Movies/MeetingAssistant/`，MVP 明文，删除会话即删除会话目录内文件，加密后续增强 | JeRRy | 已写入数据和安全分卷 |
| OD-MA-007 | closed | 非业务组件骨架和 full-stack/E2E 替代方案是什么？ | `harness/project-manifest.json`, `docs/engineering/06-product-validation-matrix.md` | 决策：可创建 native app skeleton + processing/dependency-check CLI skeleton，且不得实现业务行为 | JeRRy | 已写入 implementation guidance、验证矩阵、manifest 和非业务 skeleton；产品行为仍按验证矩阵推进 |
| OD-MA-010 | closed | 依赖来源、版本/hash、许可证和 agent policy 如何审查？ | `13-security-and-compliance.md`, `docs/engineering/10-security-and-supply-chain.md`, `harness/agent-policy.json` | 决策：允许来源 + 人工安装；bootstrap/check 不自动下载；版本/hash 锁定后续增强 | JeRRy | 已写入安全、供应链和 agent policy |
| OD-MA-011 | closed | Phase 2 是否按通用 web/backend/db 纵切，还是按 native-app/processing-cli 本地纵切？ | `08-implementation-guidance.md`, `docs/engineering/07-development-plan.md` | 决策：Phase 2 采用 `processing-cli` 命令契约优先，再接最小 `native-app` 控制面的本地纵切；不为 Phase 1 先建 Web/远程后端/数据库 | JeRRy | 已写入 implementation guidance、开发计划和 ADR |
| OD-MA-012 | closed | 原生 UI 自动化使用 XCUITest/Swift Testing，还是另设桌面测试工具？ | `12-ui-ux-design.md`, `docs/engineering/03-test-strategy.md` | 决策：Swift Testing 覆盖状态和 view model；XCUITest 覆盖 SwiftUI 关键用户状态；Playwright 只在未来 Web UI 时使用 | JeRRy | 已写入测试策略、UI/UX 和 ADR |
| OD-MA-013 | closed | 原生系统音频 capture 不可行时能否回到辅助录制方案？ | `01-product-scope.md`, `08-implementation-guidance.md`, `11-adr.md` | 决策：native-first 不变；辅助 capture 只能在 spike 证据充分后通过 spec-change、ADR 和验证矩阵更新纳入，不允许代码静默切换 | JeRRy | 已写入 implementation guidance 和 ADR |
| OD-MA-008 | watch | 少量团队内部使用如何分发和支持？ | `01-product-scope.md`, `03-permissions-and-identity.md`, `13-security-and-compliance.md` | A. 共享安装包；B. 私有源码运行；C. 签名公证分发 | JeRRy | 团队使用进入实施范围前关闭 |
| OD-MA-009 | watch | 是否未来由应用自动调用 GPT 或本地 Qwen 生成会议纪要？ | `06-api-contracts.md`, `13-security-and-compliance.md` | A. 仅手动复制；B. 本地 Qwen；C. 外部 API；D. 双模式 | JeRRy | 会议纪要自动化进入实施范围前关闭 |

状态取值：

1. `open`：阻塞实现或模式切换。
2. `watch`：不阻塞当前实现，但需要后续确认。
3. `closed`：已关闭，必须回写主责分卷。
