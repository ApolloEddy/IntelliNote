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
  final Map<String, List<ChatMessage>> chatsByNotebook = {};
  final Map<String, List<NoteItem>> notesByNotebook = {};
  final Map<String, List<JobItem>> jobsByNotebook = {};
  final Map<String, Set<String>> _selectedSourceIdsByNotebook = {};
  
  final Set<String> _sessionOpenedNotebooks = {};
  final Set<String> _processingNotebooks = {};
  final Set<String> _processingDocIds = {};
  Timer? _statusPollingTimer;

  AppState({ApiClient? apiClient, PersistenceService? persistence}) 
      : _apiClient = apiClient ?? ApiClient(),
        _persistence = persistence ?? PersistenceService() {
    _load().then((_) {
      if (notebooks.isEmpty) seedDemoData();
      _startPolling();
    });
  }

  bool isProcessing(String notebookId) => _processingNotebooks.contains(notebookId);

  Set<String> selectedSourceIdsFor(String notebookId) {
    if (!_selectedSourceIdsByNotebook.containsKey(notebookId)) {
      _selectedSourceIdsByNotebook[notebookId] = sourcesFor(notebookId)
          .where((s) => s.status == SourceStatus.ready)
          .map((s) => s.id).toSet();
    }
    return _selectedSourceIdsByNotebook[notebookId]!;
  }

  bool isFirstOpenInSession(String notebookId) {
    final isFirst = !_sessionOpenedNotebooks.contains(notebookId);
    if (isFirst) _sessionOpenedNotebooks.add(notebookId);
    return isFirst;
  }

  Future<int> checkNotebookHealth(String notebookId) async {
    final sources = List<SourceItem>.from(sourcesByNotebook[notebookId] ?? []);
    if (sources.isEmpty) return 0;
    
    final List<String> idsToRemove = [];
    final Map<String, String> seenHashes = {}; // hash -> newest_id

    // Check all sources
    for (final source in sources) {
      // 1. Availability Check
      try {
        await _apiClient.getFileStatus(source.id);
        
        // 2. Internal Hash Deduplication
        if (source.fileHash != null) {
          if (seenHashes.containsKey(source.fileHash)) {
            // Found a duplicate hash in same notebook. 
            // We keep the first one we find (newest since list is reversed)
            // and mark this one for removal.
            idsToRemove.add(source.id);
          } else {
            seenHashes[source.fileHash!] = source.id;
          }
        }
      } on HttpException catch (e) {
        if (e.message.contains('404')) idsToRemove.add(source.id);
      } catch (_) {}
    }

    if (idsToRemove.isNotEmpty) {
      for (final docId in idsToRemove) _removeSourceEverywhere(docId);
      notifyListeners();
      _save();
      return idsToRemove.length;
    }
    return 0;
  }

  void toggleSourceSelection(String notebookId, String sourceId, bool selected) {
    final set = selectedSourceIdsFor(notebookId);
    selected ? set.add(sourceId) : set.remove(sourceId);
    notifyListeners();
    _save();
  }

  void setAllSourcesSelection(String notebookId, bool selected) {
    _selectedSourceIdsByNotebook[notebookId] = selected 
      ? sourcesFor(notebookId).where((s) => s.status == SourceStatus.ready).map((s) => s.id).toSet()
      : {};
    notifyListeners();
    _save();
  }

  Future<void> _load() async {
    final data = await _persistence.loadData();
    if (data == null) return;

    if (data['notebooks'] != null) {
      notebooks.clear();
      notebooks.addAll((data['notebooks'] as List).map((e) => Notebook.fromJson(e)));
    }
    
    void loadGrouped<T>(String key, T Function(Map<String, dynamic>) fromJson, Map<String, List<T>> targetMap) {
      if (data[key] != null) {
        targetMap.clear();
        for (final item in (data[key] as List).map((e) => fromJson(e))) {
          String nid = (item as dynamic).notebookId;
          targetMap.putIfAbsent(nid, () => []).add(item);
        }
      }
    }

    loadGrouped('sources', SourceItem.fromJson, sourcesByNotebook);
    loadGrouped('chats', ChatMessage.fromJson, chatsByNotebook);
    loadGrouped('notes', NoteItem.fromJson, notesByNotebook);
    loadGrouped('jobs', JobItem.fromJson, jobsByNotebook);
    
    if (data['selectedSources'] != null) {
      (data['selectedSources'] as Map).forEach((k, v) {
        _selectedSourceIdsByNotebook[k] = (v as List).map((e) => e.toString()).toSet();
      });
    }

    sourcesByNotebook.forEach((nid, list) {
      for (var s in list) {
        if (s.status == SourceStatus.processing || s.status == SourceStatus.queued) {
          _processingDocIds.add(s.id);
        }
      }
    });
    notifyListeners();
  }

  Future<void> _save() async {
    final selectedMap = _selectedSourceIdsByNotebook.map((k, v) => MapEntry(k, v.toList()));
    await _persistence.saveData(
      notebooks: notebooks, sources: sourcesByNotebook, chats: chatsByNotebook,
      notes: notesByNotebook, jobs: jobsByNotebook, extra: {'selectedSources': selectedMap},
    );
  }

  void _startPolling() {
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_processingDocIds.isEmpty) return;
      for (final docId in _processingDocIds.toList()) {
        try {
          final data = await _apiClient.getFileStatus(docId);
          final newStatus = _parseStatus(data['status']);
          
          String? nid;
          for (final key in sourcesByNotebook.keys) {
            if (sourcesByNotebook[key]!.any((s) => s.id == docId)) { nid = key; break; }
          }
          
          if (nid != null) {
            _updateSourceStatus(docId, nid, newStatus);
            if (newStatus == SourceStatus.ready || newStatus == SourceStatus.failed) {
              _processingDocIds.remove(docId);
              final source = sourcesByNotebook[nid]!.firstWhere((s) => s.id == docId);
              _completeJobForFile(nid, source.name, newStatus == SourceStatus.ready ? JobState.done : JobState.failed);
            }
          }
        } catch (_) {}
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
    if (notebooks.isNotEmpty) return;
    createNotebook(title: '我的笔记本', emoji: '📘');
  }

  Notebook createNotebook({required String title, required String emoji}) {
    final notebook = Notebook(id: _id(), title: title, emoji: emoji, summary: '本地会话',
      createdAt: DateTime.now(), updatedAt: DateTime.now(), lastOpenedAt: DateTime.now());
    notebooks.insert(0, notebook);
    notifyListeners();
    _save();
    return notebook;
  }

  void renameNotebook(String id, String title) {
    final i = notebooks.indexWhere((n) => n.id == id);
    if (i == -1) return;
    notebooks[i] = notebooks[i].copyWith(title: title, updatedAt: DateTime.now());
    notifyListeners();
    _save();
  }

  void deleteNotebook(String id) {
    notebooks.removeWhere((n) => n.id == id);
    sourcesByNotebook.remove(id);
    chatsByNotebook.remove(id);
    notesByNotebook.remove(id);
    jobsByNotebook.remove(id);
    notifyListeners();
    _save();
  }

  Future<void> deleteSource(String notebookId, String docId) async {
    try {
      await _apiClient.deleteFile(docId);
      sourcesByNotebook[notebookId]?.removeWhere((s) => s.id == docId);
      _selectedSourceIdsByNotebook[notebookId]?.remove(docId);
      notifyListeners();
      _save();
    } catch (e) {
      print('Failed to delete source: $e');
      rethrow;
    }
  }

  List<SourceItem> sourcesFor(String id) => sourcesByNotebook[id] ?? [];
  List<ChatMessage> chatsFor(String id) => chatsByNotebook[id] ?? [];
  List<NoteItem> notesFor(String id) => notesByNotebook[id] ?? [];
  List<JobItem> jobsFor(String id) => jobsByNotebook[id] ?? [];

  Future<void> addSourceFromText({required String notebookId, required String name, required String text}) async {
    try {
      _processingNotebooks.add(notebookId);
      notifyListeners();
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}${_id()}.txt');
      await file.writeAsString(text, encoding: utf8);
      await _uploadFile(notebookId, file, '$name.txt', SourceType.paste);
    } finally {
      _processingNotebooks.remove(notebookId);
      notifyListeners();
    }
  }

  Future<void> addSourceFromFile({required String notebookId}) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'md']);
    if (res == null || res.files.isEmpty) return;
    final file = File(res.files.first.path!);
    await _uploadFile(notebookId, file, res.files.first.name, SourceType.file);
  }
  
  Future<void> _uploadFile(String nid, File file, String filename, SourceType type) async {
    final jobId = _addJob(nid, 'upload:$filename');
    try {
      final digest = sha256.convert(await file.readAsBytes()).toString();
      final check = await _apiClient.checkFile(notebookId: nid, sha256: digest, filename: filename);

      if (check['status'] == 'already_exists') {
        _removeJob(nid, jobId);
        // ONLY throw DUPLICATE if it's already in the UI list
        if (sourcesFor(nid).any((s) => s.id == check['doc_id'])) {
          throw Exception('DUPLICATE_FILE');
        }
        // Otherwise, the server just cleaned a zombie, we proceed normally (this case should be rare now)
      }

      String docId = check['doc_id'].isEmpty ? (await _apiClient.uploadFile(notebookId: nid, file: file))['doc_id'] : check['doc_id'];
      final initialStatus = _parseStatus(check['status'] == 'upload_required' ? 'processing' : check['status']);
      
      if (initialStatus != SourceStatus.ready) _processingDocIds.add(docId);
      _addSource(SourceItem(
        id: docId, 
        notebookId: nid, 
        type: type, 
        name: filename, 
        status: initialStatus, 
        content: '', 
        createdAt: DateTime.now(),
        fileHash: digest, // Store the hash!
      ));
      if (initialStatus == SourceStatus.ready) _completeJobForFile(nid, filename, JobState.done);

    } catch (e) {
      _updateJobState(nid, JobState.failed, jobId: jobId);
      rethrow;
    }
  }

  Future<void> askQuestion({required String notebookId, required String question, SourceScope scope = const SourceScope.all()}) async {
    if (isProcessing(notebookId)) return;
    _processingNotebooks.add(notebookId);
    notifyListeners();

    final message = ChatMessage(id: _id(), notebookId: notebookId, role: ChatRole.user, content: question, createdAt: DateTime.now(), citations: const []);
    _addChatMessage(message);
    
    final responseId = _id();
    _addChatMessage(ChatMessage(id: responseId, notebookId: notebookId, role: ChatRole.assistant, content: '...', createdAt: DateTime.now(), citations: const []));

    try {
      final all = chatsFor(notebookId);
      final historyMsgs = all.where((m) => m.id != message.id && m.id != responseId).toList();
      final recent = historyMsgs.length > 6 ? historyMsgs.sublist(historyMsgs.length - 6) : historyMsgs;
      final historyData = recent.map((m) => {'role': m.role == ChatRole.user ? 'user' : 'assistant', 'content': m.content}).toList();

      final stream = _apiClient.queryStream(notebookId: notebookId, question: question, sourceIds: scope.type == ScopeType.sources ? scope.sourceIds : [], history: historyData);
      
      var currentContent = '';
      await for (final data in stream) {
        if (data.containsKey('error')) {
          _updateChatMessageContent(notebookId, responseId, '\n[Error: ${data['error']}]');
          break;
        }
        if (data.containsKey('token')) {
          currentContent += data['token'];
          _updateChatMessageContent(notebookId, responseId, currentContent);
        }
        if (data.containsKey('citations')) {
          _updateChatMessageCitations(notebookId, responseId, (data['citations'] as List).map((c) => Citation(chunkId: c['chunk_id'], sourceId: c['source_id'], snippet: c['text'], score: c['score'])).toList());
        }
      }
    } catch (e) {
      _updateChatMessageContent(notebookId, responseId, 'Internal Error: $e');
    } finally {
      _processingNotebooks.remove(notebookId);
      notifyListeners();
      _save(); 
    }
  }

  void _updateChatMessageContent(String nid, String mid, String content) {
    final l = chatsByNotebook[nid];
    if (l == null) return;
    final i = l.indexWhere((m) => m.id == mid);
    if (i != -1) { l[i] = l[i].copyWith(content: content); notifyListeners(); }
  }

  void _updateChatMessageCitations(String nid, String mid, List<Citation> cits) {
    final l = chatsByNotebook[nid];
    if (l == null) return;
    final i = l.indexWhere((m) => m.id == mid);
    if (i != -1) { l[i] = l[i].copyWith(citations: cits); notifyListeners(); }
  }

  Future<NoteItem> generateStudyGuide({required String notebookId}) async => _runStudioGeneration(notebookId, 'study_guide', '学习指南');
  Future<NoteItem> generateQuiz({required String notebookId}) async => _runStudioGeneration(notebookId, 'quiz', '自测题');

  Future<NoteItem> _runStudioGeneration(String nid, String type, String prefix) async {
    if (isProcessing(nid)) throw Exception('Processing');
    _processingNotebooks.add(nid);
    notifyListeners();
    try {
      final res = await _apiClient.generateStudio(notebookId: nid, type: type);
      return _saveNote(NoteItem(id: _id(), notebookId: nid, type: type == 'quiz' ? NoteType.quiz : NoteType.studyGuide, title: '$prefix ${DateTime.now().month}/${DateTime.now().day}', contentMarkdown: res['content'], createdAt: DateTime.now(), provenance: 'studio:$type'));
    } finally {
      _processingNotebooks.remove(nid);
      notifyListeners();
    }
  }

  void _addSource(SourceItem source) {
    final l = sourcesByNotebook.putIfAbsent(source.notebookId, () => []);
    final i = l.indexWhere((s) => s.id == source.id);
    i != -1 ? l[i] = source : l.insert(0, source);
    notifyListeners();
    _save();
  }

  void _addChatMessage(ChatMessage msg) {
    chatsByNotebook.putIfAbsent(msg.notebookId, () => []).add(msg);
    notifyListeners();
    _save();
  }

  NoteItem _saveNote(NoteItem note) {
    notesByNotebook.putIfAbsent(note.notebookId, () => []).insert(0, note);
    notifyListeners();
    _save();
    return note;
  }

  String _addJob(String nid, String type) {
    final id = _id();
    jobsByNotebook.putIfAbsent(nid, () => []).insert(0, JobItem(id: id, notebookId: nid, type: type, state: JobState.queued, progress: 0, createdAt: DateTime.now()));
    notifyListeners();
    _save();
    return id;
  }

  void _updateSourceStatus(String sid, String nid, SourceStatus status) {
    final l = sourcesByNotebook[nid];
    if (l == null) return;
    final i = l.indexWhere((s) => s.id == sid);
    if (i == -1) return;
    l[i] = l[i].copyWith(status: status, updatedAt: DateTime.now());
    notifyListeners();
    _save();
  }

  void _completeJobForFile(String nid, String filename, JobState state) {
    final l = jobsByNotebook[nid];
    if (l == null) return;
    try {
      final job = l.firstWhere((j) => j.type == 'upload:$filename' && j.state != JobState.done && j.state != JobState.failed);
      _updateJobState(nid, state, jobId: job.id);
    } catch (_) {}
  }

  void _updateJobState(String nid, JobState state, {String? jobId}) {
    final l = jobsByNotebook[nid];
    if (l == null || l.isEmpty) return;
    final i = jobId != null ? l.indexWhere((j) => j.id == jobId) : 0;
    if (i != -1) {
      l[i] = l[i].copyWith(state: state, progress: 1, finishedAt: DateTime.now());
      notifyListeners();
      _save();
      if (state == JobState.done) Timer(const Duration(seconds: 3), () => _removeJob(nid, l[i].id));
    }
  }

  void _removeJob(String nid, String jid) {
    final l = jobsByNotebook[nid];
    if (l == null) return;
    final i = l.indexWhere((j) => j.id == jid);
    if (i != -1) { l.removeAt(i); notifyListeners(); _save(); }
  }

  void _removeSourceEverywhere(String sid) {
    sourcesByNotebook.forEach((nid, l) => l.removeWhere((s) => s.id == sid));
    _selectedSourceIdsByNotebook.forEach((nid, s) => s.remove(sid));
  }

  void clearJobs(String nid) {
    jobsByNotebook[nid]?.clear();
    notifyListeners();
    _save();
  }

  static int _c = 0;
  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${++_c}';
}
