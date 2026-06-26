# 平台工作区

本目录用于放置 platform 层组件、activation smoke E2E 和后续本地基础设施配置。

当前 adoption 阶段允许存在的内容：

1. `native-app/`：`native-app` 非业务 activation skeleton，只承载未来原生 macOS app/helper 的结构和门禁边界。
2. `processing-cli/`：`processing-cli` 非业务 activation skeleton，只承载未来本地处理、dependency-check 和 adapter 的结构和门禁边界。
3. `e2e/`：activation smoke E2E 计划和 manifest 接线检查。
4. `infra/`：后续本地基础设施、部署清单和可观测性配置。

规则：

1. 不要在本目录放置 secret。
2. 本地开发依赖保持 Docker based。
3. adoption 模式不得在本目录实现真实录制、媒体处理、转写、speaker labeling、外部模型调用或自动依赖下载。
4. 新增平台约定时，同步更新 `docs/engineering/08-service-standards.md` 和相关 manifest/validation matrix。
