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
  
  // Polling logic
  final Set<String> _processingDocIds = {};
  Timer? _statusPollingTimer;

  AppState() {
    _startPolling();
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_processingDocIds.isEmpty) return;
      
      // Copy list to avoid concurrent modification
      final idsToCheck = _processingDocIds.toList();
      
      for (final docId in idsToCheck) {
        try {
          final statusData = await _apiClient.getFileStatus(docId);
          final statusStr = statusData['status'];
          
          // Find which notebook this source belongs to (inefficient, but works for now)
          String? foundNotebookId;
          for (final nid in sourcesByNotebook.keys) {
            if (sourcesByNotebook[nid]?.any((s) => s.id == docId) ?? false) {
              foundNotebookId = nid;
              break;
            }
          }
          
          if (foundNotebookId != null) {
            final newStatus = _parseStatus(statusStr);
            _updateSourceStatus(docId, foundNotebookId, newStatus);
            
            if (newStatus == SourceStatus.ready || newStatus == SourceStatus.failed) {
              _processingDocIds.remove(docId);
              _updateJobState(foundNotebookId, JobState.done);
            }
          }
        } catch (e) {
          print('Polling error for $docId: $e');
        }
      }
    });
  }

  SourceStatus _parseStatus(String s) {
    switch (s.toLowerCase()) {
      case 'ready': return SourceStatus.ready;
      case 'failed': return SourceStatus.failed;
      case 'processing': return SourceStatus.processing;
      default: return SourceStatus.queued;
    }
  }

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
    // 1. Job started
    _addJob(notebookId, 'upload:${filename}');

    try {
      // 2. Compute SHA256
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();

      // 3. Check Server (CAS)
      final checkResult = await _apiClient.checkFile(
        notebookId: notebookId,
        sha256: digest,
        filename: filename
      );

      String docId;
      SourceStatus initialStatus;

      // Even deduplicated files need to be indexed for the specific notebook,
      // so status will likely be 'processing'.
      if (checkResult['doc_id'] != null && checkResult['doc_id'].isNotEmpty) {
        // Hit (or Instant)
        docId = checkResult['doc_id'];
        final statusStr = checkResult['status'] as String;
        
        if (statusStr == 'instant_success' || statusStr == 'ready') {
           initialStatus = SourceStatus.ready;
           _updateJobState(notebookId, JobState.done);
        } else {
           initialStatus = SourceStatus.processing;
           _processingDocIds.add(docId);
        }
      } else {
        // Miss -> Upload
        final uploadResult = await _apiClient.uploadFile(
          notebookId: notebookId,
          file: file
        );
        docId = uploadResult['doc_id'];
        initialStatus = SourceStatus.processing;
        _processingDocIds.add(docId);
      }

      // 4. Create local source record with SERVER ID
      final source = SourceItem(
        id: docId, // Use Server ID
        notebookId: notebookId,
        type: SourceType.file,
        name: filename,
        status: initialStatus,
        content: 'File content managed by server',
        createdAt: DateTime.now(),
      );
      _addSource(source);

    } catch (e) {
      print('Upload failed: $e');
      _updateJobState(notebookId, JobState.failed);
      // Optional: Add a "failed" source item so user sees it
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
    
    // Create empty response message
    final responseId = _id();
    var currentContent = '';
    
    _addChatMessage(ChatMessage(
      id: responseId,
      notebookId: notebookId,
      role: ChatRole.assistant,
      content: '...', // Placeholder
      createdAt: DateTime.now(),
      citations: const [],
    ));

    try {
      // Apply Scope
      List<String>? sourceIds;
      if (scope.type == ScopeType.sources) {
        sourceIds = scope.sourceIds;
      }

      final stream = _apiClient.queryStream(
        notebookId: notebookId, 
        question: question,
        sourceIds: sourceIds,
      );
      
      bool firstTokenReceived = false;

      await for (final data in stream) {
        if (data.containsKey('error')) {
           currentContent += '\n[Error: ${data['error']}]';
           _updateChatMessageContent(notebookId, responseId, currentContent);
           break;
        }

        if (data.containsKey('token')) {
          if (!firstTokenReceived) {
            currentContent = ''; // Clear placeholder
            firstTokenReceived = true;
          }
          currentContent += data['token'];
          _updateChatMessageContent(notebookId, responseId, currentContent);
        }
        
        if (data.containsKey('citations')) {
          final citations = (data['citations'] as List).map((c) {
            return Citation(
              chunkId: c['chunk_id'] ?? 'unknown',
              sourceId: c['source_id'] ?? 'unknown',
              snippet: c['text'],
              score: c['score'] ?? 0.0,
            );
          }).toList();
          _updateChatMessageCitations(notebookId, responseId, citations);
        }
      }
      
    } catch (e) {
      _updateChatMessageContent(notebookId, responseId, 'Network Error: $e');
    }
  }

  void _updateChatMessageContent(String notebookId, String messageId, String newContent) {
    final list = chatsByNotebook[notebookId];
    if (list == null) return;
    final index = list.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      list[index] = list[index].copyWith(content: newContent);
      notifyListeners();
    }
  }

  void _updateChatMessageCitations(String notebookId, String messageId, List<Citation> citations) {
    final list = chatsByNotebook[notebookId];
    if (list == null) return;
    final index = list.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      list[index] = list[index].copyWith(citations: citations);
      notifyListeners();
    }
  }

  // Studio
  Future<NoteItem> generateStudyGuide({required String notebookId}) async {
    return _runStudioGeneration(notebookId, 'study_guide', '学习指南');
  }
  
  Future<NoteItem> generateQuiz({required String notebookId}) async {
    return _runStudioGeneration(notebookId, 'quiz', '自测题');
  }

  Future<NoteItem> _runStudioGeneration(String notebookId, String type, String titlePrefix) async {
    final result = await _apiClient.generateStudio(
      notebookId: notebookId, 
      type: type
    );
    
    final content = result['content'] as String;
    
    final note = NoteItem(
      id: _id(),
      notebookId: notebookId,
      type: type == 'quiz' ? NoteType.quiz : NoteType.studyGuide,
      title: '$titlePrefix ${_dateStr()}',
      contentMarkdown: content,
      createdAt: DateTime.now(),
      provenance: 'studio:$type',
    );
    return _saveNote(note);
  }

  String _dateStr() {
    final now = DateTime.now();
    return '${now.month}/${now.day} ${now.hour}:${now.minute}';
  }

  NoteItem saveChatToNotes({

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
