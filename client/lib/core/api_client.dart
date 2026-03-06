import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({String? baseUrl}) : _baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl());

  String _baseUrl;

  String get baseUrl => _baseUrl;
  bool get isConfigured => _baseUrl.isNotEmpty;

  static String _defaultBaseUrl() {
    const defined = String.fromEnvironment('INTELLINOTE_API_BASE_URL', defaultValue: '');
    if (defined.trim().isNotEmpty) return defined;
    if (!kIsWeb && Platform.isAndroid) {
      // Android 端默认不再依赖本地 Server，必须显式配置云端网关。
      return '';
    }
    return 'http://127.0.0.1:8000/api/v1';
  }

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  void updateBaseUrl(String value) {
    _baseUrl = _normalizeBaseUrl(value);
  }

  Uri _uri(String path) {
    if (_baseUrl.isEmpty) {
      throw ApiConfigException('API_BASE_URL 未配置：Android 端请在设置中填写云端网关地址');
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> checkFile({
    required String notebookId,
    required String sha256,
    required String filename,
  }) async {
    final response = await _client.post(
      _uri('/files/check'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'notebook_id': notebookId,
        'sha256': sha256,
        'filename': filename,
      }),
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> uploadFile({
    required String notebookId,
    required File file,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/files/upload'),
    );

    request.fields['notebook_id'] = notebookId;

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> getFileStatus(String docId) async {
    final response = await _client.get(
      _uri('/files/$docId/status'),
    ).timeout(const Duration(seconds: 5));
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Stream<Map<String, dynamic>> queryStream({
    required String notebookId,
    required String question,
    List<String>? sourceIds,
    List<Map<String, String>>? history,
    StreamCancelToken? cancelToken,
  }) async* {
    final request = http.Request('POST', _uri('/chat/query'));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';

    final Map<String, dynamic> body = {
      'notebook_id': notebookId,
      'question': question,
    };
    if (sourceIds != null) {
      body['source_ids'] = sourceIds;
    }
    if (history != null && history.isNotEmpty) {
      body['history'] = history;
    }
    request.body = jsonEncode(body);

    final streamClient = http.Client();
    cancelToken?.bind(streamClient.close);

    try {
      if (cancelToken?.isCancelled ?? false) return;
      final response = await streamClient.send(request);
      if (cancelToken?.isCancelled ?? false) return;

      if (response.statusCode >= 400) {
        throw HttpException('Stream error: ${response.statusCode}');
      }

      final stream = response.stream.transform(utf8.decoder);

      String buffer = '';

      await for (final chunk in stream) {
        if (cancelToken?.isCancelled ?? false) return;
        buffer += chunk;

        while (true) {
          final delimiter = _findSseEventDelimiter(buffer);
          if (delimiter == null) break;
          final eventStr = buffer.substring(0, delimiter.index);
          buffer = buffer.substring(delimiter.index + delimiter.length);
          final normalizedEvent = eventStr.trimRight();

          if (normalizedEvent.startsWith('data: ')) {
            final dataContent = normalizedEvent.substring(6);
            if (dataContent == '[DONE]') return;

            try {
              yield jsonDecode(dataContent) as Map<String, dynamic>;
            } catch (e) {
              print('SSE Parse Error: $e');
            }
          }
        }
      }
    } on http.ClientException catch (e) {
      if (cancelToken?.isCancelled ?? false) return;
      throw HttpException('Stream client error: ${e.message}');
    } finally {
      streamClient.close();
    }
  }

  _SseDelimiter? _findSseEventDelimiter(String buffer) {
    final lfIndex = buffer.indexOf('\n\n');
    final crlfIndex = buffer.indexOf('\r\n\r\n');
    if (lfIndex == -1 && crlfIndex == -1) return null;
    if (lfIndex == -1) return _SseDelimiter(index: crlfIndex, length: 4);
    if (crlfIndex == -1) return _SseDelimiter(index: lfIndex, length: 2);
    if (lfIndex < crlfIndex) {
      return _SseDelimiter(index: lfIndex, length: 2);
    }
    return _SseDelimiter(index: crlfIndex, length: 4);
  }

  Future<Map<String, dynamic>> generateStudio({
    required String notebookId,
    required String type,
  }) async {
    final response = await _client.post(
      _uri('/studio/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'notebook_id': notebookId,
        'type': type,
      }),
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> classifyFile(String docId) async {
    final response = await _client.post(
      _uri('/files/$docId/classify'),
      headers: {'Content-Type': 'application/json'},
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<void> deleteFile(String docId) async {
    final response = await _client.delete(
      _uri('/files/$docId'),
    );
    _checkError(response);
  }

  Future<Map<String, dynamic>> getPdfPagePreview({
    required String docId,
    required int pageNumber,
    int maxChars = 4000,
  }) async {
    final response = await _client.get(
      _uri('/files/$docId/page/$pageNumber?max_chars=$maxChars'),
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> getPdfOcrConfig() async {
    final response = await _client.get(
      _uri('/system/pdf-ocr-config'),
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> updatePdfOcrConfig(Map<String, dynamic> payload) async {
    final response = await _client.put(
      _uri('/system/pdf-ocr-config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  void _checkError(http.Response response) {
    if (response.statusCode >= 400) {
      throw HttpException(
        'Request failed: ${response.statusCode} - ${response.body}',
        uri: response.request?.url,
      );
    }
  }
}

class _SseDelimiter {
  const _SseDelimiter({required this.index, required this.length});
  final int index;
  final int length;
}

class StreamCancelToken {
  bool _isCancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _isCancelled;

  void bind(void Function() onCancel) {
    if (_isCancelled) {
      onCancel();
      return;
    }
    _onCancel = onCancel;
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _onCancel?.call();
  }
}

class ApiConfigException implements Exception {
  ApiConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HttpException implements Exception {
  final String message;
  final Uri? uri;
  HttpException(this.message, {this.uri});

  bool get isNotFound => message.contains('404');

  @override
  String toString() => message;
}
