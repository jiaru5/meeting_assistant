# 10. 安全和供应链

本文件定义安全开发、依赖治理、CI/CD、制品完整性和漏洞响应的工程规则。项目安全需求和威胁事实由 `docs/product-spec/13-security-and-compliance.md` 维护。

## 安全开发基线

1. adoption 阶段必须确定适用的 OWASP ASVS 5.0 等级、数据分类和合规约束。
2. 认证、授权、租户隔离、密码学、文件处理和外部输入必须有负向测试。
3. Agent 生成的代码与人工代码执行相同的 review、测试、SAST、SCA 和发布门禁。
4. 禁止关闭框架安全保护、TLS 校验、反序列化保护或类型检查来绕过失败。
5. 复杂安全逻辑必须使用成熟库，并记录版本、配置和验证证据。

## 自动化门禁

`./scripts/security-check.sh` 必须：

1. 验证 agent 权限策略和项目清单。
2. 检查高置信度 secret 或私钥泄露。
3. 执行每个注册组件的 `security` 命令。
4. 验证 GitHub Actions 固定到完整 commit SHA。

真实项目的组件 `security` 命令至少覆盖：

1. SAST。
2. 依赖漏洞和许可证策略。
3. secret scanning。
4. IaC 和容器配置扫描。
5. 高风险 Web/API 系统的 DAST 或等价动态验证。

## 依赖与构建

1. 依赖必须使用 lockfile 或 Maven dependency management 固定解析结果。
2. 新依赖必须说明用途、维护状态、许可证和替代方案。
3. 禁止使用来源不明、拼写近似或由 Agent 猜测出来的包名。
4. CI 外部 Action 必须固定完整 commit SHA。
5. 生产 Docker 基础镜像必须固定 digest，并以非 root 用户运行。
6. release 组件必须生成 CycloneDX JSON 或项目明确选择的等价 SBOM。

Meeting Assistant 当前 native app 和 processing CLI 的 `Dockerfile` 是 release gate 用的最小 validation image：只验证 digest-pinned base、非 root `USER`、组件元数据和 SBOM 文件存在，不代表 macOS app 已具备团队分发包、真实 capture 发布物或生产服务镜像。产品发布可用性仍以 `06-product-validation-matrix.md` 中 `PV-MA-*` 是否达到 `covered` 为准。

当前 native app 和 processing CLI 组件 SBOM 必须显式声明 first-party application 的 `Apache-2.0` license evidence、`packaged-third-party-runtime-components=none` 和 `release-gate-image=validation-only`。这些字段只证明当前 validation image 没有打包第三方 runtime component，并且 SBOM gate 会在许可证或范围声明退化时 fail closed；不等同于完整 release-scope SCA、provenance、签名、公证或模型 sidecar 放行。

当前 native app 和 processing CLI 组件 `sbom` gate 必须生成本次运行的 `supply-chain/supply-chain-report.json`，并由仓库级 `./scripts/supply-chain-check.sh current` 聚合校验。报告必须绑定 manifest component id，声明 `release_gate=validation-only`、CycloneDX JSON SBOM、first-party `Apache-2.0` license、SCA dependency review、license review、无 packaged third-party runtime component、不打包 runtime/model、不自动下载、validation-only provenance scope、未生成 release provenance attestation 且 findings 为空；仓库级入口必须先删除旧报告，避免组件脚本只退出 0 或复用 stale report 造成供应链假绿。该报告仍只是 current/check scope 的机器可审查证据，不等同于完整 release-scope SCA/license/provenance、签名、公证、release bundle 或 release readiness。

`./scripts/supply-chain-check.sh release` 必须在上述组件 SBOM/report 聚合之外，额外校验 release bundle/provenance/signing/sidecar evidence report。默认路径是 `.harness/release-inputs/bundle/release-bundle-report.json`、`.harness/release-inputs/supply-chain/release-provenance-report.json`、`.harness/release-inputs/supply-chain/release-signature-report.json` 和 `.harness/release-inputs/supply-chain/release-sidecar-report.json`；CI 或人工 release rehearsal 可通过 `MEETING_ASSISTANT_RELEASE_BUNDLE_REPORT`、`MEETING_ASSISTANT_RELEASE_PROVENANCE_REPORT`、`MEETING_ASSISTANT_RELEASE_SIGNATURE_REPORT` 和 `MEETING_ASSISTANT_RELEASE_SIDECAR_REPORT` 指向实际产物。bundle report 必须声明当前 commit、`release_gate=release-bundle`、Release zip archive、`MeetingAssistantNative.app` 和 `sha256:` bundle digest；provenance report 必须声明 manifest 中的 `provenance_target`、`sbom_format`、当前 commit、builder、source repository、`release_provenance_attestation=produced`，且 artifact 列表必须包含与 bundle report 同一 digest、名称匹配 release zip 或 `.app` 的 artifact；signature report 必须声明 manifest 中的 `artifact_signing`、当前 commit、`signing_status=signed`、verifier，且 signed artifact 必须包含同一 bundle digest；sidecar report 必须绑定当前 commit，声明 `release_gate=release-sidecar-portability`、`target_scope=all-target-machines`、不打包 runtime/model、不自动下载、不访问外网，并为每个目标机器记录 `.local` 下 runtime、model、mixed-language smoke audio fixture 的 digest/source 以及 `check_dependencies`、`whisper.cpp` smoke 和 no-auto-download 通过状态。缺少这些 report 或 provenance/signature 指向不同 artifact digest 时 release 阶段必须 fail closed，不能把 validation-only SBOM、本机 provider smoke、单机 sidecar 证据或漂移的 SLSA/signing report 当作发布放行证据。

`./scripts/release-bundle-check.sh` 是 release artifact guard，必须先证明存在签名、公证、staple、digest 和当前 commit 绑定的 `MeetingAssistantNative.app` Release zip archive，且该 bundle 不打包 runtime/model、不自动下载、不包含会议数据。该 gate 必须解压 archive 并对 `MeetingAssistantNative.app` 运行 `codesign --verify --deep --strict`、`codesign -dv`、`xcrun stapler validate` 和 `spctl -a -t exec`；JSON report 只能提供输入索引和期望字段，不能替代制品本体校验。该 gate 与 `supply-chain-check.sh release` 互补：bundle report 证明分发制品本身，supply-chain release gate 会用同一 bundle digest 约束 provenance/signing report，sidecar report 证明目标机器 runtime/model/audio 取证可重复；三者不能相互替代，也不能互相指向不同 release artifact。

当前 native app 和 processing CLI 组件 `security` gate 必须生成本次运行的 `security/security-report.json`，并由仓库级 `./scripts/security-check.sh` 聚合校验。报告必须绑定 manifest component id，声明 `release_gate=validation-only`、SAST 静态扫描、SCA 依赖审查、secret scan、禁止网络/安装扫描、no-auto-download、未打包 runtime/model、无外部网络访问且 findings 为空；仓库级入口必须先删除旧报告，避免组件脚本只退出 0 或复用 stale report 造成假绿。该报告仍只是 current/check scope 的机器可审查证据，不等同于完整 release-scope SAST/SCA、签名、公证、provenance 或 release readiness。

Processing CLI release provider smoke 是 `VS-MA-22` 的 provider 安全与供应链证据，不是 `VS-MA-23` release candidate 放行证据。该 smoke 必须对模型 sidecar 和本机共享资产边界 fail closed：模型 sha256 配置或 sidecar 不匹配实际模型时失败，JSON provenance sidecar 不可解析时失败，hash/license/provenance sidecar 解析后不位于 `~/.local/share/ai-models/whisper.cpp/` 模型根目录时失败；runtime、模型和 mixed-language audio fixture 不在 `~/.local` 允许根目录或落在仓库、`Downloads`、`Desktop`、`Library/Caches` 等禁止根目录时也必须失败；English-only `.en` 模型不得作为 mixed-language evidence。该规则只约束当前本机 release-provider evidence，不等同于完整 SCA、签名、公证、release bundle 或所有开发机 provenance 覆盖。

`platform/e2e/release-security-supply-chain-smoke.sh` 是 `VS-MA-22` 的 release-scope evidence 聚合入口，不是 `VS-MA-23` release candidate 放行证据。该 wrapper 必须运行仓库级 `security-check`、`supply-chain-check current` 和 processing release-provider smoke，并由 `release_security_supply_chain_report.py` 校验 production component security/supply-chain reports 与 release-provider marker 后输出 `release_gate=release-scope-security-supply-chain` report。该 report 必须继续声明 `not_release_readiness=true`，因为当前仍未生成签名/公证分发包、SLSA/release provenance attestation、release sidecar portability report，也不能证明所有开发机 runtime/model/audio sidecar、真实 ScreenCaptureKit 或发布范围 `PV-MA-*` 全部 covered。

## Meeting Assistant MVP 依赖策略

`meeting_assistant` Phase 1 采用允许来源 + 人工安装策略：

1. bootstrap/check 脚本只检查和提示，不自动下载模型、二进制、驱动或外部脚本。
2. 允许来源包括 Apple 官方 Xcode/Command Line Tools、官方或维护良好的开源项目发布源、用户已有本地 Whisper 模型路径，以及后续经 ADR 批准的来源；Qwen 或其他会议纪要模型只有在 `OD-MA-009` 关闭并完成 spec-change 后才能进入应用依赖范围。
3. Agent 不得自行放宽 `harness/agent-policy.json`、网络 allowlist、CI 安全门禁或外部写权限来获取依赖。
4. 版本/hash 锁定、许可证自动门禁和依赖签名验证作为后续增强；在真实 dependency-check 实现前至少必须有允许来源说明和人工安装边界。
5. 如果后续需要自动下载依赖、模型或二进制，必须先更新本分卷、`13-security-and-compliance.md`、`harness/agent-policy.json` 和 ADR。
6. VS-MA-06 的首个真实 transcription runtime 为本地 `whisper.cpp` CLI：`MEETING_ASSISTANT_TRANSCRIPTION_RUNTIME` 只能指向本地可执行文件或可解析命令名，`MEETING_ASSISTANT_TRANSCRIPTION_MODEL` 只能指向用户人工准备的本地 multilingual Whisper-compatible 模型文件。
7. English-only `.en` Whisper 模型不能作为 `PV-MA-007` covered 证据；真实 smoke 必须覆盖中文为主且夹杂英文技术词汇的会议音频，并记录 no-auto-download 证据。
8. `check_dependencies` 的 transcription hardware preflight 只能输出 CPU 架构、芯片名称和内存等级等非敏感摘要，不得输出序列号、硬件 UUID 或 Provisioning UDID；该 preflight 只用于部署风险判断，不能替代模型 provenance、license/hash 审查或真实 runtime smoke。
9. 用户级共享资产目录固定为 `~/.local/opt/whisper.cpp/`、`~/.local/bin/whisper-cli`、`~/.local/share/ai-models/whisper.cpp/` 和 `~/.local/share/ai-fixtures/asr/zh-en-tech/`。项目脚本可以检查并提示这些位置，但不得自动下载、自动复制模型、自动创建 runtime symlink 或把大型模型提交到仓库。
10. Native real runtime smoke 只能通过 Debug/XCTest-only `MA_NATIVE_APP_REAL_RUNTIME_SMOKE=1` 或 Swift Testing-only `MA_NATIVE_REAL_RUNTIME_BRIDGE_SMOKE=1` 显式开启，并且只能把用户已配置的 runtime/model/audio 路径透传给 provider-owned CLI；生产/default app 和组件测试都不能因此自动选择 runtime、自动发现模型、自动下载、自动复制共享资产或把模型/音频 fixture 纳入仓库制品。

## 制品和来源

生产发布目标：

1. 构建在受控 CI 环境执行，不以开发者本地制品发布。
2. 生成至少达到 SLSA Build L2 目标的 provenance。
3. 使用 OIDC keyless signing 或组织批准的密钥系统签名制品。
4. 部署前验证 digest、签名和 provenance。
5. release tag、commit、镜像 digest、SBOM 和部署记录可相互追溯。

## 漏洞响应

1. 仓库必须提供私密漏洞报告渠道。
2. 漏洞按严重度、可利用性和资产影响分级，并设置修复 SLA。
3. 修复必须包含回归测试和受影响版本分析。
4. 重复问题必须更新安全规范、Agent 规则、共享库或自动化门禁。
5. 风险接受必须有 owner、到期日期和补偿控制。

## 标准入口

```bash
./scripts/security-check.sh
./scripts/supply-chain-check.sh current
./scripts/supply-chain-check.sh release
```
