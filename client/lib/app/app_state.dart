import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/persistence.dart';

class AppState extends ChangeNotifier {
  final ApiClient _apiClient;
  final PersistenceService _persistence;
  
  final List<Notebook> notebooks = [];
  final Map<String, List<SourceItem>> sourcesByNotebook = {};
  // Chunks are now handled by server, no need to track locally
  final Map<String, List<ChatMessage>> chatsByNotebook = {};
  final Map<String, List<NoteItem>> notesByNotebook = {};
  final Map<String, List<JobItem>> jobsByNotebook = {};
  
  // Processing status tracking (for UI interlocking)
  final Set<String> _processingNotebooks = {};

  bool isProcessing(String notebookId) => _processingNotebooks.contains(notebookId);
  
  // Polling logic
  final Set<String> _processingDocIds = {};
  Timer? _statusPollingTimer;

  AppState({ApiClient? apiClient, PersistenceService? persistence}) 
      : _apiClient = apiClient ?? ApiClient(),
        _persistence = persistence ?? PersistenceService() {
    _load().then((_) {
      if (notebooks.isEmpty) {
        seedDemoData();
      }
      _startPolling();
    });
  }

  Future<void> _load() async {
    final data = await _persistence.loadData();
    if (data == null) {
      print('[_load] No data found.');
      return;
    }

    print('[_load] Data loaded. Notebooks count in JSON: ${(data['notebooks'] as List?)?.length}');

    if (data['notebooks'] != null) {
      notebooks.clear();
      notebooks.addAll(
        (data['notebooks'] as List).map((e) => Notebook.fromJson(e))
      );
    }
    
    // Helper to group lists by notebookId
    void loadGrouped<T>(String key, T Function(Map<String, dynamic>) fromJson, Map<String, List<T>> targetMap) {
      if (data[key] != null) {
        targetMap.clear();
        final list = (data[key] as List).map((e) => fromJson(e)).toList();
        for (final item in list) {
          // Dynamic access to notebookId would be cleaner, but we know the types
          String nid = '';
          if (item is SourceItem) nid = item.notebookId;
          else if (item is ChatMessage) nid = item.notebookId;
          else if (item is NoteItem) nid = item.notebookId;
          else if (item is JobItem) nid = item.notebookId;
          
          targetMap.putIfAbsent(nid, () => []).add(item);
        }
      }
    }

    loadGrouped('sources', SourceItem.fromJson, sourcesByNotebook);
    loadGrouped('chats', ChatMessage.fromJson, chatsByNotebook);
    loadGrouped('notes', NoteItem.fromJson, notesByNotebook);
    loadGrouped('jobs', JobItem.fromJson, jobsByNotebook);
    
    notifyListeners();
  }

  Future<void> _save() async {
    await _persistence.saveData(
      notebooks: notebooks,
      sources: sourcesByNotebook,
      chats: chatsByNotebook,
      notes: notesByNotebook,
      jobs: jobsByNotebook,
    );
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
              // Use helper to find relevant job by filename convention if possible
              // We need the filename from source
              final source = sourcesByNotebook[foundNotebookId]?.firstWhere((s) => s.id == docId);
              if (source != null) {
                 _completeJobForFile(foundNotebookId, source.name, newStatus == SourceStatus.ready ? JobState.done : JobState.failed);
              } else {
                 // Fallback if source not found (shouldn't happen)
                 _updateJobState(foundNotebookId, JobState.done);
              }
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
    _save();
    return notebook;
  }

  void renameNotebook(String notebookId, String title) {
    final index = notebooks.indexWhere((item) => item.id == notebookId);
    if (index == -1) {
      return;
    }
    notebooks[index] = notebooks[index].copyWith(title: title, updatedAt: DateTime.now());
    notifyListeners();
    _save();
  }

  void deleteNotebook(String notebookId) {
    notebooks.removeWhere((item) => item.id == notebookId);
    sourcesByNotebook.remove(notebookId);
    chatsByNotebook.remove(notebookId);
    notesByNotebook.remove(notebookId);
    jobsByNotebook.remove(notebookId);
    notifyListeners();
    _save();
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
    try {
      // 简单实现：将文本写入临时文件然后上传
      final tempDir = Directory.systemTemp;
      final separator = Platform.pathSeparator;
      // Sanitize filename to prevent invalid characters
      final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_'); 
      final filePath = '${tempDir.path}$separator${safeName}_${_id()}.txt';
      
      final file = File(filePath);
      await file.writeAsString(text);
      
      await _uploadFile(notebookId, file, '$safeName.txt');
    } catch (e) {
      print('Paste text failed: $e');
      // Ensure we verify failure in UI if it happened before uploadFile
    }
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
    final jobId = _addJob(notebookId, 'upload:${filename}');

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
           _updateJobState(notebookId, JobState.done, jobId: jobId);
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
      _updateJobState(notebookId, JobState.failed, jobId: jobId);
      notifyListeners(); // Force UI update on failure
      // Optional: Add a "failed" source item so user sees it
    }
  }

  Future<void> askQuestion({
    required String notebookId,
    required String question,
    SourceScope scope = const SourceScope.all(),
  }) async {
    if (isProcessing(notebookId)) return;
    _processingNotebooks.add(notebookId);
    notifyListeners();

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
    } finally {
      _processingNotebooks.remove(notebookId);
      notifyListeners();
      _save(); // Persist final chat state
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
    if (isProcessing(notebookId)) {
       throw Exception('Another operation is in progress for this notebook.');
    }
    _processingNotebooks.add(notebookId);
    notifyListeners();

    try {
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
    } finally {
      _processingNotebooks.remove(notebookId);
      notifyListeners();
    }
  }

  String _dateStr() {
    final now = DateTime.now();
    return '${now.month}/${now.day} ${now.hour}:${now.minute}';
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
    _save();
  }

  void _addChatMessage(ChatMessage message) {
    chatsByNotebook.putIfAbsent(message.notebookId, () => []).add(message);
    notifyListeners();
    _save();
  }
  
  void _removeChatMessage(String notebookId, String messageId) {
    chatsByNotebook[notebookId]?.removeWhere((m) => m.id == messageId);
    notifyListeners();
    _save();
  }

  NoteItem _saveNote(NoteItem note) {
    notesByNotebook.putIfAbsent(note.notebookId, () => []).insert(0, note);
    notifyListeners();
    _save();
    return note;
  }

  String _addJob(String notebookId, String type) {
    final jobId = _id();
    jobsByNotebook.putIfAbsent(notebookId, () => []).insert(
          0,
          JobItem(
            id: jobId,
            notebookId: notebookId,
            type: type,
            state: JobState.queued,
            progress: 0,
            createdAt: DateTime.now(),
          ),
        );
    notifyListeners();
    _save();
    return jobId;
  }

  void _updateSourceStatus(String sourceId, String notebookId, SourceStatus status) {
    final list = sourcesByNotebook[notebookId];
    if (list == null) return;
    final index = list.indexWhere((item) => item.id == sourceId);
    if (index == -1) return;
    list[index] = list[index].copyWith(status: status, updatedAt: DateTime.now());
    notifyListeners();
    _save();
  }

  void _completeJobForFile(String notebookId, String filename, JobState state) {
    // Attempt to find a job matching "upload:filename" that is not done/failed yet
    final list = jobsByNotebook[notebookId];
    if (list == null) return;
    
    // We search for the *newest* job that matches, assuming the polling relates to recent action
    try {
      final job = list.firstWhere((j) => 
        j.type == 'upload:$filename' && 
        j.state != JobState.done && 
        j.state != JobState.failed
      );
      _updateJobState(notebookId, state, jobId: job.id);
    } catch (e) {
      // No matching active job found.
      // This is possible if app restarted and job list was loaded from disk but polling restarted
      // Or if job was already marked done.
    }
  }

  void _updateJobState(String notebookId, JobState state, {String? jobId}) {
    final list = jobsByNotebook[notebookId];
    if (list == null || list.isEmpty) return;
    
    int index = -1;
    if (jobId != null) {
      index = list.indexWhere((j) => j.id == jobId);
    } else {
      // Legacy behavior: assume top (0)
      index = 0;
    }

    if (index != -1) {
      list[index] = list[index].copyWith(state: state, progress: 1, finishedAt: DateTime.now());
      notifyListeners();
      _save();
    }
  }

  void clearJobs(String notebookId) {
    jobsByNotebook[notebookId]?.clear();
    notifyListeners();
    _save();
  }

  static int _uuidCounter = 0;

  String _id() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _uuidCounter++;
    return '${now}_$_uuidCounter';
  }
}
