import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Network failures, timeouts, 5xx, 408 and 429 are worth retrying; other
  /// 4xx mean the request itself is wrong and will never succeed.
  bool get retryable {
    final code = statusCode;
    if (code == null) return true;
    return code >= 500 || code == 408 || code == 429;
  }

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// Thin JSON-over-HTTP client for the RideGuard backend.
class ApiClient {
  ApiClient({
    required String Function() baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUrl = baseUrl,
       _client = client ?? http.Client();

  final String Function() _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Uri _uri(String path) {
    final base = _baseUrl().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<Map<String, dynamic>?> send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, _uri(path))
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException('Request timed out');
    } on http.ClientException catch (e) {
      // Includes socket errors (server down, no signal).
      throw ApiException('Server unreachable: ${e.message}');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    }
    throw ApiException(_errorDetail(response), statusCode: response.statusCode);
  }

  Future<bool> isHealthy() async {
    try {
      final body = await send('GET', '/health');
      return body?['status'] == 'ok';
    } on ApiException {
      return false;
    }
  }

  static String _errorDetail(http.Response r) {
    try {
      final decoded = jsonDecode(r.body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } on FormatException {
      // Not JSON; fall through.
    }
    return r.reasonPhrase ?? 'Request failed';
  }
}
