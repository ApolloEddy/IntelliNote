import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiClient {
  // Use 10.0.2.2 for Android Emulator, localhost for iOS/Desktop
  // Assuming Desktop for this CLI session
  static const String baseUrl = 'http://127.0.0.1:8000/api/v1';

  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> checkFile({
    required String notebookId,
    required String sha256,
    required String filename,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/files/check'),
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
      Uri.parse('$baseUrl/files/upload'),
    );
    
    request.fields['notebook_id'] = notebookId;
    
    // Add file
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        // contentType: MediaType('text', 'plain'), // Optional, auto-detection usually works
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> getFileStatus(String docId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/files/$docId/status'),
    ).timeout(const Duration(seconds: 5)); // 5 seconds timeout
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Stream<Map<String, dynamic>> queryStream({
    required String notebookId,
    required String question,
    List<String>? sourceIds,
    List<Map<String, String>>? history,
  }) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/chat/query'));
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

    final response = await _client.send(request);
    
    if (response.statusCode >= 400) {
      throw HttpException('Stream error: ${response.statusCode}');
    }

    final stream = response.stream.transform(utf8.decoder);
    
    // Simple SSE Parser
    // Buffer for split chunks
    String buffer = '';
    
    await for (final chunk in stream) {
      buffer += chunk;
      
      while (buffer.contains('\n\n')) {
        final splitIndex = buffer.indexOf('\n\n');
        final eventStr = buffer.substring(0, splitIndex);
        buffer = buffer.substring(splitIndex + 2);
        
        if (eventStr.startsWith('data: ')) {
          final dataContent = eventStr.substring(6);
          if (dataContent == '[DONE]') return;
          
          try {
            yield jsonDecode(dataContent) as Map<String, dynamic>;
          } catch (e) {
            print('SSE Parse Error: $e');
          }
        }
      }
    }
  }

  Future<Map<String, dynamic>> generateStudio({
    required String notebookId,
    required String type, // "study_guide" or "quiz"
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/studio/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'notebook_id': notebookId,
        'type': type,
      }),
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<void> deleteFile(String docId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/files/$docId'),
    );
    _checkError(response);
  }

  void _checkError(http.Response response) {
    if (response.statusCode >= 400) {
      throw HttpException(
        'Request failed: ${response.statusCode} - ${response.body}', 
        uri: response.request?.url
      );
    }
  }
}

class HttpException implements Exception {
  final String message;
  final Uri? uri;
  HttpException(this.message, {this.uri});
  
  bool get isNotFound => message.contains('404');
  
  @override
  String toString() => message;
}
