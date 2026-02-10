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
