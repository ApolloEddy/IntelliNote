import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'models.dart';

class PersistenceService {
  static const String _fileName = 'Intelli Note_data.json';
  static const List<String> _legacyFileNames = [
    'intellinote_data.json',
    'intelli-note_data.json',
    'intelli_note_data.json',
  ];

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<File> _resolveLoadFile() async {
    final preferred = await _localFile;
    if (await preferred.exists()) {
      return preferred;
    }
    final directory = await getApplicationDocumentsDirectory();
    for (final legacyName in _legacyFileNames) {
      final legacyFile = File('${directory.path}/$legacyName');
      if (await legacyFile.exists()) {
        return legacyFile;
      }
    }
    return preferred;
  }

  Future<void> saveData({
    required List<Notebook> notebooks,
    required Map<String, List<SourceItem>> sources,
    required Map<String, List<ChatMessage>> chats,
    required Map<String, List<NoteItem>> notes,
    required Map<String, List<JobItem>> jobs,
    Map<String, dynamic>? extra,
  }) async {
    final file = await _localFile;
    print('[Persistence] Saving to: ${file.path}'); // Debug Path
    
    // Flatten maps to lists for storage
    final allSources = sources.values.expand((x) => x).toList();
    final allChats = chats.values.expand((x) => x).toList();
    final allNotes = notes.values.expand((x) => x).toList();
    final allJobs = jobs.values.expand((x) => x).toList();

    final data = {
      'notebooks': notebooks.map((e) => e.toJson()).toList(),
      'sources': allSources.map((e) => e.toJson()).toList(),
      'chats': allChats.map((e) => e.toJson()).toList(),
      'notes': allNotes.map((e) => e.toJson()).toList(),
      'jobs': allJobs.map((e) => e.toJson()).toList(),
      if (extra != null) ...extra,
    };

    await file.writeAsString(jsonEncode(data));
  }

  Future<Map<String, dynamic>?> loadData() async {
    try {
      final file = await _resolveLoadFile();
      print('[Persistence] Loading from: ${file.path}');
      if (!await file.exists()) {
        print('[Persistence] File not found. Starting fresh.');
        return null;
      }
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      print('Error loading data: $e');
      return null;
    }
  }
}
