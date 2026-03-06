# Intelli Note

![Intelli Note Logo](assets/logo.png)

基于 LLM 的 AI 知识库管理 APP，用于学习过程中提供 AI 辅助学习功能，优化学习知识点的 workflow。

## 本地运行

1. 安装 Flutter SDK。
2. 获取依赖并运行：

```bash
flutter pub get
flutter run
```

## 功能概览

- Notebook 管理（创建/重命名/删除）。
- Sources 导入（粘贴文本、导入 TXT/MD/PDF）。
- 入库流水线（文本清洗、切分、伪向量化、检索）。
- Chat 问答（基于检索结果生成带引用回答）。
- Studio 学习室（生成学习指南与测验并保存到 Notes）。


## Android 部署说明（重构后）

- Android 端默认不再依赖本地 Server 进程。
- 请在应用「设置 -> 网络与部署」中配置云端 API Base URL（例如 `https://your-domain/api/v1`）。
- Windows 端架构保持不变，仍可使用本地 FastAPI/Celery/Redis 工作流。
- Notebook 页面在宽屏（横屏/平板）下会自动切换为 NavigationRail 布局。
- Android 云网关相关功能已完成四个 Codex 版本改动合并收口。
