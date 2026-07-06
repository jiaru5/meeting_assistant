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

`./scripts/release-credential-check.py` 可在 release rehearsal 或负责签名/公证的 CI job 开始前运行，确认本机或 runner 具备 `codesign`、`notarytool`、`stapler`、`spctl` 和 `Developer ID Application` codesigning identity。它只生成 `release_gate=release-credential-prereq` 的环境前置诊断，帮助提前发现无法产出签名/公证 Release archive 的执行环境；它不构建、不签名、不公证、不上传 notary、不生成 SLSA 或 Sigstore，也不能替代 release bundle、provenance、signature 或 sidecar evidence。

`./scripts/release-bundle-create.py` 可在具备 Apple 分发凭据的 release rehearsal 或 CI job 中产出 `MeetingAssistantNative.app` Release zip 和 bundle report。运行方必须显式配置 signing identity、notarytool keychain profile、builder 和 source repository；脚本会构建 Release app、签名、公证、staple、打包，并默认复跑 `release-bundle-check.sh`。该脚本成功只代表 release bundle 本体和 bundle report 达到 release bundle gate 的输入要求；发布候选仍必须提供同一 bundle digest 的 DSSE/SLSA provenance、Sigstore signature、all-target sidecar portability evidence，并通过 `supply-chain-check.sh release`、`product-validation-check.py release` 和 `release-preflight.sh`。

`./scripts/release-candidate-inputs.py` 可在 release rehearsal 或 CI 中串联完整 release input 验证：产出或复用签名/公证 bundle、物料化 bundle/provenance/signature reports、校验 release bundle、本次 release sidecar report 和 release supply-chain gate。它要求真实 DSSE/SLSA attestation 与 Sigstore bundle 文件已经由对应 release job 生成，并且不能用占位 JSON 替代。该脚本通过后只说明 release input evidence set 可被 release supply-chain gate 接受；发布候选仍必须让 `product-validation-check.py release` 全部 covered，并让 `release-preflight.sh` 通过。

`./scripts/release-inputs-report.py` 可以在 release rehearsal 或 CI 已经产出真实签名/公证 archive、DSSE/SLSA attestation 和 Sigstore bundle 后，将这些物料写入默认 `.harness/release-inputs/` report 路径。release rehearsal 或 CI 应使用 `--verify-release-bundle`，在写 report 前解压 archive 并运行 `codesign`、`stapler` 和 `spctl`，提前拒绝 ad-hoc 签名、签名身份不符或未通过公证/Gatekeeper 的物料。它不会生成签名、公证、staple、SLSA 或 Sigstore 物料，也不会替代 `release-bundle-check.sh`、`supply-chain-check.sh release`、DSSE payload 和 digest 绑定校验；它只是避免人工手写 report 时把 commit、digest 或路径写错，并把错误 release 物料尽早挡在 report 写入前。

每台目标机的 `release-sidecar-target-smoke` report 由 `platform/e2e/release-sidecar-target-smoke.sh` 生成。该 report 只记录单台机器的 runtime/model/audio sidecar repeatability evidence，发布负责人仍必须把所有目标机器 report 汇总到 release sidecar portability report，并确保该 report 的 `target_scope=all-target-machines`、target 列表、digest 和 smoke 状态与每个 target report 一致。单台机器 report 通过不能替代签名/公证 release bundle、DSSE/SLSA provenance、Sigstore signing bundle 或全部目标机器 sidecar portability evidence。

`platform/e2e/release-sidecar-portability-report.sh` 可把这些逐目标机器 report 聚合为 `.harness/release-inputs/supply-chain/release-sidecar-report.json`。发布负责人或 CI 必须显式声明 `MA_RELEASE_SIDECAR_EXPECTED_TARGETS`，并提供同一 commit 下每个 target 的 `MA_RELEASE_SIDECAR_TARGET_SMOKE_REPORTS`；生成器只有在 expected target 全部覆盖且无额外 target 时才写出 `target_scope=all-target-machines`，否则写出 `target_scope=incomplete-target-set` 并失败。该聚合 report 仍只是 release supply-chain 输入之一，不能替代 release bundle、provenance 或 signature report。

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
