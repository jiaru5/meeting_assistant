# Local E2E Smoke

本目录提供 manifest 驱动的本地 full-stack/E2E smoke。E2E 注册状态以 `harness/project-manifest.json` 为准。

当前 `smoke-test.sh` 覆盖 P2-C / VS-MA-11 的 deterministic processing local smoke：使用临时 workspace 和脚本内生成的 WAV fixture，通过公开 `processing-cli` JSON/exit code 边界串联 `import_media -> generate_transcript` 内部 normalized audio/source selection -> `generate_speaker_labels -> export_transcript -> delete_session`。

该 smoke 覆盖每步 JSON response、exit code、关键 artifact、`session.json` 变化、原始媒体 checksum、用户显式 export target、confirm=false 失败、workspace 外 export 保留和 workspace 级 `meeting_session.deleted.v1` 删除事件。命令 schema 负向、损坏 `session.json`、session lock、导出 metadata 写失败清理、speaker labels 复用再校验、artifact symlink/hardlink fail-closed 等回归由 `platform/processing-cli/scripts/test.sh` 下的组件测试覆盖。它不调用真实 speaker runtime、不上传/下载外部内容，也不依赖真实会议数据或宿主机常驻服务。

`prepare-smoke-image.sh` 只复用本机已缓存的允许基础镜像并打成本地 smoke tag；它不会在 E2E 执行阶段从外部 registry 拉取镜像。没有可用缓存时，标准 E2E 应明确失败并提示预加载镜像。
