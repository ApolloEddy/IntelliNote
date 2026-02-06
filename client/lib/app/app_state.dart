import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/models.dart';

class AppState extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  
  final List<Notebook> notebooks = [];
  final Map<String, List<SourceItem>> sourcesByNotebook = {};
  // Chunks are now handled by server, no need to track locally
  final Map<String, List<ChatMessage>> chatsByNotebook = {};
  final Map<String, List<NoteItem>> notesByNotebook = {};
  final Map<String, List<JobItem>> jobsByNotebook = {};

  void seedDemoData() {
    if (notebooks.isNotEmpty) {
      return;
    }
    createNotebook(title: '我的笔记本', emoji: '📘');
  }

  Notebook createNotebook({required String title, required String emoji}) {
    final notebook = Notebook(
      id: _id(),
      title: title,
      emoji: emoji,
      summary: '本地会话',
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
    chatsByNotebook.remove(notebookId);
    notesByNotebook.remove(notebookId);
    jobsByNotebook.remove(notebookId);
    notifyListeners();
  }

  List<SourceItem> sourcesFor(String notebookId) => sourcesByNotebook[notebookId] ?? [];
  List<ChatMessage> chatsFor(String notebookId) => chatsByNotebook[notebookId] ?? [];
  List<NoteItem> notesFor(String notebookId) => notesByNotebook[notebookId] ?? [];
  List<JobItem> jobsFor(String notebookId) => jobsByNotebook[notebookId] ?? [];

  // 临时不支持纯文本粘贴，为了简化文件上传逻辑统一
  Future<void> addSourceFromText({
    required String notebookId,
    required String name,
    required String text,
  }) async {
    // 简单实现：将文本写入临时文件然后上传
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/${name}_${_id()}.txt');
    await file.writeAsString(text);
    await _uploadFile(notebookId, file, name);
  }

  Future<void> addSourceFromFile({
    required String notebookId,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md'],
    );
    
    if (result == null || result.files.isEmpty) {
      return;
    }
    
    final path = result.files.first.path;
    if (path == null) return;
    
    final file = File(path);
    await _uploadFile(notebookId, file, result.files.first.name);
  }
  
  Future<void> _uploadFile(String notebookId, File file, String filename) async {
    // 1. UI: Add placeholder source
    final sourceId = _id();
    final source = SourceItem(
      id: sourceId,
      notebookId: notebookId,
      type: SourceType.file,
      name: filename,
      status: SourceStatus.queued,
      content: 'Uploaded file',
      createdAt: DateTime.now(),
    );
    _addSource(source);
    _addJob(notebookId, 'upload:${filename}');

    try {
      // 2. Compute SHA256
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();

      // 3. Check Server (CAS)
      _updateSourceStatus(sourceId, notebookId, SourceStatus.processing);
      
      final checkResult = await _apiClient.checkFile(
        notebookId: notebookId,
        sha256: digest,
        filename: filename
      );

      if (checkResult['status'] == 'instant_success') {
        // 秒传成功
        _updateSourceStatus(sourceId, notebookId, SourceStatus.ready);
        _updateJobState(notebookId, JobState.done);
      } else {
        // 需要上传
        final uploadResult = await _apiClient.uploadFile(
          notebookId: notebookId,
          file: file
        );
        // 上传后服务器在后台处理，我们暂时标记为 Ready，或者可以轮询
        // 这里为了 UI 响应快，假设上传成功即进入处理流程
        _updateSourceStatus(sourceId, notebookId, SourceStatus.ready);
        _updateJobState(notebookId, JobState.done);
      }
    } catch (e) {
      print('Upload failed: $e');
      _updateSourceStatus(sourceId, notebookId, SourceStatus.failed);
      _updateJobState(notebookId, JobState.failed);
    }
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
    
    // Add placeholder for AI response
    final loadingId = _id();
    _addChatMessage(ChatMessage(
      id: loadingId,
      notebookId: notebookId,
      role: ChatRole.assistant,
      content: '...',
      createdAt: DateTime.now(),
      citations: const [],
    ));

    try {
      final result = await _apiClient.query(
        notebookId: notebookId, 
        question: question
      );
      
      // Replace placeholder
      _removeChatMessage(notebookId, loadingId);
      
      final citations = (result['citations'] as List).map((c) {
        return Citation(
          chunkId: c['chunk_id'] ?? 'unknown',
          sourceId: c['source_id'] ?? 'unknown',
          snippet: c['text'],
          score: c['score'] ?? 0.0,
        );
      }).toList();

      _addChatMessage(ChatMessage(
        id: _id(),
        notebookId: notebookId,
        role: ChatRole.assistant,
        content: result['answer'],
        createdAt: DateTime.now(),
        citations: citations,
      ));
      
    } catch (e) {
      _removeChatMessage(notebookId, loadingId);
      _addChatMessage(ChatMessage(
        id: _id(),
        notebookId: notebookId,
        role: ChatRole.assistant,
        content: 'Error: $e',
        createdAt: DateTime.now(),
        citations: const [],
      ));
    }
  }

  // Studio 功能暂时留空，等待服务器实现对应接口
  Future<NoteItem> generateStudyGuide({required String notebookId}) async {
    return NoteItem(
      id: _id(), notebookId: notebookId, type: NoteType.studyGuide, 
      title: 'TODO', contentMarkdown: 'Server API needed', createdAt: DateTime.now(), provenance: ''
    );
  }
  
  Future<NoteItem> generateQuiz({required String notebookId}) async {
    return NoteItem(
      id: _id(), notebookId: notebookId, type: NoteType.quiz, 
      title: 'TODO', contentMarkdown: 'Server API needed', createdAt: DateTime.now(), provenance: ''
    );
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
    notifyListeners();
  }

  void _addChatMessage(ChatMessage message) {
    chatsByNotebook.putIfAbsent(message.notebookId, () => []).add(message);
    notifyListeners();
  }
  
  void _removeChatMessage(String notebookId, String messageId) {
    chatsByNotebook[notebookId]?.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  NoteItem _saveNote(NoteItem note) {
    notesByNotebook.putIfAbsent(note.notebookId, () => []).insert(0, note);
    notifyListeners();
    return note;
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
    notifyListeners();
  }

  void _updateSourceStatus(String sourceId, String notebookId, SourceStatus status) {
    final list = sourcesByNotebook[notebookId];
    if (list == null) return;
    final index = list.indexWhere((item) => item.id == sourceId);
    if (index == -1) return;
    list[index] = list[index].copyWith(status: status, updatedAt: DateTime.now());
    notifyListeners();
  }

  void _updateJobState(String notebookId, JobState state) {
    final list = jobsByNotebook[notebookId];
    if (list == null || list.isEmpty) return;
    // Assuming LIFO
    final index = 0; 
    list[index] = list[index].copyWith(state: state, progress: 1, finishedAt: DateTime.now());
    notifyListeners();
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();
}
