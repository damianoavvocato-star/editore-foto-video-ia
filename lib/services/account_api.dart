import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AccountApiException implements Exception {
  const AccountApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => 'Account API HTTP $statusCode: $message';
}

/// Same-origin HTTPS account client. Session tokens are supplied from secure
/// storage and never placed in URLs, query strings, or logs.
class RemoteAccountApi {
  RemoteAccountApi({
    required Uri baseUri,
    HttpClient? client,
    this.bearerToken,
  })  : baseUri = _validateBaseUri(baseUri),
        _client = client ?? HttpClient();

  final Uri baseUri;
  final HttpClient _client;
  final String? bearerToken;

  static Uri _validateBaseUri(Uri uri) {
    if (!uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(uri, 'baseUri', 'Indirizzo API non valido.');
    }
    final localHttp = uri.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2', '::1'}.contains(uri.host);
    if (uri.scheme == 'http' && !localHttp) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'Per server remoti è obbligatorio HTTPS.',
      );
    }
    return uri.replace(path: '');
  }

  Uri _resolve(String path) {
    final uri = baseUri.resolve(path);
    if (uri.scheme != baseUri.scheme ||
        uri.host.toLowerCase() != baseUri.host.toLowerCase() ||
        uri.port != baseUri.port ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError.value(path, 'path', 'La richiesta deve restare sullo stesso host.');
    }
    return uri;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path);
    final request = await _client.openUrl(method, uri).timeout(
          const Duration(seconds: 20),
        );
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    final token = bearerToken;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    headers?.forEach((name, value) => request.headers.set(name, value));
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('Risposta account API troppo grande.');
      }
      bytes.addAll(chunk);
    }
    final text = utf8.decode(bytes);
    Object? decoded;
    if (text.isNotEmpty) decoded = jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      final code = detail is Map ? detail['code']?.toString() : null;
      final message = detail is Map
          ? detail['message']?.toString() ?? 'Richiesta non autorizzata.'
          : detail?.toString() ?? 'Richiesta non riuscita.';
      throw AccountApiException(response.statusCode, message, code: code);
    }
    if (decoded == null) return <String, dynamic>{};
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Risposta account API non valida.');
    }
    return decoded;
  }

  void close() => _client.close(force: true);
}

/// Bearer sessions are stored in platform-backed encrypted secure storage.
class AccountSessionStore {
  const AccountSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  static const String _tokenKey = 'editore_account_session_v1';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) async {
    if (token.isEmpty || token.length > 512) {
      throw ArgumentError.value(token, 'token', 'Sessione non valida.');
    }
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clear() => _storage.delete(key: _tokenKey);
}
