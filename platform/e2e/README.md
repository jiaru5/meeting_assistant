# Local E2E Smoke

本目录只提供非业务 full-stack/E2E smoke 计划。E2E 注册状态以 `harness/project-manifest.json` 为准。

当前 smoke 只验证已注册 skeleton、manifest 和门禁入口存在，不验证真实录制、转写、speaker labeling 或导出能力。

`prepare-smoke-image.sh` 只复用本机已缓存的允许基础镜像并打成本地 smoke tag；它不会在 E2E 执行阶段从外部 registry 拉取镜像。没有可用缓存时，标准 E2E 应明确失败并提示预加载镜像。
