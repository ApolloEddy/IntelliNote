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

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'emoji': emoji,
    'summary': summary,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
  };

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    id: json['id'],
    title: json['title'],
    emoji: json['emoji'],
    summary: json['summary'] ?? '',
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
    lastOpenedAt: DateTime.parse(json['lastOpenedAt']),
  );

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
    this.fileHash,
    this.progress = 0.0,
    this.stage = '',
    this.stageMessage = '',
  });

  final String id;
  final String notebookId;
  final SourceType type;
  final String name;
  final SourceStatus status;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? fileHash;
  final double progress; // 0.0 - 1.0
  final String stage; // e.g. chunking, embedding, indexing
  final String stageMessage; // user-facing message from server

  Map<String, dynamic> toJson() => {
    'id': id,
    'notebookId': notebookId,
    'type': type.index,
    'name': name,
    'status': status.index,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'fileHash': fileHash,
    'progress': progress,
    'stage': stage,
    'stageMessage': stageMessage,
  };

  factory SourceItem.fromJson(Map<String, dynamic> json) => SourceItem(
    id: json['id'],
    notebookId: json['notebookId'],
    type: SourceType.values[json['type']],
    name: json['name'],
    status: SourceStatus.values[json['status']],
    content: json['content'] ?? '',
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    fileHash: json['fileHash'],
    progress: (json['progress'] ?? 0.0).toDouble(),
    stage: (json['stage'] ?? '').toString(),
    stageMessage: (json['stageMessage'] ?? '').toString(),
  );

  SourceItem copyWith({
    SourceStatus? status,
    DateTime? updatedAt,
    double? progress,
    String? fileHash,
    String? stage,
    String? stageMessage,
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
      fileHash: fileHash ?? this.fileHash,
      progress: progress ?? this.progress,
      stage: stage ?? this.stage,
      stageMessage: stageMessage ?? this.stageMessage,
    );
  }
}

// ChunkItem is server-side managed, no local persistence needed.
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

  Map<String, dynamic> toJson() => {
    'chunkId': chunkId,
    'sourceId': sourceId,
    'snippet': snippet,
    'score': score,
  };

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
    chunkId: json['chunkId'],
    sourceId: json['sourceId'],
    snippet: json['snippet'],
    score: (json['score'] as num).toDouble(),
  );
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'notebookId': notebookId,
    'role': role.index,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'citations': citations.map((c) => c.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'],
    notebookId: json['notebookId'],
    role: ChatRole.values[json['role']],
    content: json['content'],
    createdAt: DateTime.parse(json['createdAt']),
    citations: (json['citations'] as List)
        .map((e) => Citation.fromJson(e))
        .toList(),
  );

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'notebookId': notebookId,
    'type': type.index,
    'title': title,
    'contentMarkdown': contentMarkdown,
    'createdAt': createdAt.toIso8601String(),
    'provenance': provenance,
  };

  factory NoteItem.fromJson(Map<String, dynamic> json) => NoteItem(
    id: json['id'],
    notebookId: json['notebookId'],
    type: NoteType.values[json['type']],
    title: json['title'],
    contentMarkdown: json['contentMarkdown'],
    createdAt: DateTime.parse(json['createdAt']),
    provenance: json['provenance'],
  );
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'notebookId': notebookId,
    'type': type,
    'state': state.index,
    'progress': progress,
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
  };

  factory JobItem.fromJson(Map<String, dynamic> json) => JobItem(
    id: json['id'],
    notebookId: json['notebookId'],
    type: json['type'],
    state: JobState.values[json['state']],
    progress: (json['progress'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt']),
    finishedAt: json['finishedAt'] != null ? DateTime.parse(json['finishedAt']) : null,
  );

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
