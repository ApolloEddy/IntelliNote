import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/persistence.dart';

class ThemeAccentOption {
  const ThemeAccentOption({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color color;
}

class UserBubbleToneOption {
  const UserBubbleToneOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

const String kDefaultThemeAccentId = 'emerald';
const String kDefaultUserBubbleToneId = 'chatgpt';
const int kChatStreamTimeoutSeconds = 120;
const String kDefaultPdfOcrModelName = 'qwen-vl-max-latest';
const int kDefaultPdfOcrMaxPages = 12;
const int kDefaultPdfOcrTimeoutSeconds = 45;
const int kDefaultPdfTextPageMinChars = 20;
const int kDefaultPdfScanPageMaxChars = 8;
const double kDefaultPdfScanImageRatioThreshold = 0.65;
const String kDefaultPdfVisionModelName = 'qwen-vl-max-latest';
const int kDefaultPdfVisionMaxPages = 12;
const int kDefaultPdfVisionMaxImagesPerPage = 2;
const int kDefaultPdfVisionTimeoutSeconds = 45;
const double kDefaultPdfVisionMinImageRatio = 0.04;
const List<ThemeAccentOption> kThemeAccentOptions = [
  ThemeAccentOption(
    id: 'emerald',
    label: '翡翠绿',
    color: Color(0xFF10A37F),
  ),
  ThemeAccentOption(
    id: 'ocean',
    label: '海洋蓝',
    color: Color(0xFF3B82F6),
  ),
  ThemeAccentOption(
    id: 'violet',
    label: '紫罗兰',
    color: Color(0xFF8B5CF6),
  ),
  ThemeAccentOption(
    id: 'amber',
    label: '琥珀橙',
    color: Color(0xFFF59E0B),
  ),
  ThemeAccentOption(
    id: 'rose',
    label: '玫瑰红',
    color: Color(0xFFF43F5E),
  ),
];
const List<UserBubbleToneOption> kUserBubbleToneOptions = [
  UserBubbleToneOption(
    id: 'chatgpt',
    label: 'ChatGPT 默认',
  ),
  UserBubbleToneOption(
    id: 'accent',
    label: '跟随主题色',
  ),
];

class AppState extends ChangeNotifier {
  final ApiClient _apiClient;
  final PersistenceService _persistence;
  
  final List<Notebook> notebooks = [];
  final Map<String, List<SourceItem>> sourcesByNotebook = {};
  final Map<String, List<ChatMessage>> chatsByNotebook = {};
  final Map<String, List<NoteItem>> notesByNotebook = {};
  final Map<String, List<JobItem>> jobsByNotebook = {};
  final Map<String, Set<String>> _selectedSourceIdsByNotebook = {};
  final Map<String, Citation> _sourceFocusByNotebook = {};
  
  final Set<String> _sessionOpenedNotebooks = {};
  final Set<String> _processingNotebooks = {};
  final Set<String> _processingDocIds = {};
  final Map<String, StreamCancelToken> _chatCancelTokens = {};
  Timer? _statusPollingTimer;
  bool _isPolling = false;
  
  String _notebookQuery = '';
  ThemeMode _themeMode = ThemeMode.system;
  String _themeAccentId = kDefaultThemeAccentId;
  String _userBubbleToneId = kDefaultUserBubbleToneId;
  String _displayName = 'Eddy';
  bool _confirmBeforeDeleteNotebook = true;
  bool _showNotebookCount = true;
  bool _pdfOcrEnabled = false;
  String _pdfOcrModelName = kDefaultPdfOcrModelName;
  int _pdfOcrMaxPages = kDefaultPdfOcrMaxPages;
  int _pdfOcrTimeoutSeconds = kDefaultPdfOcrTimeoutSeconds;
  int _pdfTextPageMinChars = kDefaultPdfTextPageMinChars;
  int _pdfScanPageMaxChars = kDefaultPdfScanPageMaxChars;
  double _pdfScanImageRatioThreshold = kDefaultPdfScanImageRatioThreshold;
  bool _pdfVisionEnabled = false;
  String _pdfVisionModelName = kDefaultPdfVisionModelName;
  int _pdfVisionMaxPages = kDefaultPdfVisionMaxPages;
  int _pdfVisionMaxImagesPerPage = kDefaultPdfVisionMaxImagesPerPage;
  int _pdfVisionTimeoutSeconds = kDefaultPdfVisionTimeoutSeconds;
  double _pdfVisionMinImageRatio = kDefaultPdfVisionMinImageRatio;
  bool _pdfVisionIncludeTextPages = true;
  bool _pdfOcrConfigLoaded = false;
  bool _pdfOcrConfigLoading = false;
  String? _pdfOcrConfigError;

  AppState({ApiClient? apiClient, PersistenceService? persistence}) 
      : _apiClient = apiClient ?? ApiClient(),
        _persistence = persistence ?? PersistenceService() {
    _load().then((_) {
      _startPolling();
    });
  }

  bool isProcessing(String notebookId) {
    if (_processingNotebooks.contains(notebookId)) return true;
    final sources = sourcesByNotebook[notebookId];
    if (sources == null || sources.isEmpty) return false;
    return sources.any((s) => s.status == SourceStatus.processing || s.status == SourceStatus.queued);
  }
  bool isGeneratingResponse(String notebookId) => _chatCancelTokens.containsKey(notebookId);
  ThemeMode get themeMode => _themeMode;
  String get themeAccentId => _themeAccentId;
  String get userBubbleToneId => _userBubbleToneId;
  bool get useAccentUserBubble => _userBubbleToneId == 'accent';
  ThemeAccentOption get themeAccent {
    for (final option in kThemeAccentOptions) {
      if (option.id == _themeAccentId) {
        return option;
      }
    }
    return kThemeAccentOptions.first;
  }
  String get displayName => _displayName;
  bool get confirmBeforeDeleteNotebook => _confirmBeforeDeleteNotebook;
  bool get showNotebookCount => _showNotebookCount;
  bool get pdfOcrEnabled => _pdfOcrEnabled;
  String get pdfOcrModelName => _pdfOcrModelName;
  int get pdfOcrMaxPages => _pdfOcrMaxPages;
  int get pdfOcrTimeoutSeconds => _pdfOcrTimeoutSeconds;
  int get pdfTextPageMinChars => _pdfTextPageMinChars;
  int get pdfScanPageMaxChars => _pdfScanPageMaxChars;
  double get pdfScanImageRatioThreshold => _pdfScanImageRatioThreshold;
  bool get pdfVisionEnabled => _pdfVisionEnabled;
  String get pdfVisionModelName => _pdfVisionModelName;
  int get pdfVisionMaxPages => _pdfVisionMaxPages;
  int get pdfVisionMaxImagesPerPage => _pdfVisionMaxImagesPerPage;
  int get pdfVisionTimeoutSeconds => _pdfVisionTimeoutSeconds;
  double get pdfVisionMinImageRatio => _pdfVisionMinImageRatio;
  bool get pdfVisionIncludeTextPages => _pdfVisionIncludeTextPages;
  bool get pdfOcrConfigLoaded => _pdfOcrConfigLoaded;
  bool get pdfOcrConfigLoading => _pdfOcrConfigLoading;
  String? get pdfOcrConfigError => _pdfOcrConfigError;
  String get notebookQuery => _notebookQuery;
  String get normalizedNotebookQuery => _notebookQuery.trim();
  Citation? sourceFocusFor(String notebookId) => _sourceFocusByNotebook[notebookId];

  List<Notebook> get filteredNotebooks {
    if (_notebookQuery.isEmpty) return notebooks;
    return notebooks.where((n) {
      return n.title.toLowerCase().contains(_notebookQuery.toLowerCase()) ||
             n.summary.toLowerCase().contains(_notebookQuery.toLowerCase());
    }).toList();
  }

  void searchNotebooks(String query) {
    _notebookQuery = query;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _save();
  }

  void setThemeAccent(String accentId) {
    final normalized = _parseThemeAccentId(accentId);
    if (_themeAccentId == normalized) return;
    _themeAccentId = normalized;
    notifyListeners();
    _save();
  }

  void setUserBubbleTone(String toneId) {
    final normalized = _parseUserBubbleToneId(toneId);
    if (_userBubbleToneId == normalized) return;
    _userBubbleToneId = normalized;
    notifyListeners();
    _save();
  }

  void setDisplayName(String value) {
    final normalized = _normalizeDisplayName(value);
    if (_displayName == normalized) return;
    _displayName = normalized;
    notifyListeners();
    _save();
  }

  void setConfirmBeforeDeleteNotebook(bool enabled) {
    if (_confirmBeforeDeleteNotebook == enabled) return;
    _confirmBeforeDeleteNotebook = enabled;
    notifyListeners();
    _save();
  }

  void setShowNotebookCount(bool enabled) {
    if (_showNotebookCount == enabled) return;
    _showNotebookCount = enabled;
    notifyListeners();
    _save();
  }

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

  ThemeMode _parseThemeMode(dynamic raw) {
    switch ((raw ?? '').toString()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeValue(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  String _parseThemeAccentId(dynamic raw) {
    final candidate = (raw ?? '').toString().trim();
    for (final option in kThemeAccentOptions) {
      if (option.id == candidate) {
        return candidate;
      }
    }
    return kDefaultThemeAccentId;
  }

  String _parseUserBubbleToneId(dynamic raw) {
    final candidate = (raw ?? '').toString().trim();
    for (final option in kUserBubbleToneOptions) {
      if (option.id == candidate) {
        return candidate;
      }
    }
    return kDefaultUserBubbleToneId;
  }

  String _normalizeDisplayName(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return 'Eddy';
    if (text.length <= 24) return text;
    return text.substring(0, 24);
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

    final settings = data['settings'];
    if (settings is Map) {
      _themeMode = _parseThemeMode(settings['themeMode']);
      _themeAccentId = _parseThemeAccentId(settings['themeAccentId']);
      _userBubbleToneId = _parseUserBubbleToneId(settings['userBubbleToneId']);
      _displayName = _normalizeDisplayName(settings['displayName']);
      _confirmBeforeDeleteNotebook = settings['confirmBeforeDeleteNotebook'] != false;
      _showNotebookCount = settings['showNotebookCount'] != false;
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

  Future<void> loadPdfOcrConfig({bool force = false}) async {
    if (_pdfOcrConfigLoading) return;
    if (_pdfOcrConfigLoaded && !force) return;
    _pdfOcrConfigLoading = true;
    _pdfOcrConfigError = null;
    notifyListeners();
    try {
      final data = await _apiClient.getPdfOcrConfig();
      _applyPdfOcrConfig(data);
      _pdfOcrConfigLoaded = true;
    } catch (e) {
      _pdfOcrConfigError = e.toString();
    } finally {
      _pdfOcrConfigLoading = false;
      notifyListeners();
    }
  }

  Future<bool> savePdfOcrConfig({
    required bool enabled,
    required String modelName,
    required int maxPages,
    required int timeoutSeconds,
    required int textPageMinChars,
    required int scanPageMaxChars,
    required double scanImageRatioThreshold,
    required bool visionEnabled,
    required String visionModelName,
    required int visionMaxPages,
    required int visionMaxImagesPerPage,
    required int visionTimeoutSeconds,
    required double visionMinImageRatio,
    required bool visionIncludeTextPages,
  }) async {
    if (_pdfOcrConfigLoading) return false;
    _pdfOcrConfigLoading = true;
    _pdfOcrConfigError = null;
    notifyListeners();
    try {
      final payload = <String, dynamic>{
        'enabled': enabled,
        'model_name': modelName.trim(),
        'max_pages': maxPages,
        'timeout_seconds': timeoutSeconds,
        'text_page_min_chars': textPageMinChars,
        'scan_page_max_chars': scanPageMaxChars,
        'scan_image_ratio_threshold': scanImageRatioThreshold,
        'vision_enabled': visionEnabled,
        'vision_model_name': visionModelName.trim(),
        'vision_max_pages': visionMaxPages,
        'vision_max_images_per_page': visionMaxImagesPerPage,
        'vision_timeout_seconds': visionTimeoutSeconds,
        'vision_min_image_ratio': visionMinImageRatio,
        'vision_include_text_pages': visionIncludeTextPages,
      };
      final data = await _apiClient.updatePdfOcrConfig(payload);
      _applyPdfOcrConfig(data);
      _pdfOcrConfigLoaded = true;
      return true;
    } catch (e) {
      _pdfOcrConfigError = e.toString();
      return false;
    } finally {
      _pdfOcrConfigLoading = false;
      notifyListeners();
    }
  }

  void _applyPdfOcrConfig(Map<String, dynamic> data) {
    _pdfOcrEnabled = data['enabled'] == true;
    _pdfOcrModelName = (data['model_name'] ?? '').toString().trim().isEmpty
        ? kDefaultPdfOcrModelName
        : (data['model_name'] ?? '').toString().trim();
    _pdfOcrMaxPages = _toIntInRange(
      data['max_pages'],
      fallback: kDefaultPdfOcrMaxPages,
      min: 1,
      max: 200,
    );
    _pdfOcrTimeoutSeconds = _toIntInRange(
      data['timeout_seconds'],
      fallback: kDefaultPdfOcrTimeoutSeconds,
      min: 10,
      max: 180,
    );
    _pdfTextPageMinChars = _toIntInRange(
      data['text_page_min_chars'],
      fallback: kDefaultPdfTextPageMinChars,
      min: 1,
      max: 2000,
    );
    _pdfScanPageMaxChars = _toIntInRange(
      data['scan_page_max_chars'],
      fallback: kDefaultPdfScanPageMaxChars,
      min: 0,
      max: 200,
    );
    _pdfScanImageRatioThreshold = _toDoubleInRange(
      data['scan_image_ratio_threshold'],
      fallback: kDefaultPdfScanImageRatioThreshold,
      min: 0.0,
      max: 1.0,
    );
    _pdfVisionEnabled = data['vision_enabled'] == true;
    _pdfVisionModelName = (data['vision_model_name'] ?? '').toString().trim().isEmpty
        ? kDefaultPdfVisionModelName
        : (data['vision_model_name'] ?? '').toString().trim();
    _pdfVisionMaxPages = _toIntInRange(
      data['vision_max_pages'],
      fallback: kDefaultPdfVisionMaxPages,
      min: 1,
      max: 200,
    );
    _pdfVisionMaxImagesPerPage = _toIntInRange(
      data['vision_max_images_per_page'],
      fallback: kDefaultPdfVisionMaxImagesPerPage,
      min: 1,
      max: 12,
    );
    _pdfVisionTimeoutSeconds = _toIntInRange(
      data['vision_timeout_seconds'],
      fallback: kDefaultPdfVisionTimeoutSeconds,
      min: 8,
      max: 180,
    );
    _pdfVisionMinImageRatio = _toDoubleInRange(
      data['vision_min_image_ratio'],
      fallback: kDefaultPdfVisionMinImageRatio,
      min: 0.0,
      max: 1.0,
    );
    _pdfVisionIncludeTextPages = data['vision_include_text_pages'] != false;
  }

  int _toIntInRange(
    dynamic raw, {
    required int fallback,
    required int min,
    required int max,
  }) {
    int? parsed;
    if (raw is int) {
      parsed = raw;
    } else if (raw is num) {
      parsed = raw.toInt();
    } else if (raw is String) {
      parsed = int.tryParse(raw);
    }
    if (parsed == null) return fallback;
    if (parsed < min) return min;
    if (parsed > max) return max;
    return parsed;
  }

  double _toDoubleInRange(
    dynamic raw, {
    required double fallback,
    required double min,
    required double max,
  }) {
    double? parsed;
    if (raw is double) {
      parsed = raw;
    } else if (raw is num) {
      parsed = raw.toDouble();
    } else if (raw is String) {
      parsed = double.tryParse(raw);
    }
    if (parsed == null) return fallback;
    if (parsed < min) return min;
    if (parsed > max) return max;
    return parsed;
  }

  Future<void> _save() async {
    final selectedMap = _selectedSourceIdsByNotebook.map((k, v) => MapEntry(k, v.toList()));
    final settings = <String, dynamic>{
      'themeMode': _themeModeValue(_themeMode),
      'themeAccentId': _themeAccentId,
      'userBubbleToneId': _userBubbleToneId,
      'displayName': _displayName,
      'confirmBeforeDeleteNotebook': _confirmBeforeDeleteNotebook,
      'showNotebookCount': _showNotebookCount,
    };
    await _persistence.saveData(
      notebooks: notebooks, sources: sourcesByNotebook, chats: chatsByNotebook,
      notes: notesByNotebook, jobs: jobsByNotebook,
      extra: {'selectedSources': selectedMap, 'settings': settings},
    );
  }

  void _startPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_processingDocIds.isEmpty || _isPolling) return;
      _isPolling = true;
      try {
        for (final docId in _processingDocIds.toList()) {
          try {
            final data = await _apiClient.getFileStatus(docId);
            final newStatus = _parseStatus(data['status']);
            final progress = (data['progress'] ?? 0.0).toDouble();
            final stage = (data['stage'] ?? '').toString();
            final stageMessage = (data['message'] ?? '').toString();
            final parseDetail = data['detail'] is Map
                ? Map<String, dynamic>.from(data['detail'])
                : null;
            
            String? nid;
            for (final key in sourcesByNotebook.keys) {
              if (sourcesByNotebook[key]!.any((s) => s.id == docId)) { nid = key; break; }
            }
            
            if (nid != null) {
              _updateSourceStatus(
                docId,
                nid,
                newStatus,
                progress: progress,
                stage: stage,
                stageMessage: stageMessage,
                parseDetail: parseDetail,
              );
              if (newStatus == SourceStatus.ready || newStatus == SourceStatus.failed) {
                _processingDocIds.remove(docId);
                final source = sourcesByNotebook[nid]!.firstWhere((s) => s.id == docId);
                _completeJobForFile(nid, source.name, newStatus == SourceStatus.ready ? JobState.done : JobState.failed);

                // 智能图标逻辑：如果是 Ready 且 Notebook 图标还是默认的
                if (newStatus == SourceStatus.ready) {
                  final notebookIndex = notebooks.indexWhere((n) => n.id == nid);
                  if (notebookIndex != -1) {
                    final notebook = notebooks[notebookIndex];
                    // 如果是默认图标 📁 (general) 或者 ⏳ (pending)，则尝试分类
                    if (notebook.emoji == '📁' || notebook.emoji == '⏳') {
                      try {
                        final classifyRes = await _apiClient.classifyFile(docId);
                        if (classifyRes.containsKey('emoji')) {
                          updateNotebookEmoji(nid, classifyRes['emoji']);
                        }
                      } catch (_) {
                        // 失败则静默
                      }
                    }
                  }
                }
              }
            }
          } catch (e) {
            // 如果是 404，说明文件被删除了，停止轮询
            if (e.toString().contains('404')) {
              _processingDocIds.remove(docId);
            }
          }
        }
      } finally {
        _isPolling = false;
      }
    });
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    for (final token in _chatCancelTokens.values) {
      token.cancel();
    }
    _chatCancelTokens.clear();
    super.dispose();
  }

  SourceStatus _parseStatus(String s) {
    switch (s.toLowerCase()) {
      case 'ready': return SourceStatus.ready;
      case 'already_exists': return SourceStatus.ready;
      case 'failed': return SourceStatus.failed;
      case 'processing': return SourceStatus.processing;
      default: return SourceStatus.queued;
    }
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

  void updateNotebookEmoji(String id, String emoji) {
    final i = notebooks.indexWhere((n) => n.id == id);
    if (i == -1) return;
    notebooks[i] = notebooks[i].copyWith(emoji: emoji, updatedAt: DateTime.now());
    notifyListeners();
    _save();
  }

  void deleteNotebook(String id) {
    notebooks.removeWhere((n) => n.id == id);
    sourcesByNotebook.remove(id);
    chatsByNotebook.remove(id);
    notesByNotebook.remove(id);
    jobsByNotebook.remove(id);
    _sourceFocusByNotebook.remove(id);
    _chatCancelTokens[id]?.cancel();
    _chatCancelTokens.remove(id);
    notifyListeners();
    _save();
  }

  void stopGeneratingResponse(String notebookId) {
    final token = _chatCancelTokens[notebookId];
    if (token == null) return;
    token.cancel();
    notifyListeners();
  }

  Future<void> deleteSource(String notebookId, String docId) async {
    try {
      await _apiClient.deleteFile(docId);
      sourcesByNotebook[notebookId]?.removeWhere((s) => s.id == docId);
      _selectedSourceIdsByNotebook[notebookId]?.remove(docId);
      final focused = _sourceFocusByNotebook[notebookId];
      if (focused != null && focused.sourceId == docId) {
        _sourceFocusByNotebook.remove(notebookId);
      }
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

  void focusSourceFromCitation({
    required String notebookId,
    required Citation citation,
  }) {
    _sourceFocusByNotebook[notebookId] = citation;
    notifyListeners();
  }

  void clearSourceFocus(String notebookId) {
    if (_sourceFocusByNotebook.remove(notebookId) != null) {
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> getPdfPagePreview({
    required String sourceId,
    required int pageNumber,
    int maxChars = 4000,
  }) async {
    return _apiClient.getPdfPagePreview(
      docId: sourceId,
      pageNumber: pageNumber,
      maxChars: maxChars,
    );
  }

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
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'md', 'pdf']);
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
        stage: initialStatus == SourceStatus.ready ? 'done' : 'queued',
        stageMessage: initialStatus == SourceStatus.ready ? '处理完成' : '等待处理',
        parseDetail: null,
      ));
      if (initialStatus == SourceStatus.ready) _completeJobForFile(nid, filename, JobState.done);

    } catch (e) {
      _updateJobState(nid, JobState.failed, jobId: jobId);
      rethrow;
    }
  }

  Future<void> askQuestion({required String notebookId, required String question, SourceScope scope = const SourceScope.all()}) async {
    if (isProcessing(notebookId)) return;
    final cancelToken = StreamCancelToken();
    _chatCancelTokens[notebookId] = cancelToken;
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

      final stream = _apiClient
          .queryStream(
            notebookId: notebookId,
            question: question,
            sourceIds: scope.type == ScopeType.sources ? scope.sourceIds : [],
            history: historyData,
            cancelToken: cancelToken,
          )
          .timeout(
            const Duration(seconds: kChatStreamTimeoutSeconds),
            onTimeout: (sink) {
              sink.add({'error': '请求超时（${kChatStreamTimeoutSeconds}s），请重试'});
              sink.close();
            },
          );
      
      var currentContent = '';
      var hasToken = false;
      String? streamError;
      await for (final data in stream) {
        if (cancelToken.isCancelled) break;
        if (data.containsKey('token')) {
          final token = data['token']?.toString() ?? '';
          if (token.isNotEmpty) {
            hasToken = true;
            currentContent += token;
            _updateChatMessageContent(notebookId, responseId, currentContent);
          }
        }
        if (data.containsKey('error')) {
          streamError = data['error']?.toString() ?? 'Unknown stream error';
        }
        if (data.containsKey('citations')) {
          _updateChatMessageCitations(notebookId, responseId, _parseCitations(data['citations']));
        }
      }
      if (!hasToken) {
        if (cancelToken.isCancelled) {
          _updateChatMessageContent(notebookId, responseId, '[已停止生成]');
        } else if (streamError != null) {
          _updateChatMessageContent(notebookId, responseId, '\n[Error: $streamError]');
        } else {
          _updateChatMessageContent(notebookId, responseId, 'Empty Response');
        }
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        _updateChatMessageContent(notebookId, responseId, '[已停止生成]');
      } else {
        _updateChatMessageContent(notebookId, responseId, 'Internal Error: $e');
      }
    } finally {
      _chatCancelTokens.remove(notebookId);
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

  List<Citation> _parseCitations(dynamic raw) {
    if (raw is! List) return const [];
    final List<Citation> result = [];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final chunkId = map['chunk_id']?.toString() ?? '';
      final sourceId = map['source_id']?.toString() ?? '';
      final snippet = map['text']?.toString() ?? '';
      final scoreRaw = map['score'];
      final double score = scoreRaw is num ? scoreRaw.toDouble() : 0.0;
      final pageRaw = map['page_number'];
      int? pageNumber;
      if (pageRaw is int) {
        pageNumber = pageRaw;
      } else if (pageRaw is num) {
        pageNumber = pageRaw.toInt();
      } else if (pageRaw is String) {
        pageNumber = int.tryParse(pageRaw);
      }
      if (chunkId.isEmpty || sourceId.isEmpty || snippet.isEmpty) continue;
      result.add(Citation(
        chunkId: chunkId,
        sourceId: sourceId,
        snippet: snippet,
        score: score,
        pageNumber: pageNumber,
      ));
    }
    return result;
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

  void _updateSourceStatus(
    String sid,
    String nid,
    SourceStatus status, {
    double? progress,
    String? stage,
    String? stageMessage,
    Map<String, dynamic>? parseDetail,
  }) {
    final l = sourcesByNotebook[nid];
    if (l == null) return;
    final i = l.indexWhere((s) => s.id == sid);
    if (i == -1) return;
    l[i] = l[i].copyWith(
      status: status,
      updatedAt: DateTime.now(),
      progress: progress,
      stage: stage,
      stageMessage: stageMessage,
      parseDetail: parseDetail,
    );
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
