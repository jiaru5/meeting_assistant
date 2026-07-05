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

Processing CLI release provider smoke 必须对模型 sidecar fail closed：模型 sha256 配置或 sidecar 不匹配实际模型时失败，JSON provenance sidecar 不可解析时失败，hash/license/provenance sidecar 解析后不位于 `~/.local/share/ai-models/whisper.cpp/` 模型根目录时失败。该规则只约束当前本机 release-provider evidence，不等同于完整 SCA、签名、公证或所有开发机 provenance 覆盖。

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
