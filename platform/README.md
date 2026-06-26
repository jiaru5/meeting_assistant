# 平台工作区

本目录用于放置 platform 层组件、非业务 smoke E2E 和后续本地基础设施配置。

当前已注册组件和 E2E 入口以 `harness/project-manifest.json` 为准；本文件只说明本目录的组织规则。现有目录角色：

1. `native-app/`：非业务 skeleton，只承载未来原生 macOS app/helper 的结构和门禁边界。
2. `processing-cli/`：非业务 skeleton，只承载未来本地处理、dependency-check 和 adapter 的结构和门禁边界。
3. `e2e/`：非业务 smoke E2E 计划和 manifest 接线检查。
4. `infra/`：后续本地基础设施、部署清单和可观测性配置。

规则：

1. 不要在本目录放置 secret。
2. 本地开发依赖保持 Docker based。
3. skeleton 只证明结构和门禁接线；不得把 skeleton smoke 当作真实录制、媒体处理、转写、speaker labeling 或导出能力的产品验证。
4. 在本目录新增真实产品行为时，先对齐对应 product-spec 主责分卷、`AC-MA-*`、`PV-MA-*`、组件测试和 manifest 命令。
5. 新增平台约定时，同步更新 `docs/engineering/08-service-standards.md` 和相关 manifest/validation matrix。
