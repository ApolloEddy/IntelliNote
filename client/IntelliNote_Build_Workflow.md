# IntelliNote_Build_Workflow

面向：IntelliNote智记 —— “类似 NotebookLM 的知识库学习助手”

目标：用 Flutter 做跨平台（Android 手机/平板优先，Windows 次优），围绕“卡片（Notebook）→来源（Sources）→对话（Chat）→学习室（Studio）→可沉淀的笔记（Notes）”形成闭环。本文把项目从 0 到可用、再到产品化的实现流程，拆成可执行的工作流与细分功能块（含构件/模块/接口/数据结构/任务队列/测试与部署）。

---

## 1. 产品边界与设计原则

### 1.1 MVP 必须覆盖的能力
1) Notebook（卡片）管理：创建、重命名、删除、封面 emoji、摘要、最近访问、排序与搜索。
2) Sources（来源）导入与管理：粘贴文本（必选）、文件导入（TXT/MD 必选；PDF/Docx 作为迭代）、来源文件夹分组。
3) Ingestion（入库流水线）：解析 → 清洗 → 切分 chunk → 向量化 embedding → 索引构建 → 生成 Notebook 摘要与建议问题。
4) Chat（对话）：用户提问 → 检索证据 → LLM 回答；回答必须附带可点击的引用（能定位到来源 chunk/页码）。
5) Studio（学习室）：至少 2 项学习产物生成（建议：Study Guide + Quiz；或 Study Guide + Flashcards），并可保存为 Notes。

### 1.2 明确不做（先不做，避免架构跑偏）
- 多人协作/实时共享编辑
- 生产级音频播客（可留扩展位）
- 自动构建复杂知识图谱（可后续迭代）

### 1.3 三条“硬原则”
- 可追溯：任何“事实型陈述”必须能定位到来源文本；无法支持时要明确说“来源中未找到”。
- 可控：用户可以决定引用范围（全库/文件夹/单文件/手选来源）；默认尊重范围。
- 可替换：Embedding/LLM/向量库必须抽象成 Provider，方便切换国内云/海外云/本地模型。

---

## 2. 总体架构与两种落地模式

### 2.1 推荐总体结构（客户端 + 任务执行层 + 可选后端）
- Flutter 客户端：UI、状态管理、离线数据库、文件管理、请求编排、缓存。
- Ingestion Worker：负责重 CPU/IO 的解析与 embedding；可以是本地 worker（Isolate + 原生库），也可以是云端 worker。
- 可选后端 API：鉴权、同步、配额、日志、统一密钥管理、检索与引用聚合。

### 2.2 两种模式（从第一天就兼容）
A. Local-first（纯本地优先）
- 数据：SQLite + 本地文件系统（App sandbox）
- 服务：Embedding/LLM 走云 API（最省事）或本地模型（后期）
- 风险：移动端 PDF 解析 + embedding 批处理会很吃性能，必须有 JobQueue/Isolate。

B. Server-backed（推荐，尤其你后续想做“联考知识库”）
- 客户端只存元数据与缓存
- 后端负责 chunk/embedding/index/检索
- 好处：性能稳定、多端同步方便、可做评测/AB、密钥不下发到客户端。

---

## 3. 仓库与工程基线（建议的目录与模块划分）

### 3.1 Flutter（Clean Architecture）
建议以 feature 为中心拆分：

```
lib/
  app/                 # 路由、主题、全局依赖注入
  core/
    domain/            # Entity / ValueObject / UseCase 接口
    data/              # Repository 实现、DTO、SQLite 表结构
    infra/             # HTTP/WS 客户端、文件IO、加密、日志
    ui/                # 通用UI组件（卡片、菜单、列表、对话气泡等）
  features/
    home/              # Notebook 列表页
    notebook/          # Notebook 详情页（三个 tab 壳子）
    sources/           # 来源管理与预览
    chat/              # 对话与引用
    studio/            # 学习室
    notes/             # 笔记列表与编辑
    settings/          # 设置
main.dart
```

状态管理：Riverpod 或 Bloc 均可，关键是：
- 异步任务可观测（Job 状态能实时反映到 UI）
- 业务逻辑可测试（UseCase 与 Repository 分离）

### 3.2 后端（可选，但推荐）
- API：REST（简单）或 gRPC（高效）
- Worker：队列驱动（Redis + BullMQ / Celery / Sidekiq 等任一）
- 存储：PostgreSQL（元数据）+ 对象存储（原文/解析产物）+ 向量库（pgvector / Milvus / Qdrant）

---

## 4. 数据模型（先定 schema，避免返工）

### 4.1 核心实体与字段
Notebook（卡片）
- id, title, emoji, summary
- createdAt, updatedAt, lastOpenedAt
- settings: defaultScope, retrievalPolicy, answerStyle

Folder（来源文件夹）
- id, notebookId, name, parentId?

Source（来源）
- id, notebookId, folderId?
- type: file | paste | url
- name, uri/path, mimeType, size, sha256
- status: queued | processing | ready | failed
- meta: pageCount, language, createdAt

Chunk（最小检索单元）
- id, notebookId, sourceId, ordinal
- text, tokenCount
- pageRef?（PDF 页码）
- startOffset, endOffset（用于高亮）
- fingerprint（去重/近重复）

Embedding
- chunkId, model, dim, vector(blob)

ChatSession / ChatMessage
- sessionId, notebookId, title, createdAt
- messageId, sessionId, role(user|assistant), content, createdAt
- citations: List<Citation>

Citation（引用）
- messageId, chunkId, sourceId
- quoteStart, quoteEnd
- score
- display: page?, snippet（便于 UI 展示）

Note（沉淀内容）
- id, notebookId
- type: written | saved_response | study_guide | quiz | flashcards
- title, contentMarkdown
- provenance: fromSessionId?, fromMessageId?, fromStudioJobId?

Job（任务队列）
- id, type: ingest | embed | index | summarize | studio_generate_xxx
- notebookId, sourceId?
- state: queued | running | done | failed | canceled
- progress(0..1), error, createdAt, startedAt, finishedAt

---

## 5. 端到端工作流（用户动作 → 系统流水线）

下面每条 workflow 都给出“触发条件、核心步骤、涉及构件、验收点”。

### 5.1 Workflow A：创建 Notebook
触发：Home 页右下角“+”
- Step 1：弹窗输入 title + 选择 emoji（默认随机）
- Step 2：写入 Notebook 表，lastOpenedAt=now
- Step 3：跳转 Notebook 详情页（默认 Sources tab）
构件：NotebookCreateDialog / NotebookRepository / HomeController
验收：Home 列表出现新卡片；进入详情页不卡顿。

### 5.2 Workflow B：导入来源（Sources）
触发：Sources tab 点击“导入”
- B1 粘贴文本：生成 Source(type=paste) → 入队 ingest job
- B2 文件导入：复制文件到 sandbox → 生成 Source(type=file) → 入队 ingest job
- B3 URL（可选）：抓取文本 → 生成 Source(type=url) → 入队 ingest job
构件：ImportBottomSheet / SourceImportService / JobQueue
验收：来源卡片即时出现，状态从 queued→processing→ready（失败可重试）。

### 5.3 Workflow C：Ingestion（入库流水线）
触发：Job(type=ingest) 被 worker 执行
建议拆成可重试的子步骤：
1) Acquire：读取文件/文本/URL；计算 sha256
2) Parse：统一输出 ParsedDocument(pages,text,meta)
3) Normalize：清洗（去多余空白/页眉页脚/断行）
4) Chunk：切分 chunk（保留 offset/pageRef）
5) Embed：批量 embedding（限速+重试）
6) Index：写入向量索引（或写入表，检索层负责搜索）
7) Summarize：更新 Notebook summary + suggested questions
构件：DocumentParser / Normalizer / Chunker / EmbeddingProvider / VectorStore / Summarizer
验收：
- chunk 数量合理（不会过碎/过长）
- 任意问题能检索到相关 chunk（至少 topK 命中）
- Notebook 自动出现摘要与建议问题

### 5.4 Workflow D：Chat（带引用的 RAG 对话）
触发：Chat 输入框发送
- Step 1：用户选择引用范围（默认“全部来源”）
- Step 2：Retriever 根据范围过滤候选 chunks
- Step 3：PromptBuilder 组装：系统约束 + evidence chunks + 用户问题
- Step 4：LLM 流式输出（推荐）
- Step 5：CitationResolver 解析引用标号，落库 citations
- Step 6：UI 支持点击引用 → 打开引用侧栏/来源预览并高亮
构件：ChatComposer / ScopeSelector / RagOrchestrator / CitationPanel
验收：
- 回答中出现引用标号，点击能看到对应原文片段
- 改变 scope 会改变答案证据（可控）

### 5.5 Workflow E：Save to Note（沉淀）
触发：对话中点击“保存为笔记”或 Studio 生成后点击“保存”
- Step 1：生成 Note(type=...)，写入 markdown 内容
- Step 2：记录 provenance（来源 session/message/job）
- Step 3：Notes 列表可查看、编辑（written note 可编辑；saved_response 可选只读）
构件：SaveToNoteButton / NotesRepository / NoteEditor
验收：保存后立即可在 Notes tab 搜到；可跳回来源或会话。

### 5.6 Workflow F：Studio（学习室生成）
触发：Studio 选择某个工具（Study Guide / Quiz / Flashcards）
通用步骤：
1) ConfigSheet：范围/难度/数量/长度
2) 入队 studio_generate_xxx Job
3) Worker：检索关键 chunks → LLM 结构化生成（JSON）→ 转 markdown → 存为 Note
4) UI 展示产物；支持“继续追问”与“保存/导出”
推荐 MVP 两项：
- Study Guide：提纲 + 重点 + 易错点 + 练习方向（可直接用于联考复习）
- Quiz：题目 + 答案 + 解析（解析必须引用 chunk）
构件：StudioToolCard / StudioJobRunner / QuizPlayer / StudyGuideRenderer
验收：产物生成可复现（同范围/同设置结果稳定）；引用可点开。

---

## 6. 关键子系统与设计构件（按“可替换、可测试、可观测”设计）

### 6.1 JobQueue（统一长任务机制）
要求：任何耗时任务都必须入队，UI 只订阅状态。
- JobRepository：落库（state/progress/error）
- WorkerRunner：本地 Isolate 或后端队列消费者
- RetryPolicy：指数退避 + 最大重试次数
- Cancel：可取消（至少对未执行/进行中的网络请求可取消）

验收：导入 10 个来源时 UI 不冻结；重启 App 后任务状态可恢复。

### 6.2 Parser/Chunker 设计
- DocumentParser 接口：parse(path|bytes) -> ParsedDocument
- Normalizer：规则可配置（regex 列表）
- Chunker：按结构切分

切分策略（可落地的默认值）：
- chunk target size：400~800 tokens
- overlap：50~120 tokens
- 按标题/段落优先；超长段落二次拆分
- 保留：pageRef + startOffset/endOffset（引用高亮必需）

### 6.3 EmbeddingProvider / VectorStore / Retriever
EmbeddingProvider：
- embedBatch(texts) -> vectors
- 内置：rate limit、批量、重试、缓存

VectorStore：
- upsert(chunkId, vector, meta)
- search(queryVector, filter, topK)

Retriever：
- buildFilter(scope): notebookId + folderId/sourceId 列表
- search(query) -> ranked chunks

建议：
- MVP：纯向量检索
- 迭代：Hybrid（BM25 + vector 融合）
- 进一步：rerank（提高精确度）

### 6.4 RAG 编排与引用规范
强烈建议你把引用输出规范写死，避免模型自由发挥导致引用难解析。

推荐的引用协议：
- 证据块列表 evidence[i] 对应引用标号 i+1
- 模型输出在句尾写 `【1】` `【2】`
- 后处理：把 `【n】` 映射到 evidence[n-1].chunkId

PromptBuilder 的关键约束：
- “仅根据提供的 evidence 回答；若 evidence 没有，明确说没有。”
- “每个关键断言必须附带引用标号。”

### 6.5 流式输出与消息落库
- LLMClient：支持 stream token
- UI：逐步渲染
- 落库：流式结束后一次性写入最终 content + citations

### 6.6 观测与调试（后期省命）
日志应包含：
- 每次检索：query、scope、topK chunkIds、score
- 每次生成：模型、prompt 版本、token 用量、耗时
- ingestion：每一步耗时、chunk 数量、失败原因

---

## 7. UI 设计构件映射（对齐你给的 Figma prompt）

### 7.1 初始页（Home / NotebookList）
- 顶部左上角标题
- 主体横条卡片：emoji 缩略图 + 标题 + 小摘要 + 右侧 “…”
- 右下角 FAB “+” 创建
- 左侧 Drawer：用户/入口/设置

Flutter 构件：Scaffold + Drawer + SliverList + FloatingActionButton + PopupMenuButton

### 7.2 Notebook 详情页
- AppBar：返回 + 标题 + “…”
- 底部 Tab：Sources / Chat / Studio（建议用 BottomNavigationBar + IndexedStack 保持状态）

### 7.3 Sources tab
- 文件夹树 + 来源列表
- 导入入口（按钮/FAB）
- 来源卡片：状态/进度/失败重试
- 来源预览：文本/分页 PDF；引用跳转定位

### 7.4 Chat tab
- 顶部：Notebook 摘要 + 建议问题 chips
- 消息区：气泡 + 引用标号
- 输入区：可扩展输入框 + 引用范围按钮 + 发送
- 引用侧栏：展示 chunk 片段 + 高亮

### 7.5 Studio tab
- 工具卡片：Study Guide / Quiz / Flashcards
- 生成参数 sheet
- 结果展示页 + 保存为 Note

---

## 8. 里程碑计划（按“能跑起来→好用→产品化”）

### Milestone 1：MVP（核心闭环）
范围：
- Notebook CRUD
- Sources：粘贴文本 + TXT/MD
- JobQueue + ingestion（chunk + embedding + 简单检索）
- Chat：RAG + 引用点击
- Studio：Study Guide（生成并保存 Note）

验收标准：
- 导入 3 份资料后能问答；回答引用可打开原文片段
- Study Guide 可生成并在 Notes 中查看

### Milestone 2：可用性增强
范围：
- PDF 解析 + 页码引用
- 来源文件夹管理、范围选择
- Quiz 生成 + 做题 UI + 解析引用
- 性能优化：批量 embedding、缓存、流式

验收标准：
- PDF 引用能跳到对应页
- Quiz 做题与解析可用，解析可追溯

### Milestone 3：产品化
范围：
- 多端同步（可选）
- Hybrid retrieval / rerank（可选）
- Flashcards + SRS
- 权限/配额/日志/崩溃收集
- 导出分享（Markdown/PDF）

---

## 9. 测试与评测（确保“可追溯”不翻车）

### 9.1 单元测试
- Chunker：token 上限/overlap/offset 正确
- Retriever：scope filter 正确
- CitationResolver：引用标号映射准确

### 9.2 集成测试
- 导入 → ingestion 完成 → 可检索
- Chat：给定固定 evidence，引用解析稳定

### 9.3 质量指标（建议你做一个小评测集）
- Recall@K：正确证据 chunk 是否在 topK
- Citation precision：引用 chunk 是否真的包含支撑语句
- Hallucination rate：回答中“来源无依据”的断言比例

---

## 10. 安全与隐私

- 密钥不放客户端：推荐后端代理；若必须放本地，用系统 KeyStore/DPAPI。
- 本地数据：SQLite 可选加密；至少对 tokens/同步密钥加密。
- 删除策略：删除 notebook 必须连同 source 文件、chunks、embeddings 一起删除。
- 导出提示：提醒用户内容可能包含隐私。

---

## 11. 一套“最实操”的开发顺序（Checklist）

1) 搭 UI 壳子：Home → Notebook 详情（3 tab）→ Settings
2) Notebook CRUD：本地 SQLite + 列表展示
3) Sources（先做粘贴文本）：Source 入库 + 列表状态
4) JobQueue：入队/执行/进度/失败重试
5) Chunker：按段落切分 + overlap + offset
6) Embedding + VectorStore：先最简单可用
7) Chat：RAG 编排 + 引用协议 + 引用 UI
8) Studio：Study Guide → 保存为 Note
9) 再补：PDF 解析、Quiz、文件夹、Hybrid 检索

---

## 12. 接口定义（伪代码，方便你/Agent 直接开写）

```dart
abstract class DocumentParser {
  Future<ParsedDocument> parse({required String path, required String mimeType});
}

abstract class Chunker {
  List<ChunkDraft> chunk(ParsedDocument doc, ChunkPolicy policy);
}

abstract class EmbeddingProvider {
  Future<List<List<double>>> embedBatch(List<String> texts);
}

abstract class VectorStore {
  Future<void> upsert(String chunkId, List<double> vector, Map<String, dynamic> meta);
  Future<List<SearchHit>> search(List<double> queryVector, SearchFilter filter, int topK);
}

class RagOrchestrator {
  Future<Answer> ask({
    required String notebookId,
    required String question,
    required SourceScope scope,
    required AnswerStyle style,
  });
}
```

---

如果你希望下一步更“工程化”，我可以把 Milestone 1/2/3 直接拆成 GitHub Issues（每条包含：描述、子任务、验收标准、风险点、建议工期），你复制进仓库就能开干。
