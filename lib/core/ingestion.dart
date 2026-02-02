import 'dart:math';

import 'models.dart';

class IngestionResult {
  const IngestionResult({required this.chunks, required this.summary});

  final List<ChunkItem> chunks;
  final String summary;
}

class IngestionPipeline {
  final _chunker = Chunker();
  final _embedder = EmbeddingProvider();

  Future<IngestionResult> ingest({
    required String notebookId,
    required String sourceId,
    required String content,
  }) async {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    final chunks = _chunker.chunkText(
      notebookId: notebookId,
      sourceId: sourceId,
      text: normalized,
    );
    final embeddings = _embedder.embedBatch(chunks.map((item) => item.text).toList());
    final enriched = <ChunkItem>[];
    for (var i = 0; i < chunks.length; i++) {
      enriched.add(chunks[i].copyWithEmbedding(embeddings[i]));
    }
    final summary = _summarize(enriched);
    return IngestionResult(chunks: enriched, summary: summary);
  }

  Future<ChatMessage> answerQuestion({
    required String question,
    required List<ChunkItem> chunks,
    required List<SourceItem> sources,
  }) async {
    if (chunks.isEmpty) {
      return ChatMessage(
        id: _id(),
        notebookId: '',
        role: ChatRole.assistant,
        content: '当前没有可用来源，请先导入资料。',
        createdAt: DateTime.now(),
        citations: const [],
      );
    }
    final queryVector = _embedder.embed(question);
    final hits = VectorSearch.search(queryVector, chunks, topK: 3);
    if (hits.isEmpty) {
      return ChatMessage(
        id: _id(),
        notebookId: '',
        role: ChatRole.assistant,
        content: '在当前范围内未找到相关资料。',
        createdAt: DateTime.now(),
        citations: const [],
      );
    }
    final buffer = StringBuffer('根据资料，');
    for (var i = 0; i < hits.length; i++) {
      buffer.write(hits[i].chunk.text.trim());
      buffer.write('【${i + 1}】');
      if (i != hits.length - 1) {
        buffer.write('\n');
      }
    }
    return ChatMessage(
      id: _id(),
      notebookId: '',
      role: ChatRole.assistant,
      content: buffer.toString(),
      createdAt: DateTime.now(),
      citations: hits
          .map(
            (hit) => Citation(
              chunkId: hit.chunk.id,
              sourceId: hit.chunk.sourceId,
              snippet: hit.chunk.text,
              score: hit.score,
            ),
          )
          .toList(),
    );
  }

  Future<NoteItem> generateStudyGuide({
    required String notebookId,
    required List<ChunkItem> chunks,
  }) async {
    final topChunks = _pickChunks(chunks, 4);
    final content = StringBuffer('# 学习指南\n\n');
    for (var i = 0; i < topChunks.length; i++) {
      content.writeln('## 重点 ${i + 1}');
      content.writeln(topChunks[i].text.trim());
      content.writeln();
    }
    return NoteItem(
      id: _id(),
      notebookId: notebookId,
      type: NoteType.studyGuide,
      title: '学习指南',
      contentMarkdown: content.toString(),
      createdAt: DateTime.now(),
      provenance: 'studio:study_guide',
    );
  }

  Future<NoteItem> generateQuiz({
    required String notebookId,
    required List<ChunkItem> chunks,
  }) async {
    final topChunks = _pickChunks(chunks, 3);
    final content = StringBuffer('# 测验\n\n');
    for (var i = 0; i < topChunks.length; i++) {
      content.writeln('### 问题 ${i + 1}');
      content.writeln('请解释：${topChunks[i].text.trim()}');
      content.writeln('**答案要点：** ${_firstSentence(topChunks[i].text)}');
      content.writeln();
    }
    return NoteItem(
      id: _id(),
      notebookId: notebookId,
      type: NoteType.quiz,
      title: '测验题',
      contentMarkdown: content.toString(),
      createdAt: DateTime.now(),
      provenance: 'studio:quiz',
    );
  }

  String _summarize(List<ChunkItem> chunks) {
    if (chunks.isEmpty) {
      return '尚未生成摘要';
    }
    final first = chunks.first.text.split('\n').first;
    return first.length > 80 ? '${first.substring(0, 80)}...' : first;
  }

  List<ChunkItem> _pickChunks(List<ChunkItem> chunks, int count) {
    if (chunks.length <= count) {
      return chunks;
    }
    return chunks.sublist(0, count);
  }

  String _firstSentence(String text) {
    final index = text.indexOf('。');
    if (index != -1) {
      return text.substring(0, index + 1);
    }
    return text.split('\n').first;
  }
}

class Chunker {
  List<ChunkItem> chunkText({
    required String notebookId,
    required String sourceId,
    required String text,
    int targetTokens = 500,
    int overlapTokens = 80,
  }) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      return [];
    }
    final chunks = <ChunkItem>[];
    var start = 0;
    while (start < words.length) {
      final end = min(start + targetTokens, words.length);
      final chunkWords = words.sublist(start, end);
      final chunkText = chunkWords.join(' ');
      final offsetStart = text.indexOf(chunkWords.first, max(0, start));
      final offsetEnd = offsetStart + chunkText.length;
      chunks.add(
        ChunkItem(
          id: _id(),
          notebookId: notebookId,
          sourceId: sourceId,
          text: chunkText,
          startOffset: offsetStart,
          endOffset: offsetEnd,
          embedding: const [],
        ),
      );
      if (end == words.length) {
        break;
      }
      start = max(0, end - overlapTokens);
    }
    return chunks;
  }
}

class EmbeddingProvider {
  List<List<double>> embedBatch(List<String> texts) {
    return texts.map(embed).toList();
  }

  List<double> embed(String text, {int dim = 64}) {
    final vector = List<double>.filled(dim, 0);
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) {
        continue;
      }
      final index = word.hashCode.abs() % dim;
      vector[index] += 1;
    }
    return _normalize(vector);
  }

  List<double> _normalize(List<double> vector) {
    final norm = sqrt(vector.fold(0, (sum, item) => sum + item * item));
    if (norm == 0) {
      return vector;
    }
    return vector.map((value) => value / norm).toList();
  }
}

class SearchHit {
  const SearchHit(this.chunk, this.score);

  final ChunkItem chunk;
  final double score;
}

class VectorSearch {
  static List<SearchHit> search(List<double> queryVector, List<ChunkItem> chunks, {int topK = 3}) {
    final hits = <SearchHit>[];
    for (final chunk in chunks) {
      if (chunk.embedding.isEmpty) {
        continue;
      }
      final score = _dot(queryVector, chunk.embedding);
      hits.add(SearchHit(chunk, score));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(topK).where((hit) => hit.score > 0).toList();
  }

  static double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }
}

extension ChunkEmbedding on ChunkItem {
  ChunkItem copyWithEmbedding(List<double> embedding) {
    return ChunkItem(
      id: id,
      notebookId: notebookId,
      sourceId: sourceId,
      text: text,
      startOffset: startOffset,
      endOffset: endOffset,
      embedding: embedding,
    );
  }
}

String _id() => DateTime.now().microsecondsSinceEpoch.toString();
