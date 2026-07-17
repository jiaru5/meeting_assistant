# 3. 测试策略

本文件定义测试分层、测试数据规则和验收标准到测试类型的映射。产品级覆盖状态见 `06-product-validation-matrix.md`。

## 测试分层

| 层级 | 工具 | 覆盖重点 |
|---|---|---|
| 后端单元测试 | JUnit 5 或等价工具 | 领域规则、状态机、权限判断、计算函数 |
| 后端集成测试 | Spring Boot Test、Testcontainers、PostgreSQL | repository、事务、migration、权限、API 行为 |
| API 合约测试 | MockMvc、OpenAPI validator 或 Pact | 路径、状态码、request/response schema、错误响应 |
| 消息契约测试 | AsyncAPI、schema registry mock 或 contract tests | 事件 schema、幂等、消费者兼容性 |
| 前端组件测试 | Vitest、React Testing Library | 表格、筛选、空状态、权限状态、表单校验 |
| Mocked E2E | Playwright | 前端路由、布局、权限态和关键交互回归 |
| Full-stack E2E | Playwright、Docker Compose | 真实 frontend/backend/database 用户路径和 API 集成 |
| Docker 构建测试 | Docker Build、Docker Compose | 镜像可构建、容器可启动、健康检查可通过 |
| 可观测性测试 | integration tests、log assertions | request id、metrics、traces、健康检查 |
| 架构结构测试 | ArchUnit、dependency-cruiser 或等价工具 | 层级依赖、跨域访问、禁止边 |
| Harness 自测试 | Python unittest、shell | 生命周期、清单、权限、fail-closed |
| Adoption 生命周期测试 | Python unittest、shell | 初始需求空缺、假设未确认、readiness blocker、无确认激活、project 切换回滚 |
| 安全测试 | SAST、SCA、secret、IaC/container scan、DAST | 漏洞和供应链风险 |

## Meeting Assistant 测试分层

Phase 1 是本地 macOS 工具，不以 Web 前端、远程 HTTP API 或数据库作为默认纵切。当前项目的测试映射是：

| 层级 | 工具 | 覆盖重点 |
|---|---|---|
| Processing CLI 单元测试 | Python unittest 或后续等价工具 | 本地命令响应、错误码、dependency-check、artifact contract、adapter fake |
| 本地命令契约测试 | JSON schema/assertions | `CMD-MA-*` 输入、输出、错误 code 和 fail-fast 行为 |
| Native app 状态测试 | Swift Testing | Swift/SwiftUI view model、权限/依赖状态、录制状态转换 |
| Native UI smoke | XCUITest | 开始/停止、权限缺失、录制中、失败/降级、导出入口和 accessible locator |
| Native designed shell regression | Swift Testing、XCUITest、可选截图证据 | Preflight、recording、artifacts、processing、transcript、export/delete 的设计化 shell 导航、状态层级、主操作触发和 Debug/Release fixture 隔离 |
| Native task experience regression | Swift Testing、app-bundle XCUITest、可访问性检查、辅助截图和结构化人工体验记录 | Meetings/New recording/Meeting detail/Diagnostics 的任务路由、单一上下文主操作、current-session 一致性、最近会议重开、失败恢复、删除 reset，以及首次/回访用户主路径 |
| 本地文件契约测试 | Python/Swift 测试 | `session.json`、artifact registry、原始媒体保护、派生产物重试 |
| Smoke E2E | manifest 驱动脚本 | `native-app` + `processing-cli` + workspace fixture 的受控端到端路径 |

Playwright 只在后续引入 Web UI 时作为 Web mocked/full-stack E2E 工具；当前 native macOS UI 自动化优先使用 Swift Testing 和 XCUITest。

MVP.1 `PV-MA-014` 的自动化关闭条件不能继续使用“六个 section 和所有按钮同时存在”的旧控制面断言。Swift Testing 必须覆盖任务路由、current-session 不变量、处理 eligibility、最近会议 projection 和删除 reset；app-bundle XCUITest 必须覆盖首次用户主链、回访用户重开和至少一个 blocked/failed 恢复链。关键状态截图只用于视觉层级审查，不能替代任务断言。3-5 名代表性本地 Mac 用户的无指导任务测试作为补充人工体验证据，记录完成、求助、误点、犹豫和状态理解；agent、XCUITest 或截图不得冒充真人研究结论。

真人体验记录使用 `./scripts/mvp1-experience-study.py` 的 `init`、`validate` 和 `report` 入口；validate/report 默认绑定当前 HEAD，历史研究必须显式 `--allow-historical-subject` 且不能用于关闭当前 `PV-MA-014`。工具只验证 3–5 份匿名参与者记录、人工 attestation 字段、三类任务字段和 finding 状态；open P0/P1 阻断，closed P0/P1 必须有 resolution 与 passed 人工复测。工具不能独立证明参与者真人身份，不设置未确认的易用性阈值，也不把结构有效误写为产品验收通过。

`DesignedNativeShellAppBundleTests` 是 MVP.1 任务级 app-bundle suite，至少覆盖录制/处理 readiness 解耦、麦克风意图权限、ready/blocked preflight、recording、saved/degraded、provider-preflight 一致的音频完整性检查与音频源优先级、processing 进行中、同源 processing failed/retry、停止保存失败重试、历史 `processing` 恢复、已登记 transcript 的 repair-only load failure/reload、长 transcript 固定操作栏、历史重开和删除 reset。provider 已登记但校验失败的输入不得降级为虚假可用 fallback；已登记但缺失、漂移或不可解码的 transcript 不得重新显示 Generate。suite 为 Meetings 空/非空、New recording、Recording live、Saved、Processing、Transcript 和 Diagnostics 关键状态附加保留截图；截图只在 test body 实际执行后才构成证据。可用 `MA_NATIVE_APP_TASK_XCUITEST=1 ./platform/native-app/scripts/test-app-bundle.sh` 单独运行；该入口必须以无残留窗口的同 inode owner lock 锁定共享 DerivedData，使用与当前输入 fingerprint 一致的 `.xctestrun`，保存每次 attempt 的唯一 xcresult，并冻结与当前 HEAD 完全一致的 verifier 只读快照；capture 与 final verify 必须由一次读取、核对预存 SHA-256 并执行同一 bytes 的 loader 驱动，测试前 binding 也必须保存字节级 SHA-256 并在结束后从同一份 bytes 计算摘要和解析 JSON。随后 `mvp1-task-xcresult.py` 在测试前后证明 HEAD/fingerprint、`.xctestrun`、实际 app/runner/test bundle 的严格 codesign/CDHash 和 executable SHA-256 稳定，当前源码精确 17 条 task case 全部 Passed、0 failed/skipped/expected failure，retained xcresult content manifest 非空且稳定，以及 `00-meetings-recent` 至 `07-diagnostics` 八张 PNG 能通过结构、CRC 和系统完整解码。任何 xcodebuild 非零退出都必须由 wrapper 保留原始退出码；final xcresult 已存在时还必须使 verifier report `passed=false`，在 xcresult 产生前失败则只保留 log/退出码。截图导出、SHA-256 与结构/解码有效只说明可进入视觉评审，不能把 `screenshot_visual_review=pending` 写作视觉审查通过。默认组件 fast gate 继续只编译并运行 Swift/hosted 测试，不因缺少 UI automation 环境而失败。

八张截图的人工视觉审查使用 `mvp1-screenshot-visual-review.py` 建立独立、私有且 no-clobber 的记录：它必须重新绑定当前提交、仍为 `screenshot_visual_review=pending` 的成功 17/17 task report bytes 与八张规定 PNG 的 SHA-256，真人才可补充逐图 pass/fail observation 和 attestation。report/PNG 从同一 `O_NOFOLLOW`/`O_NONBLOCK`/`fstat` file descriptor 读取、解析和摘要，strict task validator 直接消费同一 report bytes；测试必须覆盖这条 same-bytes binding、FIFO fail-closed 与显式 agent/automation/XCTest 自声明阻断。每张失败截图都必须被 finding 引用；open P0/P1 阻断，closed P0/P1 必须有 resolution 和通过的真人复测。该工具可检验记录的完整性和人工声明，不能独立证明观察者身份；`ready_for_review`、报告结构有效、agent、自动化、XCUITest 或截图文件本身都不代表视觉验收、产品验收或 release readiness。

真实 task evidence 的 Python launcher/runtime、构建、测试、xcresult 读取、codesign、Git 和图片解码工具必须来自 Apple-anchor 校验后的固定系统工具链，并在测试前 binding 与最终 report 中记录调用 path、resolved path 与 SHA-256；环境变量或 `PATH` 替身必须 fail closed。所有证据关键 Python 调用和四个 MVP.1 证据脚本的直接 executable 入口必须使用 `/usr/bin/python3 -I -S`，忽略 `PYTHONHOME`、`PYTHONPATH`、user-site 与 `sitecustomize`；负向测试必须证明这些注入不能在哈希、冻结、same-bytes loader 或工具入口前执行。wrapper 与 verifier 的 Git 调用必须在最小环境下执行并清除外部 repo/worktree/index/object 重定向，哈希不得依赖 `PATH` 中的 `shasum`。单元测试替身只能通过显式 fixture 模式运行，fixture report 无论逻辑检查结果如何都必须保持 `passed=false`。后续 VoiceOver/键盘工具还要重新核对 task report 与 binding 保存的是当前同一 trusted toolchain。

accessibility identifier 和 SwiftUI source-contract 测试只证明 locator 与结构没有回退，不能替代 VoiceOver 在真实 app、真实窗口和键盘焦点下的实机走查。实机记录使用 `./scripts/mvp1-accessibility-walkthrough.py`，初始化前必须已有同一当前 HEAD、稳定 fingerprint、17/17、八张截图和同一 app identity 的成功 task xcresult report；工具重新核对 retained xcresult manifest、xctestrun、pre-test binding、截图 SHA-256、严格 codesign 与 app executable SHA-256，再绑定当前 macOS，固定覆盖页面标题、route/session focus、录制/处理/transcript 播报、核心快捷键、selected 非纯颜色、技术详情默认隐藏 raw id、删除提示焦点与 Return 取消。人工 attestation、合成数据/privacy 声明、逐项 observation、失败 finding 和 closed P0/P1 直接人工复测缺一即 fail closed；agent、自动化、截图或 XCUITest 均不得计作该走查。

native-app 的默认组件 `test` gate 优先服务本地快速反馈：Swift Testing 覆盖 view model、契约 decode、状态机和文件边界，XCTest-hosted SwiftUI smoke 覆盖关键 locator/source contract。真实 app-bundle XCUITest 仍是 native UI 关键状态证据，但执行入口拆为显式命令 `./platform/native-app/scripts/test-app-bundle.sh`，或通过 `MA_NATIVE_APP_RUN_XCUITEST=1 ./platform/native-app/scripts/test.sh` 纳入同一次组件测试。验证矩阵和交付说明必须区分默认 fast gate 与 app-bundle UI smoke；只有运行 app-bundle 入口后，才能把 `.app` 启动、窗口定位和 `XCUIApplication()` locator 作为本轮证据。

真实 OS clipboard/save-panel 证据不进入默认 fast gate。需要证明 copy/export/delete action 穿过系统 `NSPasteboard`、`NSSavePanel` 和 process-backed `export_transcript` / `delete_session` 时，显式运行 `MA_NATIVE_APP_REAL_ACTION_OS_SMOKE=1 ./platform/native-app/scripts/test-app-bundle.sh`，并在交付中记录该命令、日志和限制；该 opt-in gate 只能作为 PV closure/release-candidate 输入，不能替代 local-direct release bundle、跨机器 UI Automation/TCC 可重复性、最终 `release-preflight`，也不能替代未来显式 developer-id 商业分发门禁。

`platform/native-app/Sources/`、`platform/native-app/Tests/`、`platform/native-app/UITests/`、`platform/processing-cli/src/`、`platform/processing-cli/tests/` 和 `platform/e2e/` 是当前产品行为和产品验证的主要代码表面。修改这些路径时，工程门禁必须要求同步检查 `06-product-validation-matrix.md`，并运行对应组件测试、架构检查和 local full-stack smoke。Local full-stack smoke 必须优先使用已缓存或预加载的本地 smoke 镜像，不得在 E2E 执行阶段隐式依赖公网 registry 拉取。

## Meeting Assistant 自动化测试前置条件

任何 `CMD-MA-*`、artifact contract、native UI 状态或 processing pipeline 的产品行为实现开始前，必须先满足以下 testability 前置条件。缺少前置条件时，只能做规范补齐、测试基础设施或 spike，不能把对应产品行为标为实现完成。

| 前置条件 | 最低要求 | 不满足时的处理 |
|---|---|---|
| 命令 schema | `06-api-contracts.md` 已定义目标命令的输入、成功响应关键字段、失败响应关键字段、错误码、unknown field fail-fast 和 exit code；测试能断言 JSON object，而不是只看 stdout 字符串 | 先补 API 契约和本地命令契约测试；相关 `PV-MA-*` 保持 `planned` 或 `partial` |
| Artifact schema | `07-data-and-events.md` 已定义 `session.json`、artifact registry、`transcript.json`、`speaker_labels.json` 或 delete summary 的最小字段和路径边界 | 先补文件契约测试和 fixture；不得通过 ad hoc 文件内容判断产品完成 |
| 确定性 fixture | 测试使用临时 workspace、受控 clock 或可断言时间格式、小型媒体 fixture、fake adapter 和固定依赖状态；不得依赖用户真实会议数据或本机常驻服务 | 先补 fixture/fake adapter；真实 runtime smoke 只能作为附加证据 |
| 本地转写 runtime smoke | VS-MA-06 使用 `runtime=whisper_cpp`、本地 `whisper.cpp` CLI 和用户人工准备的 multilingual Whisper-compatible 模型；`check_dependencies` 必须报告不含设备唯一标识的硬件 preflight；小 WAV fixture 必须包含中文为主且夹杂 `HTTP`、`LLM`、`clean architecture`、`EDA` 等英文技术词汇；不得自动下载模型或调用外部 API | runtime 或模型缺失时先覆盖 `dependency_missing`；硬件 preflight 只能证明部署适配风险，不能替代真实 mixed-language smoke；真实 runtime smoke 未能在标准门禁稳定运行前，`PV-MA-007` 保持 `partial` |
| UI locator | SwiftUI 控件和状态有 accessible name、状态文本和稳定 accessibility identifier；测试可定位权限、依赖、录制、处理、回查、导出和删除状态；设计化 shell 必须证明导航、状态层级和主操作不退回原始调试 UI | 先补 view model、locator、XCUITest/Swift Testing 和必要截图证据；不能只以人工截图作为长期证据 |
| 负向用例 | 至少覆盖 unknown field、非法 enum、缺失必填字段、权限缺失、依赖缺失、artifact 缺失、路径越界、symlink 逃逸、处理失败、导出冲突、确认缺失、no-auto-upload 和 no-auto-download | 先补负向测试；未覆盖的高风险边界必须写入验证矩阵缺口 |
| 证据入口 | `06-product-validation-matrix.md` 必须写明目标测试文件或脚本、标准命令入口、当前证据、阻塞缺口和关闭条件 | 不能只写“未来测试”；缺少目标入口时不能标 `covered`，也不应扩大产品实现范围 |

`docs/engineering/07-development-plan.md` 的 `TDG-MA-*` testability gate 是这些前置条件的执行清单。实现 agent 必须在相关 `VS-MA-*` 开始和退出时检查该清单，验证 agent 必须按验证矩阵中的目标入口确认关闭状态。

## 验收标准映射

| 规范来源 | 必须覆盖的测试 |
|---|---|
| `09-acceptance-criteria.md` 身份和权限 | 后端权限测试、API 合约测试、前端权限状态测试、E2E |
| `02-domain-model.md` 领域不变量 | 后端单元、集成、数据库约束测试 |
| `05-business-rules-and-calculations.md` | 后端单元和集成测试，必要时加前端展示测试 |
| `06-api-contracts.md` | API 合约测试、前端 API client 测试 |
| `07-data-and-events.md` | migration、repository、事件契约、消费者幂等测试 |
| `12-ui-ux-design.md` | 前端组件测试、Playwright E2E、视觉和可访问性检查 |
| `12-ui-ux-design.md` 的原生 macOS UI | Swift Testing、XCUITest、可访问性 locator 检查 |
| `12-ui-ux-design.md` 的设计化 native shell | Swift Testing、app-bundle XCUITest、locator 检查、Debug/Release hook 隔离检查和可选截图证据 |

## 高风险边界

以下情况必须有自动化测试：

1. 未登录、登录过期、无权限和跨租户访问。
2. 服务端维护字段不能由客户端写入。
3. 同租户或跨域引用校验。
4. 状态机迁移、并发冲突和幂等重试。
5. migration 从空库启动成功。
6. 异步消息重复、乱序、失败和补偿。
7. 生产 profile 不接受 dev-only 身份、默认 secret 或固定测试数据。
8. 前端关键页面的 loading、empty、error、forbidden 和 submitting 状态。
9. 架构边界、禁止依赖和跨服务数据访问。
10. Agent 权限放宽、门禁绕过、未注册组件和发布假绿灯。
11. Meeting Assistant 命令 unknown field、非法 enum、缺失必填字段和 CLI exit code。
12. Meeting Assistant workspace 路径越界、symlink 逃逸、delete session 误删和 workspace 外导出保留。
13. Meeting Assistant 外部 GPT/API、依赖下载、辅助 capture adapter 静默切换等禁止路径。

## 测试数据

1. 测试数据必须确定性生成，不依赖当前真实日期，除非测试显式控制 clock。
2. 至少准备两个租户或隔离域，用于数据隔离测试。
3. 至少准备普通用户、管理员、无权限用户和 inactive/disabled 用户。
4. E2E seed 只维护全栈路径所需的最小稳定 fixture。
5. dev seed 可以更丰富，但不得成为产品事实源。
6. 集成测试和 E2E 使用的数据库、中间件和外部依赖模拟服务必须由 Docker Compose、Testcontainers 或测试进程内 mock 提供。
7. Harness 自测试如需复制仓库作为临时 fixture，必须排除 Git 已忽略的生成构建输出（包括 `platform/*/build/`），并只在 fixture 内重建该测试显式需要的受控产物；宿主机遗留的 Xcode、Docker 或其他构建输出不得影响自测成本或结果。

## 最低测试要求

1. 修改领域模型、权限、API、事件或计算规则时，必须有后端单元、集成或契约测试。
2. 修改页面、表单、筛选、表格列时，必须有前端组件测试；关键路径加 Playwright E2E。
3. 修改 Docker 或启动流程时，必须验证镜像构建和 Compose 启动。
4. 修改 migration 或数据库启动流程时，必须运行 `./scripts/db-migration-check.sh`。
5. 修改生产 profile、secret 或 env 示例时，必须运行 `./scripts/prod-config-check.sh`。
6. 修复 bug 时，优先补能失败的回归测试，再修复。
7. 新增或修改产品行为时，必须同步检查 `06-product-validation-matrix.md`。
8. 新增组件时，必须先注册 `harness/project-manifest.json` 并提供架构测试。
9. 修改 Harness 生命周期、安全策略或发布门禁时，必须补 `scripts/tests/` 的失败路径测试。
10. 发布候选的 full-stack E2E 必须实际启动 Compose 服务并等待健康检查，不能只执行 `docker compose config`。
11. 修改 adoption 流程、启动脚本、readiness 规则或 project activation 时，必须补 `scripts/tests/` 的失败路径测试，并运行 `./scripts/adoption-check.sh`。
12. 修改 `processing-cli` 命令契约、dependency-check 或 artifact contract 时，必须补本地命令契约测试，并更新 `06-product-validation-matrix.md`。
13. 修改 `native-app` SwiftUI 状态、权限提示或录制控制时，必须补 Swift Testing；关键用户状态补 XCUITest 或说明短期 manual-evidence。
