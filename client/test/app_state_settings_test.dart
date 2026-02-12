import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intelli_note/app/app_state.dart';
import 'package:intelli_note/core/models.dart';
import 'package:intelli_note/core/persistence.dart';

class _MemoryPersistence extends PersistenceService {
  Map<String, dynamic>? _store;

  @override
  Future<Map<String, dynamic>?> loadData() async => _store;

  @override
  Future<void> saveData({
    required List<Notebook> notebooks,
    required Map<String, List<SourceItem>> sources,
    required Map<String, List<ChatMessage>> chats,
    required Map<String, List<NoteItem>> notes,
    required Map<String, List<JobItem>> jobs,
    Map<String, dynamic>? extra,
  }) async {
    _store = {
      'notebooks': notebooks.map((e) => e.toJson()).toList(),
      'sources': sources.values.expand((e) => e).map((e) => e.toJson()).toList(),
      'chats': chats.values.expand((e) => e).map((e) => e.toJson()).toList(),
      'notes': notes.values.expand((e) => e).map((e) => e).map((e) => e.toJson()).toList(),
      'jobs': jobs.values.expand((e) => e).map((e) => e.toJson()).toList(),
      if (extra != null) ...extra,
    };
  }
}

Future<void> _waitForLoad() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('settings defaults are loaded correctly', () async {
    final persistence = _MemoryPersistence();
    final state = AppState(persistence: persistence);
    await _waitForLoad();

    expect(state.themeMode, ThemeMode.system);
    expect(state.themeAccentId, kDefaultThemeAccentId);
    expect(state.userBubbleToneId, kDefaultUserBubbleToneId);
    expect(state.displayName, 'Eddy');
    expect(state.confirmBeforeDeleteNotebook, isTrue);
    expect(state.showNotebookCount, isTrue);

    state.dispose();
  });

  test('settings are persisted and restored', () async {
    final persistence = _MemoryPersistence();
    final state = AppState(persistence: persistence);
    await _waitForLoad();

    state.setThemeMode(ThemeMode.dark);
    state.setThemeAccent('violet');
    state.setUserBubbleTone('accent');
    state.setDisplayName('  Apollo Eddy  ');
    state.setConfirmBeforeDeleteNotebook(false);
    state.setShowNotebookCount(false);
    await _waitForLoad();

    state.dispose();

    final restored = AppState(persistence: persistence);
    await _waitForLoad();

    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.themeAccentId, 'violet');
    expect(restored.userBubbleToneId, 'accent');
    expect(restored.displayName, 'Apollo Eddy');
    expect(restored.confirmBeforeDeleteNotebook, isFalse);
    expect(restored.showNotebookCount, isFalse);

    restored.dispose();
  });

  test('display name falls back on blank and truncates long input', () async {
    final persistence = _MemoryPersistence();
    final state = AppState(persistence: persistence);
    await _waitForLoad();

    state.setDisplayName('   ');
    expect(state.displayName, 'Eddy');

    state.setDisplayName('abcdefghijklmnopqrstuvwxyz123456789');
    expect(state.displayName.length, 24);

    state.dispose();
  });

  test('theme accent falls back on invalid value', () async {
    final persistence = _MemoryPersistence();
    final state = AppState(persistence: persistence);
    await _waitForLoad();

    state.setThemeAccent('not-exists');
    expect(state.themeAccentId, kDefaultThemeAccentId);

    state.dispose();
  });

  test('bubble tone falls back on invalid value', () async {
    final persistence = _MemoryPersistence();
    final state = AppState(persistence: persistence);
    await _waitForLoad();

    state.setUserBubbleTone('invalid');
    expect(state.userBubbleToneId, kDefaultUserBubbleToneId);

    state.dispose();
  });

  test('source focus from citation can be set and cleared', () async {
    final persistence = _MemoryPersistence();
    final state = AppState(persistence: persistence);
    await _waitForLoad();

    const citation = Citation(
      chunkId: 'chunk-1',
      sourceId: 'source-1',
      snippet: 'snippet',
      score: 0.8,
      pageNumber: 3,
    );

    state.focusSourceFromCitation(notebookId: 'nb-1', citation: citation);
    final focused = state.sourceFocusFor('nb-1');
    expect(focused, isNotNull);
    expect(focused?.sourceId, 'source-1');
    expect(focused?.pageNumber, 3);

    state.clearSourceFocus('nb-1');
    expect(state.sourceFocusFor('nb-1'), isNull);

    state.dispose();
  });
}
