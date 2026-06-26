# 后端工作区

后端微服务放在 `backend/services/` 下，稳定共享基础设施库放在 `backend/libs/` 下。

推荐服务结构：

```text
backend/services/<service-name>/
├── pom.xml
├── Dockerfile
├── src/main/java/
├── src/main/resources/db/migration/
└── src/test/
```

创建服务骨架前，先阅读 `docs/engineering/01-repo-structure.md`、`docs/engineering/08-service-standards.md` 和 `docs/product-spec/08-implementation-guidance.md`。
