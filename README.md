# IntelliNote Pro

IntelliNote 是一个基于 **RAG (检索增强生成)** 技术的智能知识库助手。采用前后端分离架构，支持私有化部署、文件秒传、增量向量化和高并发处理。

## 🏗️ 项目架构

*   **Client (客户端)**: Flutter (Windows/Mobile)，剥离了所有本地 AI 逻辑。
*   **Server (服务端)**: Python FastAPI + LlamaIndex
*   **Infrastructure (基础设施)**:
    *   **Redis**: 异步任务队列
    *   **SQLite/Qdrant**: 元数据与向量存储
    *   **Celery**: 后台任务处理 (文件解析/Embedding)

## ✨ 核心特性 (Features)

### 1. 智能文档处理
*   **CAS 存储**: 内容寻址存储，自动去重，实现“秒传”。
*   **Smart Embedding**: 向量缓存机制，相同文本块不重复调用 API，大幅降低成本。
*   **异步流水线**: 上传大文件不卡顿，后台自动解析、切分、索引。

### 2. 交互体验
*   **流式对话 (Streaming)**: 类似 ChatGPT 的打字机效果，实时逐字显示回答。
*   **精准引用**: 支持指定特定文件进行问答，减少幻觉。
*   **状态感知**: 实时显示文件解析进度。

### 3. 学习辅助
*   **Studio**: 自动生成学习指南和测验题（Markdown 渲染）。

## 🚀 快速启动 (Quick Start)

### 方式一：Docker 一键启动 (推荐)

确保已安装 Docker Desktop。

1.  进入服务端目录：
    ```bash
    cd server
    ```
2.  配置环境变量：
    复制 `.env` 模板并填入您的 `DASHSCOPE_API_KEY` (通义千问 Key)。
3.  启动服务：
    ```bash
    docker-compose up --build
    ```
    *   API Server: `http://localhost:8000`
    *   Redis: `localhost:6379`

### 方式二：Windows 本地开发启动

如果不使用 Docker，可以使用内置的一键启动脚本：

1.  进入项目根目录。
2.  双击 **`start_dev.bat`**。
3.  脚本将自动打开三个窗口：Redis、Celery Worker 和 FastAPI Server。

### 启动客户端

1.  进入客户端目录：
    ```bash
    cd client
    ```
2.  运行 Flutter：
    ```bash
    flutter run -d windows
    ```

## 📂 目录结构

```text
IntelliNote/
├── client/                 # Flutter 前端代码
│   ├── lib/core/api_client.dart  # API 客户端 (SSE Stream)
│   └── ...
├── server/                 # Python 后端代码
│   ├── app/
│   │   ├── api/            # REST API 接口
│   │   ├── services/       # 业务逻辑 (Ingestion, Storage)
│   │   ├── models/         # SQL 模型
│   │   └── worker/         # Celery 任务
│   ├── data/               # 持久化数据 (SQL, 向量库, 文件)
│   ├── tools/              # 工具 (如便携版 Redis)
│   ├── Dockerfile
│   └── docker-compose.yml
└── start_dev.bat           # Windows 一键启动脚本
```