# 11. 生产就绪

本文件定义企业级系统进入生产前的运行准备、可靠性、发布和恢复要求。

## 必需工件

`harness/project-manifest.json` 的 `production_readiness` 必须指向真实且无占位符的：

1. 威胁模型。
2. SLO。
3. 运行手册。
4. 回滚计划。
5. 备份和恢复计划。
6. 事故响应计划。
7. 数据分类。

这些工件应维护在对应主责分卷或 `docs/engineering/operations/` 下，不能仅存在于聊天、工单或个人笔记中。

## SLO 和容量

1. 每条关键用户旅程必须定义可测量的可用性、延迟或正确性 SLI。
2. SLO 必须有统计窗口、目标值、错误预算和告警策略。
3. 发布前必须运行与预期容量匹配的性能和负载测试。
4. 必须定义资源上限、队列背压、限流和过载降级行为。

## 发布与回滚

1. 发布制品来自受控 CI，并能追溯到 commit、SBOM、签名和 provenance。
2. 生产变更必须经过独立人工批准。
3. 使用 canary、blue/green、feature flag 或项目批准的渐进发布策略。
4. rollback 不能依赖修改已执行的 versioned migration。
5. 数据和应用版本必须明确向前兼容窗口。

`./scripts/release-bundle-check.sh` 是 release bundle evidence 的机器入口。发布候选必须提供 `.harness/release-inputs/bundle/release-bundle-report.json`，或通过 `MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT` 指向等价 report；report 必须绑定当前 commit、builder 和 source repository，并指向真实存在且 `sha256:` digest 匹配的 `MeetingAssistantNative.app` Release zip archive。bundle evidence 必须声明 `archive_format=zip`、code-signed、notarized、stapled、签名身份、notarization ticket、不打包 runtime/model、不自动下载且不包含会议数据；checker 必须解压 archive 并通过 `codesign`、`stapler` 和 `spctl` 校验 archive 内的 `MeetingAssistantNative.app`。缺少字段、digest 不匹配、archive 不合法、`.app` 不唯一或本体签名/公证/Gatekeeper 校验失败时 release bundle gate 必须 fail closed。

`./scripts/supply-chain-check.sh release` 同时要求 release provenance、signature 和 sidecar portability evidence。发布候选必须提供 `.harness/release-inputs/bundle/release-bundle-report.json`、`.harness/release-inputs/supply-chain/release-provenance-report.json`、`.harness/release-inputs/supply-chain/release-signature-report.json` 和 `.harness/release-inputs/supply-chain/release-sidecar-report.json`，或通过对应 `MEETING_ASSISTANT_RELEASE_*_REPORT` 环境变量指向等价 report；provenance 和 signature report 必须绑定当前 commit，并包含与 release bundle report 同一 `sha256:` digest 的 artifact，防止签名/来源证明指向另一份分发包。provenance report 还必须指向 digest 匹配的 DSSE in-toto SLSA v1 attestation 文件，且 statement subject 必须覆盖同一 release bundle digest；signature report 必须为同一 artifact 提供 keyless OIDC certificate identity/issuer、transparency log 和 digest 匹配的 Sigstore bundle 文件。sidecar report 必须绑定当前 commit，声明 `release_gate=release-sidecar-portability`、`target_scope=all-target-machines`、不打包 runtime/model、不自动下载、不访问外网，并为每个目标机器记录 `.local` 下 runtime、model、mixed-language smoke audio fixture 的 digest/source、model license/provenance 引用，以及 `check_dependencies`、`whisper.cpp` smoke 和 no-auto-download 通过状态；每个目标机器还必须引用 digest 匹配的 `release-sidecar-target-smoke` report 文件，供 checker 解析并比对 commit、target id/os/architecture、runtime/model/audio digest 和 smoke 结果。缺少任一 report、bundle digest 不匹配、attestation/signature bundle 不可审计、任一目标机器 smoke report 缺失或任一目标机器证据不完整时，release supply-chain gate 必须 fail closed。

每台目标机的 `release-sidecar-target-smoke` report 由 `platform/e2e/release-sidecar-target-smoke.sh` 生成。该 report 只记录单台机器的 runtime/model/audio sidecar repeatability evidence，发布负责人仍必须把所有目标机器 report 汇总到 release sidecar portability report，并确保该 report 的 `target_scope=all-target-machines`、target 列表、digest 和 smoke 状态与每个 target report 一致。单台机器 report 通过不能替代签名/公证 release bundle、DSSE/SLSA provenance、Sigstore signing bundle 或全部目标机器 sidecar portability evidence。

## 数据保护和恢复

1. 为关键数据定义 RPO 和 RTO。
2. 备份必须加密、访问受控，并定期执行恢复演练。
3. migration、批处理和数据修复必须有 dry-run、审计和回滚或前向修复方案。
4. 灾难恢复验证必须记录实际耗时和恢复结果，不能只证明“存在备份”。

## 运行和事故响应

1. 服务必须有 owner、on-call 或明确升级路径。
2. runbook 覆盖启动失败、依赖故障、容量不足、消息积压、数据异常和安全事件。
3. 告警必须对应用户影响或可执行操作，避免仅以基础设施噪声告警。
4. 事故结束后记录无责复盘，并把长期改进回写规范、测试或门禁。

## 生产就绪审查

生产发布前由非实现者完成独立审查，至少确认：

1. 产品验收和验证矩阵已 covered。
2. 安全威胁和高风险残余项已关闭或正式接受。
3. SLO、监控、告警、日志和 trace 可用于定位故障。
4. 负载、恢复、回滚和事故响应已经实际演练。
5. 生产权限、secret、部署和审计边界符合最小权限。

`./scripts/production-readiness-check.sh` 是机器入口，但不能替代独立审查。
