# IntelliNote

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
- Sources 导入（粘贴文本、导入 TXT/MD）。
- 入库流水线（文本清洗、切分、伪向量化、检索）。
- Chat 问答（基于检索结果生成带引用回答）。
- Studio 学习室（生成学习指南与测验并保存到 Notes）。
