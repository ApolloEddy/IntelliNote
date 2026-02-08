## 2026-02-08 (Update): Stress Testing & Architecture Reinforcement

### 🎯 目标
针对用户高频操作与异常行为进行压力测试，加固前端状态管理架构，确保在高并发场景下的稳定性。

### 🛠️ 核心修复 (Architecture & Stability)
- **AppState 重构**:
  - **LIFO Bug 修复**: 任务状态更新从“默认索引 0”改为基于 `jobId` 的精确匹配，彻底解决了并发上传时状态错位的问题。
  - **全局处理锁**: 引入 `isProcessing` 状态，实现了跨页面的全局互斥锁，防止重复点击导致的 LLM 请求浪费。
  - **依赖注入**: 为 `AppState` 增加了构造函数注入支持，极大方便了单元测试与 Mock 开发。
- **UI 增强**:
  - **异常反馈**: 来源列表与任务卡片现在支持红色高亮的错误状态提示 (`SourceStatus.failed`)。
  - **跨页面状态保持**: Loading 动画不再因页面切换而消失，UI 能够根据全局状态实时同步进度。

### 🧪 质量保证 (QA)
- **压力测试集**: 新增了针对并发任务创建、流式传输中删除、重复点击生成等场景的自动化测试用例。
- **Widget Test**: 修正了 `widget_test.dart` 的编译错误，确保基础冒烟测试通过。

## 2026-02-08: Full Stack Stabilization & Feature Polish

### 🎯 目标
完成 RAG 全链路调试，修复核心 Bug，并实现前端体验升级（持久化、字体、选择）与后端架构优化。

### 🛠️ 核心修复 (Stability)
- **Server Startup**: 修复了 `main.py` 和 `celery_app.py` 中 LlamaIndex 初始化的竞态条件。
- **Celery Task**: 修复了 `unregistered task` 错误（通过显式添加 `include` 参数）。
- **Client Bug**: 修复了聊天消息 ID 碰撞导致的回复覆盖问题。
- **Smart Embedding**: 修复了秒传去重失效的问题（排除了动态 Metadata 干扰）。

### ✨ 前端升级 (Frontend)
- **数据持久化**: 实现了基于 JSON 的本地存储 (`PersistenceService`)，解决了重启丢失数据的问题。
- **视觉优化**: 
  - 全局字体升级为 **SimHei** (黑体)。
  - 聊天字体升级为 **GWMSansUI** (现代化线条)。
  - 引入 `SelectionArea` 支持跨段落全选复制。
- **交互优化**: 来源列表增加了“清除已完成任务”的按钮。

### ⚙️ 后端优化 (Backend & DevOps)
- **Prompt 工程**: 将硬编码的 Prompt 分离为外部 Markdown 模板 (`server/app/templates/*.md`)。
- **模型配置**: 接入 DashScope (Qwen)，并将 `max_tokens` 调整为 4096 以支持长文生成。
- **DevOps**: 创建了 `server/manage.py`，实现了 Redis/Celery/API 的一键启动与统一管理。

## 2026-02-07: 全面体验升级与稳定性修复

### 🎯 目标
在完成架构重构的基础上，重点优化用户体验（流式对话）和系统稳定性（Bug修复）。

### 🛠️ 修复与优化
- **Bug Fixes**:
  - 修复了 `files.py` 中严重的缩进错误。
  - 修复了跨 Notebook 索引逻辑：秒传文件现在会正确触发索引任务。
  - 修复了 API Client 类型推断错误 (`Map<String, dynamic>`)。
- **性能优化**:
  - 后端引入 `lru_cache` 缓存向量索引，避免每次对话都重新加载磁盘文件。

### ✨ 新增功能
- **流式对话 (Streaming Chat)**: 
  - 后端 `/chat/query` 升级为 SSE (Server-Sent Events) 接口。
  - 前端实现了打字机效果，逐字显示 AI 回复。
- **API Client**: 增加了 `queryStream` 方法，支持长连接和实时数据解析。

### 📝 待办事项 (TODO)
- [ ] 接入 Qdrant 向量数据库以支持更大规模数据。
- [ ] 实现前端数据本地持久化。
