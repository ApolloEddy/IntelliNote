import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiClient {
  // Use 10.0.2.2 for Android Emulator, localhost for iOS/Desktop
  // Assuming Desktop for this CLI session
  static const String baseUrl = 'http://localhost:8000/api/v1';

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

  Future<Map<String, dynamic>> query({
    required String notebookId,
    required String question,
  }) async {
    // Note: This endpoint needs to be implemented in Server! 
    // Currently Server has /files but not /chat properly exposed in V1 yet.
    // Assuming endpoint structure based on design.
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/query'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'notebook_id': notebookId,
        'question': question,
      }),
    );
    _checkError(response);
    return jsonDecode(utf8.decode(response.bodyBytes));
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
