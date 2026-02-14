# 📒 Intelli Note

> **基于 RAG 的本地化智能笔记助手** —— 深度理解你的文档，重塑你的知识连接。

---

## ✨ 项目简介 (Introduction)

**Intelli Note** 是一款旨在通过检索增强生成 (RAG) 技术提升个人知识管理效率的智能应用。它能够无缝导入 TXT、Markdown 及 PDF 文档，利用深度学习模型对内容进行语义建模与向量化存储，从而提供精准的语义搜索、文档问答及智能分类能力。

无论你是学生、研究人员还是开发者，Intelli Note 都能帮你从海量笔记中瞬间定位关键信息，并辅助你生成学习指南、测验题目或摘要总结。

---

## 🚀 核心功能 (Key Features)

- **🧠 深度 RAG 对话**: 
  - 支持基于特定笔记本或选定源文件的流式对话。
  - **引用回溯**: AI 回答精准标注引用来源及页码（支持 PDF 页级定位）。
  - **稳定锚定**: 采用 `reverse` 布局与稳定组件 Key，确保流式输出时滚动平滑不跳动。
- **📄 多格式文档解析**:
  - 原生支持 TXT、Markdown 及 PDF。
  - **混合视觉解析**: 支持 PDF 图像语义识别与扫描页 OCR/Vision 双通道解析。
- **🔍 智能检索与分类**:
  - **双层去重**: 结合文件哈希与语义节点去重，确保知识库纯净。
  - **自动打标**: 利用 LLM 自动为笔记本生成 Emoji 分类标签。
- **🛠️ 跨平台体验**:
  - 极简中性灰主题（VSC 风格），支持多套主题色切换。
  - **桌面优化**: 完整支持 Windows 快捷键（Enter 发送 / Ctrl+Enter 换行）与高效滚动。

---

## 🛠️ 技术栈 (Tech Stack)

### 📱 客户端 (Client)
- **框架**: Flutter (Windows / Mobile)
- **状态管理**: Provider
- **渲染**: Flutter Markdown + Math Fork (支持 LaTeX 公式)
- **通信**: SSE (Server-Sent Events) 流式解析

### 🧠 服务端 (Server)
- **核心框架**: FastAPI (Python 3.10+)
- **RAG 引擎**: LlamaIndex
- **模型支持**: DashScope (Qwen/VL)
- **异步处理**: Celery + Redis
- **持久化**: SQLAlchemy (SQLite/AioSQLite) + Alembic

---

## 🏁 快速开始 (Quick Start)

### 1. 克隆项目
```bash
git clone https://github.com/your-repo/IntelliNote.git
cd IntelliNote
```

### 2. 后端部署 (Server)
```bash
cd server
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
# 配置 .env 中的 DASHSCOPE_API_KEY
python manage.py run
```

### 3. 前端启动 (Client)
```bash
cd client
# 推荐使用预置脚本配置代理环境
powershell ./run_windows.ps1
```

---

## 🗓️ 最近更新 (Recent Updates)
*详情请参阅 [CHANGELOG.md](./CHANGELOG.md)*

- **2026-02-15**: 彻底修复了聊天窗口在 Token 增长时的滚动跳动问题，引入 40ms 刷新节流。
- **2026-02-14**: 落地 PDF Vision v1，支持双通道图像语义识别。
- **2026-02-10**: 品牌升级为 Intelli Note，并完成了全链路稳定性加固。

---

## 📄 许可证 (License)

本项目采用 [Apache 2.0](./LICENSE) 许可证。