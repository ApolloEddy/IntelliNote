import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

@immutable
class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.emoji,
    required this.summary,
    required this.createdAt,
    required this.updatedAt,
    required this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String emoji;
  final String summary;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastOpenedAt;

  Notebook copyWith({
    String? title,
    String? emoji,
    String? summary,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
  }) {
    return Notebook(
      id: id,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      summary: summary ?? this.summary,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }
}

enum SourceType { file, paste, url }

enum SourceStatus { queued, processing, ready, failed }

@immutable
class SourceItem {
  const SourceItem({
    required this.id,
    required this.notebookId,
    required this.type,
    required this.name,
    required this.status,
    required this.content,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String notebookId;
  final SourceType type;
  final String name;
  final SourceStatus status;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;

  SourceItem copyWith({
    SourceStatus? status,
    DateTime? updatedAt,
  }) {
    return SourceItem(
      id: id,
      notebookId: notebookId,
      type: type,
      name: name,
      status: status ?? this.status,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@immutable
class ChunkItem {
  const ChunkItem({
    required this.id,
    required this.notebookId,
    required this.sourceId,
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.embedding,
  });

  final String id;
  final String notebookId;
  final String sourceId;
  final String text;
  final int startOffset;
  final int endOffset;
  final List<double> embedding;
}

enum ChatRole { user, assistant }

@immutable
class Citation {
  const Citation({
    required this.chunkId,
    required this.sourceId,
    required this.snippet,
    required this.score,
  });

  final String chunkId;
  final String sourceId;
  final String snippet;
  final double score;
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.notebookId,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.citations,
  });

  final String id;
  final String notebookId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final List<Citation> citations;

  ChatMessage copyWith({
    String? notebookId,
    String? content,
    List<Citation>? citations,
  }) {
    return ChatMessage(
      id: id,
      notebookId: notebookId ?? this.notebookId,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      citations: citations ?? this.citations,
    );
  }
}

enum NoteType { written, savedResponse, studyGuide, quiz }

@immutable
class NoteItem {
  const NoteItem({
    required this.id,
    required this.notebookId,
    required this.type,
    required this.title,
    required this.contentMarkdown,
    required this.createdAt,
    required this.provenance,
  });

  final String id;
  final String notebookId;
  final NoteType type;
  final String title;
  final String contentMarkdown;
  final DateTime createdAt;
  final String provenance;
}

enum JobState { queued, running, done, failed, canceled }

@immutable
class JobItem {
  const JobItem({
    required this.id,
    required this.notebookId,
    required this.type,
    required this.state,
    required this.progress,
    required this.createdAt,
    this.finishedAt,
  });

  final String id;
  final String notebookId;
  final String type;
  final JobState state;
  final double progress;
  final DateTime createdAt;
  final DateTime? finishedAt;

  JobItem copyWith({
    JobState? state,
    double? progress,
    DateTime? finishedAt,
  }) {
    return JobItem(
      id: id,
      notebookId: notebookId,
      type: type,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      createdAt: createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

enum ScopeType { all, sources }

@immutable
class SourceScope {
  const SourceScope._(this.type, this.sourceIds);

  const SourceScope.all() : this._(ScopeType.all, const []);

  const SourceScope.sources(List<String> sourceIds)
      : this._(ScopeType.sources, sourceIds);

  final ScopeType type;
  final List<String> sourceIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceScope &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          const IterableEquality().equals(sourceIds, other.sourceIds);

  @override
  int get hashCode => type.hashCode ^ const IterableEquality().hash(sourceIds);
}
