## 2026-02-14 (Chat Input UI Fix): 输入框背景一致性与垂直居中修复

### 🎯 目标
修复对话输入框中 placeholder/正文与外层输入容器背景不一致、以及文本垂直位置偏移的问题。

### 🛠️ 变更 (Changed)
- `client/lib/features/chat/chat_page.dart`
  - 在聊天输入框 `InputDecoration` 中显式覆盖全局 `InputDecorationTheme`：
    - `filled: false`
    - `fillColor: Colors.transparent`
  - 为输入文本增加 `strutStyle`（固定行高），并统一 hint 行高：
    - `strutStyle.height = 1.28`
    - `hintStyle.height = 1.28`
  - 保持 `contentPadding` 上下对称，配合 `textAlignVertical.center` 使 placeholder 与正文在单行/多行状态下更稳定地垂直居中。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub lib/features/chat/chat_page.dart`

### 🧱 架构影响 (Architecture)
- 本次仅调整输入框渲染样式，不影响消息发送逻辑、快捷键行为与会话状态机。

---

## 2026-02-14 (Dark Mode Markdown Quote Fix): 夜间引用块可读性修复

### 🎯 目标
修复夜间模式下 Markdown 引用块（`>`）浅蓝底+浅色文字导致对比不足、阅读困难的问题。

### 🛠️ 变更 (Changed)
- `client/lib/features/chat/chat_page.dart`
  - 为 `MarkdownStyleSheet` 增加 `blockquote` 专用样式（文字色、内边距、背景、左侧强调边框）。
  - 夜间模式引用块改为高对比深底+亮文字，白天模式保持轻量浅色引用视觉。
- `client/lib/features/notes/notes_page.dart`
  - 笔记详情弹窗的 Markdown 渲染同步应用同套 `blockquote` 样式，避免页面间表现不一致。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub lib/features/chat/chat_page.dart lib/features/notes/notes_page.dart`

### 🧱 架构影响 (Architecture)
- 样式修复仅作用于 Markdown 渲染层，不影响消息/笔记数据结构与业务流程。

---

## 2026-02-14 (PDF Hybrid Vision v1): 混合页图像识别 + 扫描页 OCR/Vision 双通道

### 🎯 目标
实现 PDF 混合解析模式：文本型 PDF 也可提取图像并进行语义识图；扫描版 PDF 同时走 OCR（文本）与 Vision（图像语义）双通道。

### ➕ 新增 (Added)
- `server/app/services/document_parser.py`
  - 新增图像语义识别 Provider：`DashScopeQwenVisionProvider`（Qwen-VL）。
  - 新增页面图像抽取结构：`ParsedPageImage`。
  - 新增解析统计字段：`vision_pages`、`vision_images`。
- `server/app/core/config.py`
  - 新增 Vision 配置项：
    - `PDF_VISION_ENABLED`
    - `PDF_VISION_MODEL_NAME`
    - `PDF_VISION_MAX_PAGES`
    - `PDF_VISION_MAX_IMAGES_PER_PAGE`
    - `PDF_VISION_TIMEOUT_SECONDS`
    - `PDF_VISION_MIN_IMAGE_RATIO`（默认从 0.08 调整为 0.04，提升论文配图命中率）
    - `PDF_VISION_INCLUDE_TEXT_PAGES`

### 🛠️ 变更 (Changed)
- `server/app/services/document_parser.py`
  - 文本页：保留文本层提取，同时可追加“图像理解补充”段落。
  - 扫描页：在 OCR 提取文本后，继续执行图像语义识别并合并入页面文本。
  - 新增多栏阅读顺序重排：按文本块列聚类后再按列内纵向排序，降低双栏论文串栏问题。
  - 新增矢量图密度估计与整页 Vision 兜底：当页面无可裁剪位图但检测到矢量图特征时，自动触发整页图像理解。
  - 元数据新增 `vision_used`、`vision_images`，便于后续引用追踪。
- `server/app/services/ingestion.py`
  - 将 `vision_used`、`vision_images` 纳入 embedding 元数据排除列表，避免动态字段污染向量。
- `server/app/api/endpoints/system.py`
  - `pdf-ocr-config` 接口扩展 Vision 参数读写（保持向后兼容）。
- `client/lib/app/app_state.dart`
  - OCR 配置状态管理扩展为 OCR + Vision 联合配置。
- `client/lib/features/settings/settings_page.dart`
  - 设置页新增 Vision 开关与参数输入（模型、页数、每页图片数、超时、最小图片占比、文本页开关）。
- `client/lib/features/sources/sources_page.dart`
  - 解析统计展示新增 `Vision页 / Vision图`。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m py_compile app\core\config.py app\services\document_parser.py app\services\ingestion.py app\api\endpoints\system.py`
- `venv\Scripts\python.exe -m pytest -q tests/test_document_parser.py tests/test_pdf_ocr_config_endpoint.py`
- `flutter analyze --no-pub lib/app/app_state.dart lib/features/settings/settings_page.dart lib/features/sources/sources_page.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/citation_model_test.dart`

### 🧱 架构影响 (Architecture)
- PDF 解析链路从“单一文本通道”升级为“文本 + OCR + Vision”可组合模式，同时通过系统配置接口保持低耦合可调优。
- 图像语义信息被注入同页文档片段，后续 RAG 检索可直接召回图示语义而非仅依赖文本层。

---

## 2026-02-14 (Manage CLI UX Fix): 恢复单终端联动启动行为

### 🎯 目标
恢复历史可用的开发体验：`python manage.py` 直接在同一终端前台启动 Redis/Worker/API，并输出合并日志。

### 🛠️ 变更 (Changed)
- `server/manage.py`
  - 新增前台运行命令 `run`（无参默认），统一拉起三服务并合并输出日志。
  - 增加前台模式下的进程守护与 Ctrl+C 联动停止逻辑。
  - 保留后台命令式运维能力：`up/down/status/restart/health`。
- `start_dev.bat`
  - 启动后端改为调用无参 `manage.py`，与前台联动模式一致。
- `README.md`
  - 快速开始与服务管理命令更新为“前台默认 + 后台可选”的说明。

### 🐞 修复 (Fixed)
- 修复“`python manage.py` 不再是单终端联动启动”带来的使用回归。
- 保留 `from __future__ import annotations`，避免在较旧 Python 解释器上触发 `int | None` 注解求值异常。
- 修复前台模式对 `6379` 端口占用过于严格的问题：当本机已存在 Redis 时改为复用，不再直接退出。
- 恢复前台联动模式的服务日志前缀着色（Redis/Worker/API 分色），便于快速区分日志来源。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m py_compile manage.py`
- `venv\Scripts\python.exe manage.py status`

### 🧱 架构影响 (Architecture)
- 将“默认开发入口”与“后台运维入口”解耦：默认走前台联动，子命令用于运维与自动化脚本，降低误用成本。

---

## 2026-02-14 (PDF-RAG Phase 2 v1): 解析统计可视化 + OCR 配置面板

### 🎯 目标
在现有 PDF-RAG 一阶段基础上，提升可观测性与可调优能力：前端可直接查看每个来源的解析统计，并在设置页动态调整 OCR 策略参数。

### ➕ 新增 (Added)
- 新增 OCR 配置接口：
  - `GET /api/v1/system/pdf-ocr-config`
  - `PUT /api/v1/system/pdf-ocr-config`
- 新增 OCR 配置接口测试：
  - `server/tests/test_pdf_ocr_config_endpoint.py`
- 新增来源解析统计展示：
  - Sources 卡片展示 `总页/文本页/OCR页/跳过页`。
- 新增 RAG 质量评测样例集与脚本：
  - `server/tools/rag_eval_cases.jsonl`
  - `server/tools/rag_eval_runner.py`
  - `server/tests/test_rag_eval_runner.py`

### 🛠️ 变更 (Changed)
- `server/app/services/ingestion.py`
  - 任务完成阶段的进度 payload 增加 `parse_stats detail`，便于前端在完成后继续读取统计。
- `server/app/api/endpoints/files.py`
  - 状态接口在 `READY/FAILED` 也尝试读取 Redis 进度详情，保留解析统计可见性。
  - Redis 读取失败降级为日志，不再影响状态接口可用性。
- `server/main.py`
  - 挂载 `system` 路由。
- `client/lib/core/api_client.dart`
  - 新增 OCR 配置读取/更新方法。
- `client/lib/app/app_state.dart`
  - 新增 OCR 配置状态管理（加载、保存、错误态、参数边界解析）。
  - 轮询文件状态时接入 `detail` 并透传到 `SourceItem`。
- `client/lib/core/models.dart`
  - `SourceItem` 增加 `parseDetail` 字段并支持序列化。
- `client/lib/features/sources/sources_page.dart`
  - 来源卡片新增解析统计文案展示。
- `client/lib/features/settings/settings_page.dart`
  - 新增 PDF OCR 设置面板（开关、模型名、页数、超时、阈值与刷新/保存）。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m py_compile main.py app\api\endpoints\system.py app\api\endpoints\files.py app\services\ingestion.py`
- `venv\Scripts\python.exe -m pytest -q tests/test_pdf_ocr_config_endpoint.py tests/test_document_parser.py tests/test_files_extension_validation.py tests/test_chat_error_mapping.py tests/test_files_error_mapping.py`
- `flutter analyze --no-pub lib/app/app_state.dart lib/core/models.dart lib/core/api_client.dart lib/features/sources/sources_page.dart lib/features/settings/settings_page.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/citation_model_test.dart`

### 🧱 架构影响 (Architecture)
- OCR 策略从“仅环境变量静态配置”升级为“服务端可热更新配置 + 前端管理面板”，更利于线上调参和后续 A/B 评估。
- 解析统计贯通链路 `Ingestion -> Status API -> AppState -> Sources UI`，形成端到端可观测闭环。

---

## 2026-02-14 (Stability Loop v1): 服务编排标准化 + 健康检查 + 错误分层

### 🎯 目标
收敛本地开发时的服务状态不一致问题，建立可重复执行的启停流程，并将聊天/队列错误统一为可判别的标准错误码。

### ➕ 新增 (Added)
- 新增服务管理命令式入口：`server/manage.py`
  - 支持 `up/down/status/restart/health`。
  - 引入 `.runtime` 目录保存 pid 与日志，避免重复拉起导致进程混乱。
- 新增后端健康检查接口：`GET /health`
  - 输出 `redis`、`worker`、`llm_config` 三类检查结果。
- 新增错误分层测试：
  - `server/tests/test_chat_error_mapping.py`
  - `server/tests/test_files_error_mapping.py`

### 🛠️ 变更 (Changed)
- `server/app/api/endpoints/chat.py`
  - 新增 `_classify_llm_error`，将 LLM 异常映射为 `E_LLM_TIMEOUT/E_LLM_NETWORK/E_LLM_AUTH/...`。
  - SSE 错误事件增加 `error_code` 与 `error_detail`。
- `server/app/api/endpoints/files.py`
  - 入队异常统一转为 `503` 且携带 `E_QUEUE_UNAVAILABLE`。
  - 文档失败状态新增 `error_code/error_hint`，便于前端和日志快速判因。
- `start_dev.bat`
  - 启动后端改为显式执行 `manage.py up` + `manage.py status`。
- `README.md`
  - 新增服务管理命令与健康检查、常见错误码说明。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m py_compile main.py app\api\endpoints\chat.py app\api\endpoints\files.py manage.py`
- `venv\Scripts\python.exe -m pytest -q tests/test_chat_error_mapping.py tests/test_files_error_mapping.py tests/test_chat_citation_page_number.py`

### 🧱 架构影响 (Architecture)
- 服务生命周期从“临时脚本窗口进程”升级为“命令式可观测编排”，降低 API/Worker/Redis 脱节概率。
- 错误模型由自由文本提升为稳定错误码，前端可按错误类型做差异化提示与后续自动恢复策略。

---

## 2026-02-12 (Chat Timeout Budget Fix): DashScope 多路重试改为总超时预算

### 🎯 目标
修复 `DASHSCOPE_CHAT_TIMEOUT_SECONDS=90` 在三路重试场景下被按“每次尝试 90s”执行，导致总等待时间可超 120s 客户端超时的问题。

### 🛠️ 变更 (Changed)
- `server/app/api/endpoints/chat.py`
  - `_call_dashscope_chat` 的超时策略从“每次重试使用完整超时”改为“共享总预算超时”。
  - 新增总预算控制：按尝试数切分单次请求超时，并在循环内根据剩余预算动态收敛。
  - 当预算耗尽且无明确错误时，返回 `timeout: exhausted total budget Ns` 诊断信息。

### 🐞 修复 (Fixed)
- 修复代理波动时三路回退 (`primary/no_proxy/proxy_off`) 叠加超时导致前端先报 `请求超时` 的问题。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m py_compile app\api\endpoints\chat.py`

### 🧱 架构影响 (Architecture)
- 对话超时语义统一为“总预算”而非“单次尝试”，与配置项命名和客户端超时预期保持一致。

---

## 2026-02-12 (Client Timeout Tuning): 对话流超时从 30s 提升到 120s

### 🎯 目标
避免 RAG 已返回引用但 LLM 生成阶段尚未完成时，客户端过早触发 `请求超时`。

### 🛠️ 变更 (Changed)
- `client/lib/app/app_state.dart`
  - 新增常量 `kChatStreamTimeoutSeconds = 120`。
  - 对话流超时从 `30s` 调整为 `120s`。
  - 超时错误文案改为显示具体阈值：`请求超时（120s），请重试`。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub lib/app/app_state.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart`

### 🧱 架构影响 (Architecture)
- 仅客户端流控参数调整，不影响后端接口协议与数据结构。

---

## 2026-02-12 (Chat Timeout Tuning): DashScope 对话超时提升至 90s

### 🎯 目标
缓解 DashScope 在代理波动场景下的 `Read timed out (20s)` 问题，提升长响应请求成功率。

### 🛠️ 变更 (Changed)
- `server/app/core/config.py`
  - 新增配置项 `DASHSCOPE_CHAT_TIMEOUT_SECONDS`，默认值 `90`。
- `server/app/api/endpoints/chat.py`
  - `_call_dashscope_chat` 请求超时改为读取配置项（最小保护值 10s），默认实际为 `90s`。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m py_compile app\core\config.py app\api\endpoints\chat.py`
- `venv\Scripts\python.exe -m pytest -q tests/test_chat_citation_page_number.py tests/test_full_suite.py`

### 🧱 架构影响 (Architecture)
- 超时策略从硬编码常量转为配置驱动，可通过 `.env` 无代码调参。

---

## 2026-02-12 (PDF Page Preview): Sources 支持按页拉取真实 PDF 内容预览

### 🎯 目标
将“引用定位”从片段级增强到页级：当引用来自 PDF 且带页码时，允许在 Sources 直接拉取并查看该页真实文本预览。

### ➕ 新增 (Added)
- 后端新增 PDF 页预览能力：
  - 新增 `server/app/services/pdf_preview.py`，提供独立的页文本提取函数 `extract_pdf_page_preview`。
  - 新增接口 `GET /api/v1/files/{doc_id}/page/{page_number}`，返回页码、总页数、文本、字符数、图片占比。
- 前端新增页级预览入口：
  - Sources 定位横幅新增“查看页预览”按钮（仅 PDF + 有页码时显示）。
  - 新增页预览弹窗，支持加载态、错误态与文本展示。
- 新增测试：
  - `server/tests/test_pdf_page_preview_reader.py`（覆盖页提取正常/越界场景）。

### 🛠️ 变更 (Changed)
- `client/lib/core/api_client.dart` 新增 `getPdfPagePreview`。
- `client/lib/app/app_state.dart` 新增 `getPdfPagePreview` 透传方法。
- `client/lib/features/sources/sources_page.dart` 定位横幅扩展页级预览交互。

### 🐞 修复 (Fixed)
- 修复“需要查看引用所在真实页内容时，只能看截断片段”的体验缺口。
- 修复测试导入链副作用问题：页预览核心逻辑从 endpoint 文件剥离到 service 层，避免测试时触发 Worker/LLM 初始化依赖。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m py_compile app\api\endpoints\files.py app\services\pdf_preview.py`
- `venv\Scripts\python.exe -m pytest -q tests/test_pdf_page_preview_reader.py tests/test_document_parser.py tests/test_chat_citation_page_number.py tests/test_files_extension_validation.py tests/test_full_suite.py`
- `flutter analyze --no-pub lib/features/sources/sources_page.dart lib/app/app_state.dart lib/core/api_client.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart`

### 🧱 架构影响 (Architecture)
- 页预览提取逻辑独立于 `files.py` 路由层，保持“接口编排”与“PDF解析实现”分离，便于后续扩展到缩略图/OCR页专用策略。

---

## 2026-02-12 (Citation Preview UX): 来源定位横幅增加片段预览与全文查看

### 🎯 目标
在“引用跳转来源”基础上，补齐快速阅读能力：用户切到 Sources 后可直接看到引用片段预览，并一键打开完整片段。

### ➕ 新增 (Added)
- `Sources` 定位横幅新增：
  - 片段预览文本（截断展示）
  - `查看片段` 按钮（弹窗展示完整片段）
- 点击预览文本可直接打开完整片段弹窗。

### 🛠️ 变更 (Changed)
- `client/lib/features/sources/sources_page.dart`：
  - `_SourceFocusBanner` 扩展 `snippet` 与 `onOpenSnippet` 参数。
  - `SourcesPage` 新增 `_showFocusedSnippetDialog`，统一处理片段弹窗展示。

### 🐞 修复 (Fixed)
- 修复“跳转到来源后只能高亮、无法快速阅读引用内容”的交互断层。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub lib/features/sources/sources_page.dart lib/features/chat/chat_page.dart lib/features/notebook/notebook_page.dart lib/app/app_state.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart`

### 🧱 架构影响 (Architecture)
- 仅前端展示层增强，不变更后端接口与持久化结构。

---

## 2026-02-12 (Citation Jump UX): 对话引用一键定位到来源卡片

### 🎯 目标
在 PDF-RAG 引用可追溯基础上，补齐“从聊天引用跳转到来源列表”的交互闭环，减少用户手动查找来源成本。

### ➕ 新增 (Added)
- `ChatPage` 引用弹窗新增“查看来源”按钮：
  - 点击后触发来源定位动作并切换到 Sources 页。
- `AppState` 新增来源定位状态管理：
  - `focusSourceFromCitation`
  - `sourceFocusFor`
  - `clearSourceFocus`
- `SourcesPage` 新增定位提示横幅与卡片高亮样式（含可选页码提示）。
- 新增状态测试：
  - `client/test/app_state_settings_test.dart` 增加“来源定位状态可设置与清除”用例。

### 🛠️ 变更 (Changed)
- `NotebookPage`：
  - 接入 `ChatPage` 的引用跳转回调，收到定位请求时自动切换至 Sources tab。
  - 当引用对应来源不存在时，给出明确提示，不执行无效跳转。
- `SourcesPage`：
  - 被定位来源卡片显示“已定位到引用来源（第 N 页）”状态文案。
  - 支持“一键清除定位态”，避免残留高亮造成误导。
- `AppState.deleteSource/deleteNotebook`：
  - 删除来源或笔记本时同步清理定位态，防止悬挂状态。

### 🐞 修复 (Fixed)
- 修复“引用可见但无法快速定位到对应来源卡片”的交互断链。
- 修复“被删除来源仍可能残留定位态”的状态一致性风险。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub lib/features/notebook/notebook_page.dart lib/features/chat/chat_page.dart lib/features/sources/sources_page.dart lib/app/app_state.dart test/app_state_settings_test.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart`

### 🧱 架构影响 (Architecture)
- 新增定位态为纯前端临时状态，不进入持久化存储，不影响既有 Notebook/Sources/Chat 数据结构。
- 引用跳转链路通过回调解耦：`ChatPage -> NotebookPage -> AppState -> SourcesPage`，避免跨页面直接依赖。

---

## 2026-02-12 (Worker Hotfix): PyMuPDF 缺失快速失败 + Celery 事件循环修复

### 🎯 目标
修复 PDF 任务在 Worker 中因缺少 PyMuPDF 导致的重试风暴，以及重试线程 `Timer-1` 无事件循环引发的二次异常。

### ➕ 新增 (Added)
- 无。

### 🛠️ 变更 (Changed)
- `server/app/worker/tasks.py`：
  - 将异步任务执行从 `get_event_loop + run_until_complete` 改为 `asyncio.run(...)`，避免线程上下文缺失事件循环。
- `server/app/worker/retry_policy.py`：
  - 将 `PyMuPDF is required for PDF parsing` 与 `No module named 'fitz'` 纳入不可重试错误判定。

### 🐞 修复 (Fixed)
- 修复 `RuntimeError: There is no current event loop in thread 'Timer-1'` 的 Worker 重试崩溃。
- 修复 `PyMuPDF` 缺失时重复重试导致的任务噪音与状态收敛延迟。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m pip install PyMuPDF`
- `venv\Scripts\python.exe -m py_compile app\worker\tasks.py app\worker\retry_policy.py app\services\document_parser.py`
- `venv\Scripts\python.exe -m pytest -q tests/test_document_parser.py tests/test_chat_citation_page_number.py`
- `venv\Scripts\python.exe -m pytest -q tests/test_full_suite.py tests/test_files_extension_validation.py`

### 🧱 架构影响 (Architecture)
- Worker 执行模型更稳定：每次任务创建独立事件循环，避免线程复用时的状态污染。
- PDF 依赖缺失场景从“可重试噪音错误”收敛为“一次失败、明确原因”的确定性行为。

---

## 2026-02-12 (PDF-RAG Phase 1): PDF 导入解析 + 页码引用 + 可选 Qwen OCR

### 🎯 目标
在不破坏现有 TXT/MD RAG 链路的前提下，落地 PDF 一阶段能力：支持 PDF 导入、页码级可追溯引用，以及扫描页可选 OCR 的解耦扩展点。

### ➕ 新增 (Added)
- 新增可插拔文档解析层 `server/app/services/document_parser.py`：
  - `DocumentParserRegistry`：按扩展名分流解析器（TXT/MD/PDF）。
  - `PdfDocumentParser`：页级解析、图片占比判定、页码元数据注入。
  - `DashScopeQwenOcrProvider`：扫描页 OCR 的可选 Provider（默认关闭），模型默认 `qwen-vl-max-latest`。
- 新增 PDF 相关配置项：
  - `PDF_OCR_MODEL_NAME`、`PDF_OCR_ENABLED`、`PDF_OCR_MAX_PAGES`、`PDF_OCR_TIMEOUT_SECONDS`
  - `PDF_TEXT_PAGE_MIN_CHARS`、`PDF_SCAN_PAGE_MAX_CHARS`、`PDF_SCAN_IMAGE_RATIO_THRESHOLD`
- 新增测试：
  - `server/tests/test_document_parser.py`
  - `server/tests/test_chat_citation_page_number.py`
  - `server/tests/test_files_extension_validation.py`
  - `client/test/citation_model_test.dart`

### 🛠️ 变更 (Changed)
- 后端 ingestion 接入解析注册表：
  - `server/app/services/ingestion.py` 从直接 `SimpleDirectoryReader` 改为统一走 `DocumentParserRegistry`。
  - 解析完成后在进度详情中输出解析统计（总页数/文本页/OCR页/跳过页）。
- 上传链路文件类型白名单升级为 `TXT/MD/PDF`：
  - `server/app/api/endpoints/files.py` 增加后缀校验与统一错误提示。
  - 白名单与解析层共享单一常量来源，避免策略漂移。
- 前端导入能力与文案同步升级：
  - `client/lib/app/app_state.dart` 文件选择扩展到 `['txt', 'md', 'pdf']`。
  - `client/lib/features/sources/sources_page.dart` 文案更新为支持 PDF。
  - `client/README.md` 功能说明更新为支持 PDF。
- 引用数据结构升级为“可选页码”：
  - `server/app/api/endpoints/chat.py` 引用新增 `page_number`。
  - `client/lib/core/models.dart` 新增 `Citation.pageNumber`（兼容 `page_number/pageNumber`）。
  - `client/lib/app/app_state.dart` 解析 SSE 引用时透传页码。
  - `client/lib/features/chat/chat_page.dart` 引用标签与弹窗展示页码信息。

### 🐞 修复 (Fixed)
- 修复“PDF 能导入但无法进入正确解析路径”的框架缺口（由文件 hash 存储导致扩展名不可见，现改为按原始 filename 分流解析）。
- 修复 PDF 场景下引用仅有片段无页码的问题，提升可追溯性。
- 修复 API 层与解析层各自维护扩展名白名单导致的潜在一致性风险。

### ✅ 验证 (Validation)
- `venv\Scripts\python.exe -m pytest -q tests/test_chat_citation_page_number.py tests/test_document_parser.py tests/test_files_extension_validation.py tests/test_full_suite.py`
- `venv\Scripts\python.exe -m py_compile app\api\endpoints\chat.py`
- `flutter test --no-pub test/citation_model_test.dart`
- `flutter analyze --no-pub lib/app/app_state.dart lib/core/models.dart lib/features/chat/chat_page.dart lib/features/sources/sources_page.dart test/citation_model_test.dart`

### 🧱 架构影响 (Architecture)
- 解析层从“ingestion 内部硬编码单实现”升级为“注册表 + 解析器 + OCR Provider”三段式：
  - 对现有 embedding/index/chat 流程保持兼容；
  - 新增能力以扩展点方式注入，不与核心 RAG 编排强耦合；
  - 后续可在不改 ingestion 主干的情况下替换 OCR 模型或新增 Docx/HTML 解析器。

---

## 2026-02-12 (UX Copy Alignment): Sources 空状态文案与导入能力对齐

### 🎯 目标
修复 Sources 页面空状态文案与实际导入能力不一致的问题，避免用户被“支持 PDF”文案误导。

### ➕ 新增 (Added)
- 无。

### 🛠️ 变更 (Changed)
- `client/lib/features/sources/sources_page.dart` 空状态提示改为：
  - `导入 TXT、MD 或粘贴文本`

### 🐞 修复 (Fixed)
- 修复“文案提示支持 PDF，但当前文件选择仅允许 TXT/MD”造成的预期偏差。

### 🧱 架构影响 (Architecture)
- 无数据结构与接口变更，仅 UI 文案层对齐既有功能边界。

---

## 2026-02-10 (UX & Theme Polish v5): VSC 暗色回归 + 气泡模式 + 重新打包

### 🎯 目标
将全局暗色背景收敛到更接近 VS Code Dark Theme 的中性灰基调，补齐聊天气泡默认风格与主题联动，并完成新 Logo 的 Windows 重打包。

### ➕ 新增 (Added)
- 新增“用户气泡色”设置项（默认 `ChatGPT 默认`）：
  - `ChatGPT 默认`：深色下为更浅一阶黑灰气泡，浅色下为更深一阶白灰气泡。
  - `跟随主题色`：用户气泡使用主题色透明层。
- 新增用户气泡色配置链路：
  - `AppState` 增加 `userBubbleToneId` 与 `setUserBubbleTone`
  - 持久化写入 `settings.userBubbleToneId` 并在启动时回读
- 设置测试新增“无效气泡色配置自动回退”用例。

### 🛠️ 变更 (Changed)
- 全局主题暗色基线回归 VSC 风格中性灰：
  - `surface/surfaceContainer*`、`outline*` 调整为非偏绿深灰层级
  - `scaffoldBackgroundColor` 调整为 `#1E1E1E` 基底
- 主题色联动范围扩展：
  - `NavigationBar` 选中高亮/图标/标签颜色与主题色同步
  - `FilterChip`、聊天引用 `ActionChip`、进度条主题统一接入主题色
- 输入框深色去边框：
  - 全局 `InputDecorationTheme` 在 dark 模式下移除边框
  - 聊天输入容器、搜索框、新建/重命名弹窗输入区在 dark 模式移除边框描线
- 圆角体系整体下调（更克制）：
  - `Card/Chip/Button/Input` 等全局圆角下调
  - 首页 Notebook 卡片、聊天输入容器、搜索框、菜单浮层圆角减小
- 首页 Notebook 卡片交互优化：
  - 卡片圆角减小
  - 右侧省略号点击热区放大为矩形区域（非圆形）
  - `ModernMenuButton` 使用 `HitTestBehavior.opaque` 提升命中率

### 🧩 品牌与打包 (Build)
- 已基于更新后的 `client/assets/logo.png` 重新生成：
  - `client/windows/runner/resources/app_icon.ico`
- 已完成 Windows Release 重打包：
  - 产物：`client/build/windows/x64/runner/Release/intelli-note.exe`
- `.gitignore` 新增 `client/assets/*.psd`，避免设计源文件误提交。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub lib/app/app.dart lib/app/app_state.dart lib/features/settings/settings_page.dart lib/features/chat/chat_page.dart lib/features/home/home_page.dart lib/features/home/interactive_search_bar.dart lib/features/home/modern_menu.dart lib/features/notebook/notebook_page.dart test/app_state_settings_test.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart`
- `flutter build windows --release --no-pub`

---

## 2026-02-10 (UX & Theme Polish v4): 搜索收起修复 + 来源徽标化 + 可选主题色

### 🎯 目标
修复首页搜索框在 PC 端的收起与模糊行为异常，优化来源文件在深色模式下的可读性，并新增有限主题色选择能力（配合浅色/深色/跟随系统）。

### ➕ 新增 (Added)
- 设置页 `外观` 增加“主题色”选择（翡翠绿、海洋蓝、紫罗兰、琥珀橙、玫瑰红）。
- `AppState` 新增主题色配置链路：
  - 新字段 `themeAccentId`
  - 新方法 `setThemeAccent`
  - 新增持久化与回读（`settings.themeAccentId`）
- 新增设置测试用例：无效主题色值自动回退默认值。

### 🛠️ 变更 (Changed)
- 首页搜索栏交互重构：
  - Hover 展开时立即显示背景模糊层（不再依赖输入框聚焦）
  - PC 端鼠标移出且输入为空时自动收起
  - 点击空白区域时，空输入场景可立即收起
  - 回车提交后继续保持“无模糊”展示结果
- 首页 Notebook 图标样式调整：
  - 取消 emoji 背景容器，改为透明展示
  - emoji 尺寸增大，提高识别度
- 来源文件卡片视觉与信息表达升级：
  - 文件前导图标改为扩展名徽标（如 `MD`、`PDF`、`TXT`）
  - 深色/浅色下统一使用主题语义色，增强标题、状态与背景对比
  - 删除按钮与进度色彩统一接入主题色
- 全局主题支持主题色驱动：
  - `MaterialApp` 根据设置主题色动态生成 light/dark Theme
  - `FilledButton`、`FAB`、`SegmentedButton`、`Chip` 等控件主色统一跟随主题色
  - 聊天用户气泡改为主题色低透明度风格，和发送按钮色调保持一致

### 🐞 修复 (Fixed)
- 修复搜索框首次 Hover 展开时背景不模糊的问题。
- 修复搜索框在输入为空时，鼠标移出/点击空白后无法收起的问题。
- 修复来源文件列表在暗色主题下“背景与文字区分度不足”的可读性问题。

### 🧱 架构影响 (Architecture)
- 设置链路从“仅主题模式”升级为“主题模式 + 主题色”双维度配置：
  - `SettingsPage` → `AppState` → `PersistenceService(extra.settings)` → 启动 `_load()` 回读 → `MaterialApp Theme` 动态消费。
- 来源文件展示从“类型图标”升级为“文件扩展名徽标”，信息表达更贴近文件语义，且不依赖图标映射。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub lib/app/app.dart lib/app/app_state.dart lib/features/home/interactive_search_bar.dart lib/features/home/home_page.dart lib/features/sources/sources_page.dart lib/features/settings/settings_page.dart lib/features/chat/chat_page.dart test/app_state_settings_test.dart`
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart`

---

## 2026-02-10 (Theme UX Hotfix v2): ChatGPT 风格暗色优化 + 搜索交互重构

### 🎯 目标
针对视觉反馈继续优化深色模式（参考 ChatGPT Android 风格），降低图标背景与卡片阴影压迫感；同时重构首页搜索框交互逻辑，解决 PC 悬停与提交行为不符合预期的问题。

### 🛠️ 变更 (Changed)
- 深色主题改为更接近 ChatGPT 风格的中性深灰基调：
  - 背景/面板/边框色采用更克制的层级对比（非高饱和色块）
  - 保留发送按钮主色作为品牌强调色，统一交互焦点
- 首页与菜单阴影减轻：
  - Notebook 卡片、悬浮搜索框、下拉菜单、重命名弹窗阴影半径与透明度整体下调
  - 图标背景与容器对比度降低，避免“发灰发脏”或“重阴影”视觉负担
- Chat 页面暗色进一步适配：
  - 用户气泡改为更中性的深灰样式（暗色下不再偏突兀）
  - Markdown 文本/代码块/输入区文字与提示色改为主题语义色
  - 输入框容器与忙碌态按钮颜色在暗色下统一为低对比层级

### 🔎 搜索交互重构 (Search UX)
- PC 端鼠标移出搜索框时：若输入为空则自动收起。
- 搜索改为“回车提交”触发检索：
  - 输入过程中不立即筛选（清空输入时会立即清空筛选）
  - 按 Enter 后提交关键词并取消背景模糊
- 背景模糊只在“展开 + 未提交 + 聚焦输入”时出现，避免提交后仍遮挡内容。
- 首页统计文案增强：
  - 当有筛选关键词时显示  
    `你有 {总数} 个笔记本，检索关键词 “{关键词}” ，检索到 {结果数} 个结果`

### 🧱 架构影响 (Architecture)
- 搜索状态从“纯输入联动筛选”升级为“输入态 + 提交态”双状态模型，交互语义更清晰。
- 深色主题继续从“组件局部修色”向“语义色统一驱动”推进，为后续 Sources/Studio/Notes 页面统一改造奠定基线。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub`（相关文件）通过。
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart` 通过。

---

## 2026-02-10 (Theme UX Hotfix): 设置按钮避让 + VSC 风格深色主题优化

### 🎯 目标
修复首页搜索栏与设置按钮重叠问题，并将深色模式调整为更接近 VS Code 默认 Dark Theme 的视觉风格，提升组件在暗色场景下的可读性与一致性。

### 🛠️ 变更 (Changed)
- 搜索栏定位支持偏移参数（`topOffset`、`rightOffset`），首页将搜索栏右侧留白后移，避免与齿轮按钮重叠。
- 全局主题重构为双方案式：
  - 浅色：延续现有风格
  - 深色：采用 VSC 风格配色（深灰背景 + 中性面板 + 蓝色强调）
- 强化暗色主题基础样式：`scaffoldBackgroundColor`、`cardTheme`、`dialogTheme`、`inputDecorationTheme`、`appBar` 图标与文本颜色统一。
- 首页关键组件去硬编码亮色：
  - 空态文案、卡片背景、卡片边框、标题与更多按钮图标改为基于 `ColorScheme` 的动态颜色
  - 新建/重命名弹窗在暗色下使用深色渐变与动态边框/文本色
- 菜单与搜索组件暗色适配：
  - `ModernMenu` 的背景、边框、阴影、hover 与文本色改为主题驱动
  - `InteractiveSearchBar` 的背景、边框、图标色、输入文字色改为主题驱动，并移除弃用 API `withOpacity`
- Chat 页面关键区域暗色适配：
  - 消息气泡、Markdown 代码块、动作按钮、输入框提示/文本色、发送按钮与忙碌态颜色改为主题驱动
  - 避免暗色模式下“浅底深字”与“对比不足”混用问题

### 🐞 修复 (Fixed)
- 修复首页搜索栏与设置按钮点击区域重叠。
- 修复深色模式下多个组件“背景过亮/字色偏浅或偏暗”的可读性问题。
- 清理搜索栏无用状态字段，消除静态检查告警。

### ✅ 验证 (Validation)
- `flutter analyze --no-pub`（相关文件）通过。
- `flutter test --no-pub test/app_state_settings_test.dart test/widget_test.dart` 通过。

### 🧱 架构影响 (Architecture)
- 页面层 UI 颜色策略进一步从“常量色值”转向“主题语义色”。
- 为后续扩展暗色覆盖（Chat/Sources 等页）建立统一配色基线。

---

## 2026-02-10 (Settings): 首页设置入口 + 常规设置页首版

### 🎯 目标
在首页提供可发现的设置入口，落地常规设置页核心能力，并确保设置项可持久化、可回读、可即时生效。

### ➕ 新增 (Added)
- 新增设置页面 `client/lib/features/settings/settings_page.dart`，首版提供：
  - 主题模式：跟随系统 / 浅色 / 深色
  - 首页称呼：可编辑并保存（含长度与空白输入校验）
  - 删除 Notebook 前二次确认开关
  - 首页笔记本数量显示开关
  - “规划中”功能位：语言、快捷键、启动行为
- 新增设置回归测试 `client/test/app_state_settings_test.dart`：
  - 默认值检查
  - 持久化写入与重载恢复
  - 称呼空白回退与超长截断

### 🛠️ 变更 (Changed)
- `AppState` 增加设置状态与持久化链路：
  - 新增字段：`themeMode`、`displayName`、`confirmBeforeDeleteNotebook`、`showNotebookCount`
  - `_save()` 扩展写入 `settings` 节点，`_load()` 支持回读并容错默认值
  - 新增设置更新方法：`setThemeMode`、`setDisplayName`、`setConfirmBeforeDeleteNotebook`、`setShowNotebookCount`
- `MaterialApp` 改为跟随 `AppState` 的 `themeMode`，并补充 `darkTheme` 主题。
- 首页 `SliverAppBar` 新增齿轮按钮，点击进入设置页。
- 首页问候语从固定 `Eddy` 改为读取设置称呼；笔记本数量文本支持开关控制。
- Notebook 删除入口接入“二次确认”配置（关闭时可直接删除，开启时弹确认对话框）。

### 🐞 修复 (Fixed)
- 修复设置页输入格式器声明导致的测试编译错误（`const` 列表中使用非常量构造）。
- 清理 `app_state.dart` 冗余导入，消除静态分析告警。

### 🧱 架构影响 (Architecture)
- 设置数据链路已闭环：`设置页输入` → `AppState` 状态更新/归一化 → `PersistenceService.saveData(extra.settings)` → 启动时 `_load()` 回读 → `MaterialApp/HomePage` 实时消费。
- 该链路与现有 `selectedSources` 共存于同一持久化文件，不破坏既有 Notebook/Sources/Chat/Notes 数据结构。

---

## 2026-02-10 (Windows Build Hotfix): 目标重命名后的 CMake 缓存兼容

### 🎯 目标
修复 Windows 端在应用目标名重命名后，`flutter run -d windows` 因历史 CMake 缓存仍引用旧目标 `intellinote` 而构建失败的问题。

### 🛠️ 变更 (Changed)
- 在 `client/windows/CMakeLists.txt` 增加安装前缀缓存迁移逻辑：
  - 当检测到 `CMAKE_INSTALL_PREFIX` 含有 `TARGET_FILE_DIR:` 的历史目标表达式时，强制重置为当前 `BINARY_NAME` 对应路径。
  - 保留默认初始化分支，继续兼容首次配置流程。

### 🐞 修复 (Fixed)
- 修复 `CMake Error: $<TARGET_FILE_DIR:intellinote> No target "intellinote"` 导致的生成阶段失败。
- 验证结果：`flutter run -d windows --no-pub` 可正常构建并启动，产物为 `build/windows/x64/runner/Debug/intelli-note.exe`。

### 🧱 架构影响 (Architecture)
- Windows 构建链对“目标名变更”具备向后兼容能力，减少 `flutter clean`/手动删缓存的强依赖。

### 🔎 额外排查 (Investigation)
- 对 `client/assets/logo.png` 执行无元数据重写，并同步重建 `client/windows/runner/resources/app_icon.ico`，确保图标源文件仅含基础 PNG 块。
- 在 `flutter clean` 后重新执行 `flutter run -d windows`，构建可成功完成，但 `libpng iCCP` 警告仍出现，说明该警告不由当前项目 Logo 资源直接触发。

---

## 2026-02-10 (Branding v2): 内部技术标识按命名约束统一

### 🎯 目标
在“统一品牌为 `Intelli Note`”的基础上，对不支持空格的技术标识执行降级命名：优先 `Intelli-Note`，若仍不支持则使用 `Intelli_Note`（按各生态规范转为小写）。

### 🛠️ 变更 (Changed)
- Flutter 包名从 `intellinote` 调整为 `intelli_note`（Dart 包名不支持空格与连字符）：
  - `client/pubspec.yaml`
  - `client/test/widget_test.dart` 的 `package:` 导入同步更新。
- Windows 构建标识按约束拆分：
  - `project()` 名称改为 `intelli_note`（稳妥兼容 CMake 变量体系）。
  - 可执行产物名改为 `intelli-note`（支持连字符）。
  - `Runner.rc` 中 `OriginalFilename` 同步为 `intelli-note.exe`。
- Docker 部署标识统一为连字符风格：
  - 容器名：`intelli-note-redis` / `intelli-note-api` / `intelli-note-worker`
  - 网络名：`intelli-note-net`
- Celery 应用名调整为 `intelli-note-worker`，与部署命名一致。

### ➕ 新增 (Added)
- 持久化文件命名升级为 `Intelli Note_data.json`，并新增旧文件名兼容回退读取：
  - `intellinote_data.json`
  - `intelli-note_data.json`
  - `intelli_note_data.json`
- `.gitignore` 新增 `client/intelli_note.iml` 与 `client/intelli-note.iml`，兼容 IDE 模块名变化。

### 🐞 修复 (Fixed)
- 修复包名改动后测试文件冗余导入导致的静态检查告警（`unused_import`）。

### 🧱 架构影响 (Architecture)
- 品牌展示层保持 `Intelli Note`（空格形式），技术标识层根据工具链约束自动降级为 `-` 或 `_`，避免“品牌统一”与“构建可用性”冲突。
- 本次对持久化路径加入兼容加载链路，避免历史用户数据因文件名迁移而丢失。

---

## 2026-02-10 (Branding): 统一品牌为 Intelli Note 并接入 LOGO

### 🎯 目标
将 `client/assets/logo.png` 统一应用到程序图标、标题栏与文档品牌位，并将对外展示名称统一为 `Intelli Note`。

### ➕ 新增 (Added)
- 客户端首页标题栏新增品牌 Logo（`assets/logo.png`），与 `Intelli Note` 文案并列展示。
- `README.md` 与 `client/README.md` 新增 Logo 展示位，统一项目视觉入口。

### 🛠️ 变更 (Changed)
- Windows 程序窗口标题改为 `Intelli Note`（`client/windows/runner/main.cpp`）。
- Windows 可执行文件资源元信息（`FileDescription`/`InternalName`/`ProductName`）统一为 `Intelli Note`（`client/windows/runner/Runner.rc`）。
- 后端对外项目名改为 `Intelli Note Server`（`server/app/core/config.py`）。
- 聊天提示词模板中的助手身份从 `IntelliNote` 统一为 `Intelli Note`（`server/app/templates/chat/*.md`）。
- 启动脚本窗口标题与启动提示文案统一为 `Intelli Note`（`start_dev.bat`）。
- 客户端工作流文档标题与品牌称呼统一为 `Intelli Note`（`client/IntelliNote_Build_Workflow.md`）。

### 🐞 修复 (Fixed)
- 修复 `client/lib/app/app.dart` 中 `withOpacity` 的弃用调用，改为 `withValues(alpha: 0.1)`，消除静态分析告警。

### 🧱 架构影响 (Architecture)
- 保持技术标识（如包名、可执行文件名、容器名）不变，仅统一用户可见品牌层，避免破坏依赖链与部署脚本兼容性。
- Windows 图标资源 `client/windows/runner/resources/app_icon.ico` 由 `client/assets/logo.png` 重新生成，形成“单一品牌源图”到程序图标的可追溯链路。

---

## 2026-02-10 (Audit): 代码库全量审查与问题整合

### 🎯 目标
整合 Codex Cloud 的四份代码审查报告，输出统一的《代码审查与审计报告》，并识别核心风险点与技术债务。

### 🛠️ 变更 (Changed)
- **报告整合**: 将 `NeedCleared.审查报告.txt` 中的 UI、API、测试三个维度的 4 个版本报告整合为 `Consolidated_Review_Report.md`。
- **风险分级**: 识别出 3 个 P0 级致命缺陷（崩溃/编译错误/输入冲突）、3 个 P1 级体验缺陷（流式超时/反馈缺失）以及架构级 P2 债务。
- **文档维护**: 删除原始冗余报告文件 `NeedCleared.审查报告.txt`。

### 🧱 架构影响 (Architecture)
- 本次行动为纯文档与审计工作，未直接修改代码，但为后续的“稳定性加固”阶段确立了明确的修复路线图。

---

## 2026-02-10 (UX Hotfix v3): 强制手动滚动优先 + 输入框单行空态瘦身

### 🎯 目标
彻底解决用户手动滚动时仍被自动跟随干扰的问题，并继续压缩输入框在空内容/单行场景下的视觉高度。

### 🛠️ 变更 (Changed)
- 对话滚动新增更强约束：
  - 手动交互期间（拖拽/滚轮）禁止 `_scrollToBottom` 执行；
  - 仅在用户回到底部时恢复自动跟随。
- 输入框单行空态自适应：
  - 容器垂直内边距、最小高度、文本字号与行高下调；
  - 发送按钮尺寸和图标尺寸联动缩小；
  - 多行时自动回到更宽松的阅读比例。

### 🐞 修复 (Fixed)
- 修复滚动时自动跟随与手动滚动争抢导致的“反复横跳”。
- 修复空内容输入框看起来过厚、字体与按钮比例不协调的问题。

---

## 2026-02-10 (UX Hotfix v2): 对话滚动锁定机制 + 输入框空态比例修正

### 🎯 目标
解决对话区滚动在用户匀速拖动时仍出现跳动的问题，并修正输入框在空内容状态下的字体与容器比例失衡。

### 🛠️ 变更 (Changed)
- 聊天滚动新增“手动滚动锁”（`_manualScrollHold`）：
  - 用户滚动/滚轮期间强制关闭自动跟随；
  - 仅在用户结束交互且接近底部时恢复自动滚动。
- 自动滚底策略增加保护：
  - 当手动滚动锁开启时，不执行自动滚底；
  - 小位移直接 `jumpTo`，大位移短动画，减少抖动。
- 输入框空态比例二次修正：
  - 容器边距、圆角和最小高度下调；
  - 文本字号/行高/内边距重配；
  - 发送按钮尺寸与图标尺寸同步缩小，比例更协调。

### 🐞 修复 (Fixed)
- 修复“用户正在滚动时自动跟随仍介入”导致的上蹿下跳。
- 修复输入框空态下字体视觉偏大、按钮与文本区比例不协调。

---

## 2026-02-10 (UX Hotfix): 对话滚动抖动修正 + 输入框比例二次调优

### 🎯 目标
修复对话区滚动时“上蹿下跳”的跟手问题，并进一步优化输入框字体与容器尺寸比例不协调的问题。

### 🛠️ 变更 (Changed)
- 对话滚动跟随策略改为“拖拽开始即关闭自动滚动、拖拽结束且接近底部才恢复”，减少滚动冲突。
- `_scrollToBottom` 增加距离阈值：
  - 小距离直接 `jumpTo`
  - 大距离短动画 `animateTo`
  以避免频繁动画叠加导致的抖动。
- 输入框容器比例二次调整：
  - 文本区最小高度约束
  - 输入字号/行高与内边距重配
  - 发送按钮尺寸约束与缩放幅度微调

### 🐞 修复 (Fixed)
- 修复用户匀速上下拖拽时自动滚动与用户滚动相互争抢导致的跳动问题。
- 修复输入框中文本视觉比例偏大、容器高度不协调的问题。

---

## 2026-02-10 (UX Polish): 对话滚动手感优化 + 气泡比例调整 + 来源导入窗口重构

### 🎯 目标
提升对话区滚动跟手性与阅读舒适度，并重做“知识来源导入”交互，替换简陋的底部菜单式入口。

### ✨ 新增 (Added)
- 来源页新增自定义导入弹窗：
  - `_ImportChooserDialog`（中置弹窗，卡片化导入选项）
  - `_ImportActionCard`（可交互导入方式卡片）
- 新增粘贴文本弹窗：
  - `_PasteSourceDialog`（统一主题样式）
  - `_PastePayload`（粘贴导入参数封装）
- 聊天页新增 `_ChatScrollBehavior`，扩展鼠标/触控板拖拽设备支持。

### 🛠️ 变更 (Changed)
- 对话区 `ListView` 增加显式 `Scrollbar`（桌面端 `thumb+track` 可见，支持拖拽）。
- 自动滚动策略增强：用户主动滚动时立即关闭自动跟随，仅在接近底部时恢复自动滚动，避免“拉扯感”。
- 聊天气泡尺寸与排版优化：
  - 最大宽度从固定比例调整为桌面/移动端分级比例。
  - 调整气泡内边距、最小宽度。
  - 正文字号与行高、代码字号下调到更协调比例。
- 来源页导入入口由 `showModalBottomSheet` 改为 `showGeneralDialog` 中置弹窗，视觉与交互一致性提升。

### 🐞 修复 (Fixed)
- 修复“导入按钮点击后从底部弹出简易菜单”的交互粗糙问题。
- 修复粘贴导入时文本内容为空仍可提交的问题（新增前端校验与错误提示）。

### 🧱 架构影响 (Architecture)
- 来源导入流程从“页面内联底部菜单 + 简单 AlertDialog”升级为“可复用弹窗组件化架构”，后续可扩展 URL 导入、批量导入等能力而无需改动主页面结构。

---

## 2026-02-10 (UI Hotfix): Notebook 输入窗口重写 + 占位提示冲突修复

### 🎯 目标
修复输入框出现“双灰色占位提示”的体验问题，并将 Notebook 创建/重命名入口重写为统一主题输入窗口。

### ✨ 新增 (Added)
- 新增通用弹窗输入能力：
  - `showNotebookNameDialog(...)`
  - `_NotebookNameDialogCard` 组件（带缩放淡入动画）
- 新增输入窗口视觉与交互：
  - 主题化卡片容器（渐变、圆角、聚焦边框高亮）
  - 统一按钮区（取消/确认）
  - 标题空值即时错误提示
  - 长度限制（`maxLength=60`）

### 🛠️ 变更 (Changed)
- `HomePage._showCreateDialog` 改为复用新输入窗口，不再使用 `labelText + hintText` 双提示组合。
- `_NotebookCard._showRenameDialog` 对齐到同一输入窗口，创建与重命名体验一致。
- 聊天输入组件移除底部第二行灰色提示，仅保留单一占位文本，避免视觉重复。

### 🐞 修复 (Fixed)
- 修复“输入框上下两条灰色提示文字”问题（根因：标签与提示文案叠加）。

### 🧱 架构影响 (Architecture)
- Notebook 命名输入从页面内联 `AlertDialog+TextField` 升级为可复用的对话输入组件，后续其他命名场景可直接复用同一实现。

---

## 2026-02-10 (UI Hotfix): 对话页红屏修复 + 输入框组件重写

### 🎯 目标
修复聊天界面出现 Flutter 红底黄字错误，并将输入框升级为符合当前主题风格的动画化组件，提升稳定性与交互质感。

### ✨ 新增 (Added)
- 新增 `_ChatComposer` 组件，统一承载：
  - 输入框容器样式（圆角卡片、边框高亮、阴影）
  - 发送按钮状态动画（发送图标/加载态切换）
  - 桌面端与移动端的快捷提示文案

### 🛠️ 变更 (Changed)
- 聊天页底部输入区从“下划线 TextField + 按钮”改为“主题化容器输入组件”。
- 键盘事件监听由 `KeyboardListener` 调整为 `Focus(onKeyEvent)`，与 `TextField` 聚焦链路对齐，降低焦点冲突风险。
- 发送链路新增并发保护：在 `_sending` 或 `isProcessing` 时直接拦截重复发送。
- `Ctrl+Enter` 插入换行时增加无效 selection 兜底，避免光标异常导致的范围错误。

### 🐞 修复 (Fixed)
- 修复 LaTeX 块级语法正则中使用内联 `(?s)` 标志导致的运行期兼容风险，避免消息渲染阶段触发页面崩溃。

### 🧱 架构影响 (Architecture)
- 对话输入区域从页面内联实现收敛为独立组件 `_ChatComposer`，后续可以在其他页面复用同一输入体验并集中维护输入行为。

---

## 2026-02-10 (UI): 聊天气泡新增 LaTeX 公式渲染支持

### 🎯 目标
让 AI 对话中的数学表达式在聊天气泡内直接可读渲染，避免公式以纯 Markdown 文本显示影响阅读。

### ✨ 新增 (Added)
- 聊天气泡支持 LaTeX 公式语法：
  - 行内公式：`$...$`
  - 块级公式：`$$...$$`
- 新增公式渲染依赖：
  - `flutter_math_fork`
  - `markdown`

### 🛠️ 变更 (Changed)
- `chat_page.dart` 中 `MarkdownBody` 增加自定义 LaTeX 语法解析与渲染器：
  - `_InlineLatexSyntax`
  - `_BlockLatexSyntax`
  - `_LatexElementBuilder`
- 公式解析失败时回退为原始公式文本显示（红色），避免消息渲染中断。

### 🧱 架构影响 (Architecture)
- 对话渲染链路从“纯 Markdown 文本”升级为“Markdown + LaTeX 复合渲染”，仅影响前端展示层，不改变后端 RAG/引用数据结构。

---

## 2026-02-10 (Hotfix v10): 改用 DashScope 直连 HTTP 生成，绕开 SDK 空响应链路

### 🎯 目标
彻底修复 `AgentChatResponse = Empty Response` 且后续 `llm.chat` 网络重试不稳定导致的“有检索、无稳定回答/无引用”问题。

### 🛠️ 变更 (Changed)
- `chat/query` 从 `as_chat_engine().chat()` 的生成链路改为：
  - **检索**：本地 `as_retriever()` 完成（仍保留 source filters）。
  - **生成**：后端直接调用 DashScope HTTP 接口（`/text-generation/generation`），不再依赖 LlamaIndex DashScope SDK 的生成路径。
- RAG 路径改为“先发 citations，再发 token”，保证引用优先落到前端。
- 当远程生成失败时，基于已检索片段返回本地降级答复，避免空白。
- `test_chat_streaming` 同步更新到新链路（mock retriever + mock `_call_dashscope_chat`）。

### 🐞 修复 (Fixed)
- 修复了 `chat_engine` 返回 `Empty Response` 导致的主回答不稳定。
- 修复了引用数据存在但生成失败时引用无法可靠到达 UI 的问题。

---

## 2026-02-10 (Hotfix v9): RAG 引用优先投递 + 本地降级答复

### 🎯 目标
修复“RAG 检索有结果但引用不显示、正文为空”场景下的可用性问题。

### 🛠️ 变更 (Changed)
- `chat/query` 在 RAG 路径下改为**先发送 citations 事件**，再发送 token，确保引用不会因后续生成失败而丢失。
- 当 RAG/LLM 返回空正文时，不再只回 error，而是基于已检索片段生成本地降级答复，保证 UI 始终有可读输出。

### 🐞 修复 (Fixed)
- 修复了“source_nodes 已命中但前端无引用 chips”的链路稳定性问题。

---

## 2026-02-10 (Hotfix v8): 引用事件优先发送，修复“有回答无引用”可见性问题

### 🎯 目标
在 RAG 回答链路中确保引用条目优先到达前端，即使后续 token 流中断也不丢引用展示。

### 🛠️ 变更 (Changed)
- `chat/query` 在 RAG 成功路径下改为先发送 `citations` 事件，再发送 `token` 事件。
- 后端 citation 的 `score` 字段强制数值化，避免 `null` 触发客户端解析异常。
- 前端 `AppState` 新增 `_parseCitations()` 容错解析，单条坏数据不影响整条回答。

### 🐞 修复 (Fixed)
- 修复“后端日志显示已发送 citations，但 UI 无引用 chips”的链路不稳定问题。

---

## 2026-02-10 (Hotfix v7): 修复 RAG 模式下 AI 回复为空 (Empty Response) 的逻辑缺陷

### 🎯 目标
解决在 SSE 流式传输过程中，RAG 模式因对象提取失败或 LLM 拒答导致的回复内容为空（Empty Response）问题。

### 🛠️ 修复 (Fixed)
- **RAG 响应提取增强**：优化 `_extract_response_text` 逻辑，支持 LlamaIndex ChatEngine 返回的多种响应对象结构。
- **强制 Prompt 回退机制**：当 ChatEngine 检索后返回空响应时，自动构造包含背景资料的显式 Prompt 并回退至底层的 `llm.chat` 接口，确保回复生成的成功率。
- **SSE 稳定性优化**：修复了在 RAG 路径中可能导致生成器提前关闭的逻辑，并在提取失败时提供更清晰的 Fallback 路径。
- **调试日志增强**：在控制台详细打印 RAG 检索到的节点数量、提取结果及 Fallback 状态，便于后续排查。

### 2026-02-10 (Hotfix v6): 强制 DashScope 直连优先，避免代理链路卡死

### 🎯 目标
在 `DASHSCOPE_FORCE_NO_PROXY=true` 场景下，彻底避免 DashScope 请求先走代理再回退导致的长时间等待与无响应。

### 🛠️ 变更 (Changed)
- `chat/query` 的 DashScope 调用策略改为：
  - 当 `DASHSCOPE_FORCE_NO_PROXY=true` 时，先显式清空代理变量并附加 DashScope 到 `NO_PROXY`，直接走直连模式。
  - 超时从长等待收敛为短等待（18s），并保留一次同模式快速重试。
- 分类器与 Embedding HTTP 客户端对齐：
  - `classifier` 在强制直连模式下同样先禁代理再请求。
  - `dashscope_http_embedding` 与 `smart_embedding` 在强制直连模式下显式传入 `proxies={\"http\": None, \"https\": None}`。

### 🐞 修复 (Fixed)
- 修复了强制直连已开启但请求仍可能先经过代理链路，导致 RAG 查询阶段卡在重试并长期无 token 输出的问题。

---

## 2026-02-10 (Hotfix v5): qwen3 非流式参数修正 + DashScope 直连生效

### 🎯 目标
在用户当前网络环境（Gsou TUN + 规则代理）下，确保 `qwen3-32b` 能稳定返回正文，不再出现“有检索无回答”。

### 🛠️ 变更 (Changed)
- **qwen3 调用参数兼容**:
  - 对 `qwen3*` 模型的非流式调用统一注入 `enable_thinking=false`（聊天与分类链路），修复 DashScope 400 参数错误。
- **DashScope 直连策略**:
  - 运行配置调整为 `DASHSCOPE_FORCE_NO_PROXY=1`，保持系统代理设置同时对 DashScope 域名强制走 `NO_PROXY`（经 TUN 直连）。
- **错误可观测性增强**:
  - 当 DashScope 返回非 200 时，提取 `raw.code/raw.message` 回传到上层错误信息，避免“空响应”掩盖真实原因。

### 🐞 修复 (Fixed)
- 修复 `qwen3-32b` 在非流式路径下返回 `InvalidParameter: parameter.enable_thinking must be set to false for non-streaming calls` 导致的空响应问题。

### ✅ 验证 (Verification)
- 本地直接调用 `Settings.llm.chat`（`qwen3-32b`）已返回 `OK`，`raw.status_code=200`。

---

## 2026-02-10 (Hotfix v4): DashScope SSL EOF 重试策略加固

### 🎯 目标
修复聊天阶段在 SOCKS 代理链路下触发 `SSLEOFError` 时未命中回退条件的问题，避免再次出现 RAG 有引用但回答中断。

### 🛠️ 变更 (Changed)
- **`chat/query` 网络回退增强**:
  - 扩展网络错误识别规则：支持 `SOCKSHTTPSConnectionPool`、`SSLEOFError`、`Max retries exceeded`、`Cannot connect` 等文本模式。
  - 回退策略升级为三段式：
    - 保持当前代理配置先尝试；
    - 失败后自动附加 DashScope 到 `NO_PROXY` 再试；
    - 再失败时临时清空 `HTTP(S)_PROXY/ALL_PROXY` 后重试一次。
- **分类器链路对齐**:
  - `classifier` 从 `achat` 单路径改为与聊天一致的同步线程调用 + 代理回退兜底，降低上传阶段分类告警噪声。

### 🐞 修复 (Fixed)
- 修复了 `chat.py` 中“仅匹配 `dashscope.aliyuncs.com:443`”导致大量真实网络异常未触发回退的缺陷。

### 🧱 架构影响 (Architecture)
- DashScope 调用链从“单一文本匹配回退”升级为“异常模式识别 + 代理策略分层退化”，在代理波动场景下可用性显著提升。

---

## 2026-02-10 (Hotfix v3): 对话空响应闭环修复 + 进度条视觉回归

### 🎯 目标
修复“RAG 有引用但回答为空（Empty Response）”以及来源页进度条视觉噪声过高的问题，恢复稳定、可读的对话与上传体验。

### ✨ 新增 (Added)
- **后端 SSE 空响应兜底**:
  - `chat/query` 新增 `_extract_response_text()`，统一提取不同 LLM 返回结构中的正文内容。
  - 当首次响应为空时增加二次重试；重试后仍为空时，显式返回 `error` 事件，不再静默输出空白。

### 🛠️ 变更 (Changed)
- **RAG 回答生成策略**:
  - 在“检索到引用但正文为空”场景，新增基于引用内容重构 prompt 的回退生成路径，优先争取可读正文。
- **前端 SSE 解析器**:
  - `ApiClient.queryStream()` 兼容 `\n\n` 与 `\r\n\r\n` 事件分隔，减少 Windows/代理链路下的事件切分误判。
- **进度条 UI**:
  - 来源卡片从“三层叠加动画 + 扫光特效”回退为“单条进度 + 百分比 + 阶段文案”，提升信息可读性与视觉稳定性。

### 🐞 修复 (Fixed)
- 修复聊天流中“仅收到 citations、未收到 token”时前端长期停留 `...` 的问题。
- 修复 `test_chat_streaming` 与当前 `as_chat_engine.chat` 实现脱节，导致的测试失真问题。

### 🧱 架构影响 (Architecture)
- 聊天链路从“可能静默空文本”升级为“正文提取 -> 二次重试 -> 显式错误事件”的确定性收敛流程。
- 前端展示链路从“占位文本可能残留”升级为“流结束后根据 token/error 做终态收敛”，避免脏 UI 状态。

---

## 2026-02-10 (Hotfix v2): 连接兜底增强与轮询风暴进一步抑制

### 🎯 目标
继续处理“状态请求过密”“进度跳跃明显”“聊天偶发连接错误”三类残留问题。

### 🛠️ 变更 (Changed)
- **前端轮询**:
  - `AppState._startPolling()` 启动前先 `cancel` 旧定时器，避免重复创建轮询器。
  - 轮询间隔维持 5 秒，配合互斥锁减少状态请求风暴。
- **Embedding 稳定性**:
  - `smart_embedding` HTTP 调用新增失败后“临时 NO_PROXY 再试一次”兜底。
  - 单批重试策略从长退避改为短退避（最多 3 次，每次 1 秒），避免长时间卡在单个 chunk。
- **聊天稳定性**:
  - `chat/query` 失败后增加“通用回答最终降级”兜底，避免将底层网络异常直接抛到 Flutter UI。
  - 保持 SSE 结构，仍按 token 片段返回。

### 🧱 架构影响 (Architecture)
- 网络链路从“单路径失败即中断”升级为“代理路径 + 直连临时回退 + 最终业务降级”的三层容错。
- 状态轮询链路进一步收敛，降低客户端重复定时器带来的后端噪声。

---

## 2026-02-10 (Hotfix): 轮询风暴抑制与聊天连接兜底重试

### 🎯 目标
缓解上传状态接口高频请求导致的“请求看起来无数次”问题，并降低聊天阶段偶发 `Cannot connect to host dashscope.aliyuncs.com:443` 的失败率。

### 🛠️ 变更 (Changed)
- 前端状态轮询间隔从 2 秒调整为 5 秒，配合已有防重入锁，减少重复请求密度。
- 进度条增加 `TweenAnimationBuilder` 平滑补间，降低 `1/7 -> 6/7` 的视觉跳变。
- 聊天接口新增网络回退逻辑：
  - 首次失败后自动临时切换 DashScope 到 `NO_PROXY` 再重试一次。
  - SSE 错误文案改为用户可读提示，避免把底层连接栈信息直接回显到 UI。

### 🧱 架构影响 (Architecture)
- 状态拉取从“高频短轮询”收敛为“中频轮询 + UI 平滑插值”，降低接口噪声同时保持可感知进度。
- 聊天链路增加“代理失败 -> 直连回退”单次自动兜底，提高复杂网络环境可用性。

---

## 2026-02-10 (Stability Patch): 轮询防重入 + 聊天链路改同步调用

### 🎯 目标
解决上传状态接口高频重复请求，以及聊天阶段仍出现 `Cannot connect to host dashscope.aliyuncs.com:443 ssl:default [None]` 的问题。

### 🛠️ 变更 (Changed)
- **前端轮询防重入**:
  - `AppState` 轮询新增 `_isPolling` 互斥锁，防止 `Timer.periodic` 在上一次请求未结束时重入，减少重复状态请求风暴。
  - `AppState.dispose()` 中显式取消 `_statusPollingTimer`，避免生命周期泄漏。
- **聊天 API 稳定化**:
  - `chat/query` 改为优先使用同步调用（`llm.chat` / `chat_engine.chat`）并通过 `asyncio.to_thread` 执行，规避异步底层连接在代理环境中的不稳定问题。
  - 保留 SSE 输出，改为将完整响应按小片段切分后逐段推送，前端体验保持流式。

### 🧱 架构影响 (Architecture)
- 状态拉取从“可能并发重入”收敛为“单航道轮询”，显著降低服务端重复请求压力。
- 聊天链路从“异步 SDK 直连”调整为“同步调用线程化 + SSE 封装”，提升代理/TUN 环境稳定性。

---

## 2026-02-10 (Chat + Progress): 修复聊天检索 EOF 并细化 Chunk 进度动画

### 🎯 目标
解决聊天阶段仍触发 `SOCKSHTTPSConnectionPool ... SSLEOFError`，并修复 Embedding 进度“卡在 5/11”与可视反馈不足问题。

### 🛠️ 变更 (Changed)
- **聊天检索链路 Embedding 替换**:
  - 新增 `DashScopeHTTPEmbedding`（`server/app/services/dashscope_http_embedding.py`），通过 HTTP 批量接口实现查询向量，不再走 SDK 内部并发单条路径。
  - `settings.init_llama_index()` 改为注入 `DashScopeHTTPEmbedding` 作为全局 `embed_model`，覆盖聊天/RAG 查询阶段。
- **Chunk 进度细粒度**:
  - `EMBED_BATCH_SIZE` 默认值从 `5` 调整为 `1`，使 Embedding 阶段可按 chunk 逐步推进，避免长时间停在 `5/11`。
- **进度条动画增强**:
  - 来源卡片进度条增加流动高光动画（`AnimationController + 渐变遮罩`），在真实数值推进基础上提升“正在进行中”的可感知性。

### ✨ 新增 (Added)
- 新增测试 `server/tests/test_dashscope_http_embedding.py`，覆盖 HTTP embedding 返回排序逻辑。

### 🧱 架构影响 (Architecture)
- 查询阶段 embedding 与入库阶段 embedding 统一为“后端可控 HTTP 实现”，降低第三方 SDK 并发策略导致的网络抖动风险。

---

## 2026-02-10 (UX + Pipeline): 任务进度改为真实阶段驱动

### 🎯 目标
将上传任务从“固定文案 + 粗粒度进度”升级为“后端真实阶段驱动 + 前端逐任务细粒度展示”，尤其细化 Chunk Embedding 阶段。

### ✨ 新增 (Added)
- 后端 ingestion 进度改为结构化 JSON：
  - `progress`：0~1 实时进度
  - `stage`：阶段标识（如 `chunking`/`embedding`/`indexing`）
  - `message`：阶段文案
  - `detail`：附加细节（如 `embedded_chunks/total_chunks`）
- 前端 `SourceItem` 新增：
  - `stage`
  - `stageMessage`

### 🛠️ 变更 (Changed)
- `GET /api/v1/files/{doc_id}/status` 支持返回 `stage/message/detail`，并兼容旧的纯数字进度缓存值。
- 前端来源卡片状态文案改为读取服务端阶段文案，不再固定“正在上传/AI 正在解析”。
- 进度条改为真实 `source.progress` 驱动，按任务单独更新。
- Embedding 阶段进度按已处理 chunk 数增量推进，文案显示 `计算向量中 (x/y)`。

### 🐞 修复 (Fixed)
- 修复 `StorageService` 缺失 `read_file` 导致 `/files/{doc_id}/classify` 报错的问题。
- 修复 `SourceItem.copyWith` 更新状态时丢失 `fileHash` 的问题。

### 🧱 架构影响 (Architecture)
- 状态链路从 `worker内部浮点进度` 升级为 `worker阶段事件 -> Redis结构化进度 -> API -> 前端任务卡片`，实现可观测且可解释的全链路进度系统。

---

## 2026-02-10 (Critical Fix): 绕开 LlamaIndex 并发 Embedding 路径

### 🎯 目标
修复在代理/TUN网络下，`llama-index` 对 DashScope embedding 的并发单条请求容易触发 `SSLEOFError` 的核心问题。

### 🛠️ 变更 (Changed)
- `SmartEmbeddingManager` 改为 HTTP 批量调用 DashScope embedding 接口：
  - 每批 `texts` 发起一次请求（单连接单请求），不再走 `aget_text_embedding_batch()` 的并发单条调用路径。
  - 返回结果按 `text_index` 排序后回填，确保向量顺序与输入一致。
- 继续保留分批策略（`EMBED_BATCH_SIZE`）与每批重试机制。

### ✨ 新增 (Added)
- 新增测试 `server/tests/test_smart_embedding_http_batch.py`，覆盖 HTTP 返回解析与顺序校验。

### 🧱 架构影响 (Architecture)
- embedding 调用链从 `LlamaIndex SDK 并发请求` 调整为 `Server 自控批量 HTTP 请求`，显著降低 TLS 握手放大与代理链路抖动风险。

---

## 2026-02-10 (DX): 新增 Windows 一键启动 Flutter 脚本

### 🎯 目标
降低 Windows + Gsou Cloud 代理环境下 Flutter 开发启动门槛，避免每次手动设置环境变量。

### ✨ 新增 (Added)
- 新增脚本 `client/run_windows.ps1`：
  - 自动设置 `PUB_HOSTED_URL` 与 `FLUTTER_STORAGE_BASE_URL` 镜像源。
  - 自动设置 `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/NO_PROXY`。
  - 默认执行 `flutter pub get` 后执行 `flutter run -d windows`。
  - 支持参数：
    - `-Device` 指定运行设备（默认 `windows`）
    - `-SkipPubGet` 跳过依赖拉取

### 🧱 架构影响 (Architecture)
- 将“网络配置 + 依赖拉取 + 启动运行”从人工命令串收敛为单脚本入口，降低环境漂移和手工误操作概率。

---

## 2026-02-10 (Server Stability): Embedding 分批提交，降低 TLS/代理链路抖动

### 🎯 目标
解决上传索引时一次性提交大量文本块（如 20 chunks）导致 DashScope TLS 连接不稳定、触发 `SSLEOFError` 的问题。

### ✨ 新增 (Added)
- 配置项 `EMBED_BATCH_SIZE`（默认 `5`），用于控制 embedding 批量请求大小。
- `SmartEmbeddingManager._iter_batches()`：统一分批迭代逻辑。
- 新增测试 `server/tests/test_smart_embedding_batching.py` 覆盖分批切分与边界输入。

### 🛠️ 变更 (Changed)
- `smart_embedding` 从“单次大批量请求”改为“分批顺序请求 + 每批独立重试 + 进度回调增量更新”。

### 🧱 架构影响 (Architecture)
- 关键链路从 `20 chunks -> 1 request` 调整为 `20 chunks -> 4 requests(5x4)`，显著降低单连接 TLS 压力与代理抖动放大效应。

---

## 2026-02-10 (Proxy Protocol Fix): 切换到 SOCKS5 代理并补齐依赖

### 🎯 目标
修复 DashScope 在 `26001` 端口通过 `http://` 代理握手超时的问题，改为匹配 Gsou TUN 的 SOCKS 代理协议。

### 🛠️ 变更 (Changed)
- `server/.env`:
  - `HTTP_PROXY` 改为 `socks5h://127.0.0.1:26001`
  - `HTTPS_PROXY` 改为 `socks5h://127.0.0.1:26001`
  - 保持 `DASHSCOPE_FORCE_NO_PROXY=0`
- `server/requirements.txt`:
  - 新增 `PySocks`，让 `requests/urllib3` 具备 SOCKS 代理支持。

### 🧱 架构影响 (Architecture)
- 代理链路从 HTTP CONNECT 切换为 SOCKS5，网络协议与本地代理端口能力对齐，避免 TLS 握手阶段超时/EOF。

---

## 2026-02-10 (Env Config): 更新本地代理端口为 26001

### 🎯 目标
使服务端 Python 进程通过 Gsou Cloud TUN 代理访问 DashScope，避免直连导致的 SSL EOF。

### 🛠️ 变更 (Changed)
- 更新 `server/.env`：
  - `HTTP_PROXY=http://127.0.0.1:26001`
  - `HTTPS_PROXY=http://127.0.0.1:26001`
  - `DASHSCOPE_FORCE_NO_PROXY=0`

---

## 2026-02-10 (Server Proxy Fix): .env 代理配置注入到 Python 进程

### 🎯 目标
修复 `.env` 中已配置 `HTTP(S)_PROXY` 但 DashScope SDK 实际未使用，导致 Worker 仍然直连并触发 `SSLEOFError` 的问题。

### ✨ 新增 (Added)
- `Settings.apply_network_settings()`:
  - 启动时将 `HTTP_PROXY/HTTPS_PROXY/NO_PROXY` 同步写入 `os.environ`（含大小写变量），确保 requests/SDK 能读取。
  - 支持 `DASHSCOPE_FORCE_NO_PROXY=true` 时附加 DashScope 域名到 `NO_PROXY`。
- 新增测试 `server/tests/test_network_settings.py`，覆盖代理注入与 NO_PROXY 强制策略。

### 🛠️ 变更 (Changed)
- `main.py` 与 `celery_app.py` 在 `settings.init_llama_index()` 之前统一调用 `settings.apply_network_settings()`。
- Celery `worker_process_init` 钩子中重复应用网络设置，避免子进程环境漂移。
- 启动时新增网络配置生效日志（仅显示 set/unset，不输出敏感代理地址），用于快速确认代理是否注入成功。

### 🧱 架构影响 (Architecture)
- 网络配置链路从“.env 仅被配置对象读取”升级为“.env -> settings -> os.environ -> SDK”，补齐了代理生效闭环。

---

## 2026-02-10 (Server Network Fix): TUN/代理环境下 DashScope 连接稳定性修复

### 🎯 目标
解决在 Gsou Cloud 规则模式 TUN 环境下，Python Worker 上传索引阶段频繁出现 `SSLEOFError` 的问题，并减少错误重试导致的长时间卡住。

### ✨ 新增 (Added)
- **可配置直连开关**:
  - 新增 `DASHSCOPE_FORCE_NO_PROXY` 环境变量（默认关闭）。
  - 仅在显式开启时，才为 DashScope 设置 `NO_PROXY` 直连策略。

### 🛠️ 变更 (Changed)
- **网络初始化策略收敛**:
  - `main.py` 与 `celery_app.py` 不再无条件强制 DashScope 绕过代理。
  - 删除默认不安全 SSL 上下文注入逻辑，避免对第三方 HTTP 客户端产生不可预期副作用。
- **任务重试策略优化**:
  - 新增 `worker/retry_policy.py`，统一定义不可重试错误判定。
  - 对 `SSLEOFError`、`AuthenticationError`、缺失 Embedding Key 等错误不再进行 Celery 指数退避重试，直接失败并返回状态。

### 🐞 修复 (Fixed)
- 修复了代理/TUN 场景下被强制 `NO_PROXY` 导致的 DashScope 连接失败问题。
- 修复了网络硬错误场景中任务长时间重复重试、前端状态迟迟不收敛的问题。

### 🧱 架构影响 (Architecture)
- 网络链路从“硬编码直连”调整为“环境驱动可切换（代理/直连）”，提高跨网络环境可移植性。
- 错误处理链路从“统一重试”细化为“可重试/不可重试分流”，状态收敛速度和可观测性显著提升。

---

## 2026-02-10 (Server Hotfix): 修复 Embedding SSL EOF 回归

### 🎯 目标
修复上传索引流程中由网络补丁引入的 `SSLEOFError` 回归，恢复稳定的向量化调用链路。

### 🛠️ 变更 (Changed)
- **SmartEmbedding 网络策略回退**:
  - 移除 `smart_embedding` 中“清空代理环境变量 + 每次重建客户端”的高风险逻辑。
  - 恢复优先使用全局初始化的 `self.embed_model` 进行批量 embedding 调用，保持与服务启动时一致的网络/SSL行为。
  - 仅在全局模型缺失时，才使用 `DASHSCOPE_EMBED_API_KEY -> DASHSCOPE_API_KEY` 兜底创建临时模型。

### 🐞 修复 (Fixed)
- 修复了文件上传后进入 embedding 阶段高概率触发：
  - `HTTPSConnectionPool(... SSLEOFError: UNEXPECTED_EOF_WHILE_READING)` 的回归问题。

### 🧱 架构影响 (Architecture)
- 关键调用链从“运行时动态改网络环境”收敛为“启动期统一配置 + 运行期稳定复用”，降低了环境相关不确定性与线上漂移风险。

---

## 2026-02-10 (Server Fix): 上传链路鉴权失败与任务状态纠偏

### 🎯 目标
修复服务端文件上传后在向量化阶段频繁失败的问题，并确保失败状态能被前端准确感知。

### ✨ 新增 (Added)
- **失败原因透出**:
  - `GET /api/v1/files/{doc_id}/status` 在 `failed` 状态下新增 `error` 字段，直接返回后端记录的失败原因，便于前端提示与排障。

### 🛠️ 变更 (Changed)
- **Embedding Key 解析策略**:
  - `SmartEmbeddingManager` 新增 `_resolve_embed_api_key()`，优先读取 `DASHSCOPE_EMBED_API_KEY`，再回退到 `DASHSCOPE_API_KEY`。
  - 统一使用 `settings.EMBED_MODEL_NAME`，避免硬编码模型名造成配置漂移。

### 🐞 修复 (Fixed)
- **鉴权错误根因修复**:
  - 修复了嵌入请求重建客户端时错误读取 `DASHSCOPE_API_KEY` 的问题，避免仅配置 `DASHSCOPE_EMBED_API_KEY` 时出现 `AuthenticationError`。
- **任务状态一致性修复**:
  - `ingestion` 流水线捕获异常后不再静默吞掉，而是写入 `FAILED` 状态后重新抛出异常，防止 Celery 任务被误记为 `success`。

### 🧱 架构影响 (Architecture)
- **状态链路更闭环**:
  - 关键变量流向从 `Embedding API Key` -> `SmartEmbeddingManager` -> `DashScopeEmbedding` 调用链实现单一来源配置。
  - 关键状态流向从 `ingestion 异常` -> `Document.status/error_msg` -> `status API` -> `前端提示` 形成可观测闭环。

---

## 2026-02-09 (UI Polish): 空状态与视觉微调

### 🎯 目标
优化应用在初次使用或内容为空时的视觉体验，消除单调感，引导用户快速上手。

### ✨ 体验优化 (Changed)
- **首页空状态 (Home)**:
  - 移除了启动时自动创建“我的笔记本”的逻辑，允许纯净启动。
  - 优化了首页无笔记时的引导页设计 (大图标 + CTA 引导)。
- **来源列表空状态 (Sources)**:
  - 为笔记详情页的来源列表设计了全新的空状态。
  - 增加了居中的 `CloudUpload` 图标、描述性文字以及“立即导入”的快捷按钮，操作路径更短。

### 🛠️ 架构调整 (Architecture)
- **AppState**: 彻底移除了 `seedDemoData` 方法，净化了初始化逻辑。

---

## 2026-02-09 (Feature): 智能搜索与文档分类

### 🎯 目标
实现基于 Emoji 的文档智能分类，并提供全域笔记搜索功能，进一步提升信息组织效率。

### ✨ 新增功能 (Added)
- **智能分类 (Classification)**:
  - 后端集成 LLM 分类服务，能够根据文档内容自动打标 Emoji (如 📐 数学, ⚛️ 物理)。
  - `Document` 模型新增 `emoji` 字段，并在文件上传/索引阶段自动执行分类。
  - 新增 API `/files/{id}/classify` 支持按需重分类。
- **智能搜索栏 (Interactive Search)**:
  - 首页新增悬浮式搜索栏，支持平滑展开/收起动画。
  - 实现了基于标题和摘要的实时笔记过滤功能。
  - 优化了无搜索结果时的空状态展示。

### 🛠️ 架构调整 (Architecture)
- **Database**: `documents` 表新增 `emoji` 列 (Migration `015ec0f3c03d`)。
- **State Management**: `AppState` 新增搜索状态管理，解耦了数据源与视图展示。

---

## 2026-02-08 (Docs & License): 项目文档标准化

### 🎯 目标
完成项目文档的全面重构，明确技术路线图，并配置标准开源协议。

### ✨ 文档更新 (Added)
- **Apache 2.0 License**: 正式配置开源许可证文件。
- **README Pro**: 全面重写项目主文档，涵盖核心架构、双层去重算法、技术栈选型及未来路线图。

---

## 2026-02-08 (UI Refinement): 视觉体验打磨与风格回归

### 🎯 目标
提升全界面的阅读舒适度，恢复并优化简约的输入框风格。

### ✨ 体验优化 (Changed)
- **字体全面升级**: 
  - 调大了全局字体基准（Body 16-18pt, Title 22pt）。
  - 聊天正文提升至 17pt，显著增强了阅读清晰度。
- **输入框样式回归**:
  - 恢复了经典的“单横线 (Underline)”交互风格。
  - 优化了激活状态下的线条粗细与颜色过渡，视觉更加轻盈、现代。

---

## 2026-02-08 (Final Polish): 交互体验大改版与删除功能闭环

### 🎯 目标
提升跨平台（PC/移动端）的输入与操作体验，实现源文件的深度管理（索引清理），并完成全界面中文本地化。

### ✨ 新增功能 (Added)
- **源文件深度删除**:
  - 为文件卡片增加了红色垃圾桶图标。
  - **索引同步清理**: 删除操作会同步移除服务器向量库中的相关节点，确保 RAG 检索结果的实时准确性。
- **AI 气泡动作栏**:
  - **复制功能**: 支持一键复制 AI 回复的纯文本（含 Emoji），并提供简约美观的浮动提示。
  - **分享接口**: 预留了分享功能入口。
  - **自适应动画**: 移动端支持点击气泡后通过平滑动画展开动作图标，电脑端则直接显示。

### 🛠️ 交互优化 (Changed)
- **智能输入框**:
  - **电脑端**: 实现 `Enter` 键直接发送，`Ctrl + Enter` 换行，极大地提升了对话效率。
  - **移动端**: 保持 `Enter` 换行的原生习惯，避免误发。
  - 增加了自动增高的多行输入支持。
- **全界面本地化**: 将所有 UI 标签、导航、弹窗提示及占位符统一为中文表述。

### 🐞 修复 (Fixed)
- 修复了 `AppState` 和 `ChatPage` 在处理复杂异步交互时的上下文稳定性问题。

---

## 2026-02-08 (Refined): 架构审计与 RAG 深度优化

### 🎯 目标
执行质量守卫者 (Quality Guardian) 审计，彻底解决后端脏数据残留、RAG 检索重复内容及自检逻辑不彻底的问题。

### 🛠️ 核心修复 (Architecture & Dedup)
- **后端 (API & RAG)**:
  - **自愈式 /check**: 接口现在在检查哈希前会主动清理数据库中状态异常或索引丢失的旧记录，确保上传链路 100% 畅通。
  - **RAG 内容去重**: 引入了检索节点的内容级去重 (Node Deduplication)，即便用户选择了多个重复文件，AI 也只会参考一份唯一内容，消除了“系统检测到重复”的冗余回答。
  - **深度召回**: 将 `similarity_top_k` 提升至 15，确保去重后仍有充足的上下文。
- **前端 (Flutter)**:
  - **哈希持久化**: `SourceItem` 现在会持久化存储文件哈希值。
  - **本地自检进化**: `checkNotebookHealth` 现在能同时识别“后端不存在 (404)”和“本地哈希重复”两种异常，并执行物理清理。
  - **弹窗交互**: 优化了清理结果的弹窗反馈。

### ✨ 体验优化
- **UI 细节**: 统一英文字体为 `Consolas`，优化了聊天气泡的最大宽度限制 (75%)。
- **交互逻辑**: 实现了笔记本首次打开滚到顶、随后记忆位置的智能滚动逻辑。

---

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
## 2026-02-10 (Stability Hardening): 审查报告闭环修复（P0/P1/P2）

### 🎯 目标
按《Consolidated_Review_Report.md》逐项修复高风险缺陷，完成前端交互崩溃点、流式对话可控性、后端数据一致性与缓存隔离的闭环加固。

### ✨ 新增 (Added)
- 前端新增可中断的流式会话控制：
  - `StreamCancelToken`（`client/lib/core/api_client.dart`）
  - 聊天输入区新增“停止生成”按钮（`client/lib/features/chat/chat_page.dart`）
- 后端新增数据库迁移：
  - `server/alembic/versions/7c2c5e9f1d4a_harden_document_and_cache_constraints.py`
  - 为 `documents.status` 增加合法值约束
  - 为 `documents` 增加 `(notebook_id, file_hash)` 唯一约束
  - 将 `chunk_cache` 升级为 `(text_hash, model_name)` 复合主键

### 🛠️ 变更 (Changed)
- `NotebookPage` 在目标笔记本被删除时不再 `firstWhere` 崩溃，改为安全提示并返回上级页面。
- 聊天键盘事件处理改为 `KeyEventResult.handled`，修复桌面端 Enter 发送后残留空行。
- 聊天 SSE 超时从 `60s` 收敛为 `30s`，并在取消/异常后恢复输入状态。
- `AppState.isProcessing` 扩展为“全局处理中 + 来源处理中”联合判定，上传处理中禁发消息。
- 来源删除交互增加防抖与反馈：删除按钮 loading、失败提示、成功提示。
- 上传状态映射修正：`already_exists -> SourceStatus.ready`，并同步初始阶段文案为“处理完成”。
- `SmartEmbeddingManager` 查询缓存时加入 `model_name` 条件，避免跨模型误复用旧向量。
- 文件上传接口增加前置重复检测和并发冲突兜底，降低脏数据时代码路径异常概率。

### 🐞 修复 (Fixed)
- 修复笔记本在异端删除后页面重建崩溃问题。
- 修复聊天输入 Enter 与 TextField 默认行为冲突导致的额外换行问题。
- 修复流式请求卡死后前端长期处于不可输入状态的问题。
- 修复来源删除“无加载、无错误提示”的静默失败体验缺陷。
- 修复 `already_exists` 被错误映射为 `queued/processing` 导致 UI 长时间转圈的问题。
- 修复 `ChunkCache` 仅按 `text_hash` 命中造成不同 embedding 模型缓存污染的问题。
- 修复删除文档后 Artifact 无引用仍残留的 CAS 孤儿文件问题（新增引用检查 + 物理清理）。

### 🧱 架构影响 (Architecture)
- 前端对话链路由“单向等待”升级为“可取消流 + 超时收敛 + 状态可恢复”的可控状态机。
- 后端数据层从“弱约束字符串状态 + 单键缓存”升级为“受约束状态 + 唯一性保障 + 模型隔离缓存键”。
- 文件生命周期从“删文档即结束”升级为“删文档 -> 引用检测 -> Artifact/CAS 清理”的闭环回收链路。

### ✅ 验证 (Verification)
- Flutter 静态检查：
  - `flutter analyze lib/app/app_state.dart lib/core/api_client.dart lib/features/chat/chat_page.dart lib/features/notebook/notebook_page.dart lib/features/sources/sources_page.dart`
- Python 语法检查：
  - `python -m py_compile` 覆盖修改后的 `models/services/endpoints/migration` 文件
- Pytest 子集：
  - `tests/test_full_suite.py`（上传生命周期）
  - `tests/test_smart_embedding_batching.py`
  - `tests/test_smart_embedding_key_resolution.py`
