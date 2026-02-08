# IntelliNote Pro 📘

**IntelliNote Pro** 是一款工业级、基于 RAG (Retrieval-Augmented Generation) 架构的现代化智能笔记与知识管理助手。它不仅能记录你的想法，更能通过深度学习算法理解你的本地知识库，提供精准、具备多轮对话记忆的智能问答服务。

---

## 🚀 核心特性

### 1. 智能 RAG 对话引擎
*   **上下文感知**：基于 `ContextChatEngine` 的多轮对话管理，支持语义重写，能够精准理解“它”、“那个进度”等代词。
*   **智能兜底机制**：当检索不到本地资料时，系统自动回退到通用 AI 对话模式，确保交互永不中断。
*   **引用溯源**：AI 回复附带点击可查的原文片段引用，确保信息准确可靠。

### 2. 极致的去重与自愈系统
*   **双层去重算法**：
    *   **CAS (Content Addressable Storage)**：基于哈希校验的秒传机制，节省服务器存储。
    *   **Node-level Deduplication**：检索阶段自动剔除重复片段，确保 AI 不受冗余资料干扰。
*   **系统自愈 (Self-Healing)**：
    *   进入笔记本时自动执行健康巡检，静默清理服务器已失效或重置的索引卡片。
    *   `/check` 接口具备自动清理数据库脏记录的能力。

### 3. 跨平台交互体验
*   **现代化 UI**：全局采用 `Consolas` 英文字体，搭配 `GWMSansUI` 优化阅读体验。
*   **智能滚动控制**：支持流式回复自动跟随、手动干预即停、位置记忆等高级交互。
*   **多端适配**：支持 PC 端（Enter 发送/Ctrl+Enter 换行）与移动端（原生换行逻辑）差异化交互。

---

## 🛠️ 技术栈

### 前端 (Client)
*   **Framework**: Flutter 3.x (Dart)
*   **State Management**: Provider
*   **Typography**: Consolas & SimHei & GWMSansUI
*   **Communication**: SSE (Server-Sent Events) 流式数据解析

### 后端 (Server)
*   **Framework**: FastAPI (Python 3.11+)
*   **ORM**: SQLAlchemy (Async Engine)
*   **Task Queue**: Celery + Redis (异步索引处理)
*   **Vector Database**: LlamaIndex (SimpleVectorStore)

### AI & 算法
*   **LLM**: DashScope (通义千问系列)
*   **Embedding**: text-embedding-v3
*   **Algorithm**: 
    *   Semantic Chunking (256 Tokens)
    *   Condense Question Logic
    *   Smart Embedding CAS

---

## 🗺️ 未来路线图 (Roadmap)

- [ ] **全格式支持**: 接入 LlamaParse，支持 PDF、Word、PPT 等复杂文档。
- [ ] **全局搜索**: 跨笔记本的语义向量检索。
- [ ] **实验室增强**: 增加笔记导出为标准 Markdown/PDF 功能。
- [ ] **安全加固**: 引入本地加密存储。
- [ ] **多模态能力**: 支持图片内容识别与图文笔记关联。

---

## ⚖️ 开源协议

本项目采用 [Apache License 2.0](LICENSE) 协议。

---

## 📦 快速启动

1.  **启动后端**:
    ```bash
    cd server
    python manage.py
    ```
2.  **启动前端**:
    ```bash
    cd client
    flutter run
    ```

---
**IntelliNote Pro** - 让你的笔记真正动起来。
