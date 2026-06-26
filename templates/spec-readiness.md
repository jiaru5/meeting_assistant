# Spec Readiness 模板

使用 `docs/adoption/SPEC-READINESS.md` 作为工作副本。project activation 前，每一行都必须达到 `ready` 或明确标记为 `not-applicable`。

| 分卷或领域 | 必需内容 | 状态 | 是否阻塞缺口 | 下一步 |
|---|---|---|---|---|
| `01-product-scope.md` | 目标、非目标、用户、场景和成功标准 | missing | yes |  |
| `02-domain-model.md` | 领域模型、字段、枚举、生命周期和不变量 | missing | yes |  |
| `03-permissions-and-identity.md` | 身份、角色、权限、租户隔离和审计 | missing | yes |  |
| `04-user-journeys-and-ui.md` | 旅程、页面/视图和失败状态 | missing | yes |  |
| `05-business-rules-and-calculations.md` | 规则、状态机、计算和幂等 | missing | yes |  |
| `06-api-contracts.md` | API/命令/事件契约和错误 | missing | yes |  |
| `07-data-and-events.md` | 持久化、migration、事件、保留和审计数据 | missing | yes |  |
| `08-implementation-guidance.md` | 技术栈、服务边界和部署约束 | missing | yes |  |
| `09-acceptance-criteria.md` | 映射到行为的 `AC-*` 验收标准 | missing | yes |  |
| `10-open-decisions.md` | 没有阻塞性的 open decision | missing | yes |  |
| `11-adr.md` | 重要决策有 Accepted ADR | missing | yes |  |
| `12-ui-ux-design.md` | UI/UX、可访问性、locator 规则或明确 N/A | missing | yes |  |
| `13-security-and-compliance.md` | 安全、数据分类、威胁模型、合规和恢复目标 | missing | yes |  |
| Validation matrix | 真实 `PV-*` 行已映射到测试或计划门禁 | missing | yes |  |
| Project manifest | 真实项目、owner、组件、命令和 full-stack E2E 计划 | missing | yes |  |
