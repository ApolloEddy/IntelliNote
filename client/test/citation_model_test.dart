import 'package:flutter_test/flutter_test.dart';
import 'package:intelli_note/core/models.dart';

void main() {
  test('Citation.fromJson supports snake_case page_number', () {
    final citation = Citation.fromJson({
      'chunkId': 'chunk-1',
      'sourceId': 'source-1',
      'snippet': 'snippet',
      'score': 0.9,
      'page_number': 5,
    });

    expect(citation.pageNumber, 5);
  });

  test('Citation.toJson persists pageNumber', () {
    const citation = Citation(
      chunkId: 'chunk-2',
      sourceId: 'source-2',
      snippet: 'content',
      score: 0.7,
      pageNumber: 2,
    );

    final json = citation.toJson();
    expect(json['pageNumber'], 2);
  });
}

