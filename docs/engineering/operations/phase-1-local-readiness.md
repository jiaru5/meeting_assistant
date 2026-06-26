# Phase 1 本地运行准备

本文档描述 `meeting_assistant` 个人本地 MVP 的运行准备边界。Phase 1 不包含远程生产服务、组织账号、云同步、集中式数据存储或团队值班面。

## 威胁模型

威胁模型以 `docs/product-spec/13-security-and-compliance.md` 的 `SEC-MA-*` 和 `THREAT-MA-*` 为准。Phase 1 的高风险面是本地 macOS 权限、本地 workspace、人工外部复制、依赖供应链和 AI 标签误用。

## SLO

Phase 1 没有远程生产服务或多用户可用性承诺，因此 SLO 和 error budget 不适用。团队共享、云服务或对外分发进入范围前必须重新定义 SLI、SLO、统计窗口、错误预算和告警策略。

## 运行手册

Phase 1 的运行操作限定为本地启动、依赖检查、骨架门禁和用户本地文件管理。真实录制、转写和 speaker labeling 只能在 project 模式后按 product-spec 实现。

## 回滚计划

activation skeleton 不产生业务数据。回滚方式是移除或禁用对应 skeleton、manifest 注册和本地生成物。project 模式后的业务数据回滚必须在对应纵切中补充。

## 备份和恢复计划

Phase 1 MVP 不提供应用级备份或云同步。会议数据默认位于用户本地 workspace，删除语义以 `07-data-and-events.md` 和 `13-security-and-compliance.md` 为准。

## 事故响应

Phase 1 没有服务端 on-call。安全或数据问题的处理路径是停止本地处理、保留本地日志摘要、检查 workspace 和依赖来源，并在后续 spec-change 中补充长期控制。

## 数据分类

数据分类以 `docs/product-spec/13-security-and-compliance.md` 的 `DATA-MA-*` 为准。会议视频、音频、transcript 和 speaker labels 默认视为 confidential by default。
