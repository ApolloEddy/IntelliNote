import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/ingestion.dart';
import '../core/models.dart';

class AppState extends ChangeNotifier {
  final List<Notebook> notebooks = [];
  final Map<String, List<SourceItem>> sourcesByNotebook = {};
  final Map<String, List<ChunkItem>> chunksByNotebook = {};
  final Map<String, List<ChatMessage>> chatsByNotebook = {};
  final Map<String, List<NoteItem>> notesByNotebook = {};
  final Map<String, List<JobItem>> jobsByNotebook = {};

  final IngestionPipeline _pipeline = IngestionPipeline();

  void seedDemoData() {
    if (notebooks.isNotEmpty) {
      return;
    }
    final notebook = createNotebook(title: '示例笔记', emoji: '📘');
    addSourceFromText(notebookId: notebook.id, name: '示例来源', text: demoText);
  }

  Notebook createNotebook({required String title, required String emoji}) {
    final notebook = Notebook(
      id: _id(),
      title: title,
      emoji: emoji,
      summary: '尚未生成摘要',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );
    notebooks.insert(0, notebook);
    notifyListeners();
    return notebook;
  }

  void renameNotebook(String notebookId, String title) {
    final index = notebooks.indexWhere((item) => item.id == notebookId);
    if (index == -1) {
      return;
    }
    notebooks[index] = notebooks[index].copyWith(title: title, updatedAt: DateTime.now());
    notifyListeners();
  }

  void deleteNotebook(String notebookId) {
    notebooks.removeWhere((item) => item.id == notebookId);
    sourcesByNotebook.remove(notebookId);
    chunksByNotebook.remove(notebookId);
    chatsByNotebook.remove(notebookId);
    notesByNotebook.remove(notebookId);
    jobsByNotebook.remove(notebookId);
    notifyListeners();
  }

  List<SourceItem> sourcesFor(String notebookId) => sourcesByNotebook[notebookId] ?? [];
  List<ChunkItem> chunksFor(String notebookId) => chunksByNotebook[notebookId] ?? [];
  List<ChatMessage> chatsFor(String notebookId) => chatsByNotebook[notebookId] ?? [];
  List<NoteItem> notesFor(String notebookId) => notesByNotebook[notebookId] ?? [];
  List<JobItem> jobsFor(String notebookId) => jobsByNotebook[notebookId] ?? [];

  Future<void> addSourceFromText({
    required String notebookId,
    required String name,
    required String text,
  }) async {
    final source = SourceItem(
      id: _id(),
      notebookId: notebookId,
      type: SourceType.paste,
      name: name,
      status: SourceStatus.queued,
      content: text,
      createdAt: DateTime.now(),
    );
    _addSource(source);
    await _runIngestionJob(source);
  }

  Future<void> addSourceFromFile({
    required String notebookId,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    final content = String.fromCharCodes(file.bytes ?? []);
    final source = SourceItem(
      id: _id(),
      notebookId: notebookId,
      type: SourceType.file,
      name: file.name,
      status: SourceStatus.queued,
      content: content,
      createdAt: DateTime.now(),
    );
    _addSource(source);
    await _runIngestionJob(source);
  }

  Future<void> askQuestion({
    required String notebookId,
    required String question,
    SourceScope scope = const SourceScope.all(),
  }) async {
    final message = ChatMessage(
      id: _id(),
      notebookId: notebookId,
      role: ChatRole.user,
      content: question,
      createdAt: DateTime.now(),
      citations: const [],
    );
    _addChatMessage(message);

    final response = await _pipeline.answerQuestion(
      question: question,
      chunks: _applyScope(chunksFor(notebookId), scope),
      sources: sourcesFor(notebookId),
    );
    _addChatMessage(response.copyWith(notebookId: notebookId));
  }

  Future<NoteItem> generateStudyGuide({
    required String notebookId,
  }) async {
    final note = await _pipeline.generateStudyGuide(
      notebookId: notebookId,
      chunks: chunksFor(notebookId),
    );
    return _saveNote(note);
  }

  Future<NoteItem> generateQuiz({
    required String notebookId,
  }) async {
    final note = await _pipeline.generateQuiz(
      notebookId: notebookId,
      chunks: chunksFor(notebookId),
    );
    return _saveNote(note);
  }

  NoteItem saveChatToNotes({
    required String notebookId,
    required ChatMessage message,
  }) {
    final note = NoteItem(
      id: _id(),
      notebookId: notebookId,
      type: NoteType.savedResponse,
      title: '保存的回答',
      contentMarkdown: message.content,
      createdAt: DateTime.now(),
      provenance: 'session:${message.id}',
    );
    return _saveNote(note);
  }

  void _addSource(SourceItem source) {
    sourcesByNotebook.putIfAbsent(source.notebookId, () => []).insert(0, source);
    _addJob(source.notebookId, 'ingest');
    notifyListeners();
  }

  void _addChatMessage(ChatMessage message) {
    chatsByNotebook.putIfAbsent(message.notebookId, () => []).add(message);
    notifyListeners();
  }

  NoteItem _saveNote(NoteItem note) {
    notesByNotebook.putIfAbsent(note.notebookId, () => []).insert(0, note);
    notifyListeners();
    return note;
  }

  List<ChunkItem> _applyScope(List<ChunkItem> chunks, SourceScope scope) {
    if (scope.type == ScopeType.all) {
      return chunks;
    }
    return chunks.where((chunk) => scope.sourceIds.contains(chunk.sourceId)).toList();
  }

  void _addJob(String notebookId, String type) {
    jobsByNotebook.putIfAbsent(notebookId, () => []).insert(
          0,
          JobItem(
            id: _id(),
            notebookId: notebookId,
            type: type,
            state: JobState.queued,
            progress: 0,
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> _runIngestionJob(SourceItem source) async {
    _updateSourceStatus(source.id, source.notebookId, SourceStatus.processing);
    _updateJobState(source.notebookId, JobState.running);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final result = await _pipeline.ingest(
      notebookId: source.notebookId,
      sourceId: source.id,
      content: source.content,
    );

    chunksByNotebook.putIfAbsent(source.notebookId, () => []).addAll(result.chunks);
    _updateSourceStatus(source.id, source.notebookId, SourceStatus.ready);
    _updateNotebookSummary(source.notebookId, result.summary);
    _updateJobState(source.notebookId, JobState.done);
  }

  void _updateSourceStatus(String sourceId, String notebookId, SourceStatus status) {
    final list = sourcesByNotebook[notebookId];
    if (list == null) {
      return;
    }
    final index = list.indexWhere((item) => item.id == sourceId);
    if (index == -1) {
      return;
    }
    list[index] = list[index].copyWith(status: status, updatedAt: DateTime.now());
    notifyListeners();
  }

  void _updateJobState(String notebookId, JobState state) {
    final list = jobsByNotebook[notebookId];
    if (list == null || list.isEmpty) {
      return;
    }
    final index = list.indexWhere((item) => item.state != JobState.done);
    if (index == -1) {
      return;
    }
    list[index] = list[index].copyWith(state: state, progress: 1, finishedAt: DateTime.now());
    notifyListeners();
  }

  void _updateNotebookSummary(String notebookId, String summary) {
    final index = notebooks.indexWhere((item) => item.id == notebookId);
    if (index == -1) {
      return;
    }
    notebooks[index] = notebooks[index].copyWith(summary: summary, updatedAt: DateTime.now());
    notifyListeners();
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();
}

const String demoText = '''
IntelliNote 是一个面向学习场景的知识库助手，它通过导入资料、进行文本解析与切分，
再结合向量检索与问答生成，帮助用户在学习过程中快速理解和复习资料。

核心流程包括：来源导入、入库流水线、对话问答、学习室产出与笔记沉淀。
学习室可以生成学习指南、测验与闪卡，帮助用户构建自己的复习材料。

IntelliNote 的设计强调可追溯、可控与可替换三大原则，确保引用可靠且技术可扩展。
''';
