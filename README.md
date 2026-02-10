# Intelli Note AI Notes Hub

![Intelli Note Logo](client/assets/logo.png)

> `Intelli Note` 是一个基于 RAG 的智能笔记助手：导入文档后可检索、溯源并与远程 LLM 进行上下文问答。

## 项目简介 (Introduction)
Intelli Note 将本地文档索引为可检索知识库，并通过 FastAPI + LlamaIndex + DashScope 提供带引用来源的 AI 对话能力。

## 核心功能 (Key Features)
- ✨ 智能分类：上传文档后自动生成 Emoji 分类标签。
- 🔍 语义检索：基于向量检索召回相关 chunk，支持跨文档问答。
- 🔗 引用溯源：回答附带来源片段与分数，便于核验。
- ⚡ 流式输出：SSE 逐段返回回答，前端实时渲染。
- 🧱 去重与缓存：文件哈希去重 + chunk embedding 缓存，降低重复计算与成本。
- 🛡️ 网络兜底：代理/直连切换与重试策略，提升复杂网络环境可用性。

## 技术栈 (Tech Stack)
- 📱 Client: Flutter (Windows/Mobile), Provider, flutter_markdown
- 🧠 Server: FastAPI, LlamaIndex (RAG), SQLAlchemy, Celery
- 🗃️ Storage/Queue: Redis, SQLite, 本地向量索引
- 🤖 LLM/Embedding: DashScope (Qwen)

## 核心数据模型
- `Document`: 文档实例（所属 notebook、文件哈希、状态、emoji）
- `Artifact`: 内容寻址文件实体（SHA256、大小、存储路径）
- `ChunkCache`: 文本块 embedding 缓存（按 text hash）

## 快速开始 (Quick Start)
### 1. 启动 Server
```bash
cd server
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
python manage.py
```

### 2. 启动 Client
```bash
cd client
flutter pub get
flutter run -d windows
```

## 目录说明
- `client/`: Flutter 前端
- `server/`: FastAPI + Celery + RAG 后端
- `server/app/templates/`: Prompt 模板
- `server/tests/`: 后端测试

## 许可证 (License)
Apache 2.0（见 `LICENSE`）。
