# Intelli Note AI Notes Hub

![Intelli Note Logo](client/assets/logo.png)

> 基于 RAG 的智能笔记助手：导入资料后自动索引、可追溯问答、支持 PDF 混合解析（文本/OCR/Vision）。

## 项目简介

Intelli Note 是一个本地知识库 + 远程大模型问答系统，采用 `Flutter + FastAPI + LlamaIndex + Celery + Redis` 架构。  
系统围绕“可检索、可追溯、可观测”设计，面向技术文档与论文学习场景做了专项优化。

## 核心能力

- 智能入库：上传 `TXT/MD/PDF` 后自动入队、解析、切分、向量化、持久化。
- 文档去重：基于文件哈希（CAS）防止重复导入。
- 语义检索：按 notebook 隔离索引，支持跨来源召回。
- 引用溯源：回答附带引用片段、分数、页码（PDF）。
- 流式对话：SSE 实时返回，前端逐段渲染。
- PDF 混合解析：
  - 文本型 PDF：文本层提取 + 图像语义理解（Vision）。
  - 扫描版 PDF：OCR 提取文本 + Vision 图像理解。
  - 多栏重排：按文本块列聚类优化阅读顺序，降低双栏串栏问题。
- 可观测性：Sources 卡片显示解析统计（总页/文本/OCR/Vision/跳过）。
- 服务编排：`manage.py` 支持前台联动和后台守护两种模式。

## 技术栈

- Client: Flutter, Provider, `flutter_markdown`, `flutter_math_fork`
- Server: FastAPI, SQLAlchemy, LlamaIndex, Celery
- Storage: SQLite, Redis, 本地向量索引
- Model Provider: DashScope (Qwen 系列)

## 核心数据模型

- `Document`: 文档实例（所属 notebook、文件哈希、状态、emoji）。
- `Artifact`: 内容寻址文件实体（`sha256 -> storage_path`）。
- `ChunkCache`: 文本块 embedding 缓存（按 `text_hash + model_name`）。

## 快速开始

### 1) 启动 Server

```bash
cd server
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
python manage.py
```

说明：
- `python manage.py`：前台联动模式（同一终端看 Redis/Worker/API 日志）。
- 按 `Ctrl+C` 可联动停止本次前台启动的服务。

### 2) 启动 Client

```bash
cd client
flutter pub get
flutter run -d windows
```

## 服务管理命令

- 前台联动启动：`cd server && venv\Scripts\python manage.py`
- 后台守护启动：`cd server && venv\Scripts\python manage.py up`
- 查看状态：`cd server && venv\Scripts\python manage.py status`
- 健康检查：`cd server && venv\Scripts\python manage.py health`
- 停止后台服务：`cd server && venv\Scripts\python manage.py down`
- 重启后台服务：`cd server && venv\Scripts\python manage.py restart`

健康检查接口：
- `GET http://127.0.0.1:8000/health`
- 返回项包含 `redis`、`worker`、`llm_config`。

## 环境变量（.env）

最小建议配置（`server/.env`）：

```env
DASHSCOPE_LLM_API_KEY=your_llm_key
DASHSCOPE_EMBED_API_KEY=your_embed_key
LLM_MODEL_NAME=qwen3-32b
EMBED_MODEL_NAME=text-embedding-v4

# 网络（按需）
HTTP_PROXY=socks5h://127.0.0.1:26001
HTTPS_PROXY=socks5h://127.0.0.1:26001
DASHSCOPE_FORCE_NO_PROXY=0

# Chat
DASHSCOPE_CHAT_TIMEOUT_SECONDS=90

# PDF 混合解析
PDF_OCR_ENABLED=true
PDF_VISION_ENABLED=true
PDF_VISION_INCLUDE_TEXT_PAGES=true
PDF_VISION_MIN_IMAGE_RATIO=0.04
```

## 常见问题

- `port 8000 already in use`：
  - 说明已有 API 在跑，先执行 `python manage.py status` 检查。
  - 如需前台联动模式，先 `python manage.py down` 再 `python manage.py`。
- 报 `No API key found for OpenAI`：
  - 实际通常是 DashScope key 没被读取到（例如 `.env` 编码异常/BOM）。
  - 先确认 `DASHSCOPE_LLM_API_KEY`、`DASHSCOPE_EMBED_API_KEY` 存在且可读。
- PDF 显示 `OCR=0`：
  - 文本型 PDF 正常可能为 0；如果 `Vision图` 大于 0，说明图像语义识别已生效。

## 测试与质量检查

Server:

```bash
cd server
venv\Scripts\python -m pytest -q
```

Client:

```bash
cd client
flutter analyze --no-pub
flutter test --no-pub
```

## 项目结构

- `client/`: Flutter 前端
- `server/`: FastAPI + Celery + RAG 后端
- `server/app/models/`: 数据模型
- `server/app/services/`: 解析、检索、入库服务
- `server/tests/`: 后端测试
- `CHANGELOG.md`: 迭代记录

## 许可证

Apache 2.0（见 `LICENSE`）。
