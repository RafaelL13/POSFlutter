import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pos_app/core/config/app_environment.dart';
import 'package:pos_app/core/storage/secure_token_store.dart';

abstract interface class JsonApiClient {
  Future<Map<String, Object?>> get(String path, {Map<String, String>? query});
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
  });
}

enum CloudFailure {
  unauthorized,
  forbidden,
  validation,
  conflict,
  notFound,
  rateLimited,
  server,
  timeout,
  network,
  unexpected,
}

CloudFailure classifyCloudStatus(int statusCode) => switch (statusCode) {
  401 => CloudFailure.unauthorized,
  403 => CloudFailure.forbidden,
  400 || 422 => CloudFailure.validation,
  409 => CloudFailure.conflict,
  404 => CloudFailure.notFound,
  429 => CloudFailure.rateLimited,
  >= 500 => CloudFailure.server,
  _ => CloudFailure.unexpected,
};

final class CloudApiException implements Exception {
  const CloudApiException(
    this.failure,
    this.message, {
    this.statusCode,
    this.errorCode,
  });
  final CloudFailure failure;
  final String message;
  final int? statusCode;
  final String? errorCode;

  factory CloudApiException.fromStatus(
    int statusCode, [
    String? serverMessage,
    String? errorCode,
  ]) {
    final failure = classifyCloudStatus(statusCode);
    final fallback = switch (failure) {
      CloudFailure.unauthorized => 'Tu sesión venció o no es válida.',
      CloudFailure.forbidden =>
        'No tienes permiso para consultar este recurso.',
      CloudFailure.validation => 'La solicitud remota no es válida.',
      CloudFailure.conflict => 'Existe un conflicto con el estado remoto.',
      CloudFailure.notFound => 'El recurso solicitado no existe.',
      CloudFailure.rateLimited =>
        'Hay demasiadas solicitudes. Intenta nuevamente en un momento.',
      CloudFailure.server => 'El servidor no pudo completar la consulta.',
      _ => 'La nube respondió $statusCode.',
    };
    return CloudApiException(
      failure,
      serverMessage?.trim().isNotEmpty == true
          ? serverMessage!.trim()
          : fallback,
      statusCode: statusCode,
      errorCode: errorCode,
    );
  }

  @override
  String toString() => message;
}

final class CloudApiClient implements JsonApiClient {
  CloudApiClient({
    http.Client? client,
    SecureTokenStore? tokens,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _tokens = tokens ?? const SecureTokenStore();

  final http.Client _client;
  final SecureTokenStore _tokens;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppEnvironment.apiBaseUrl}$path')
          .replace(queryParameters: query);

  @override
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
  }) => _request(() async {
    final response = await _post(path, body, authenticated: authenticated);
    if (authenticated && response.statusCode == 401 && await _refresh()) {
      return _decode(await _post(path, body, authenticated: true));
    }
    return _decode(response);
  });

  @override
  Future<Map<String, Object?>> get(String path, {Map<String, String>? query}) =>
      _request(() async {
        final response = await _get(path, query);
        if (response.statusCode == 401 && await _refresh()) {
          return _decode(await _get(path, query));
        }
        return _decode(response);
      });

  Future<http.Response> _post(
    String path,
    Map<String, Object?> body, {
    required bool authenticated,
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (authenticated) {
      final token = await _tokens.accessToken();
      if (token != null) headers['authorization'] = 'Bearer $token';
    }
    return _client
        .post(_uri(path), headers: headers, body: jsonEncode(body))
        .timeout(timeout);
  }

  Future<http.Response> _get(String path, Map<String, String>? query) async {
    final headers = <String, String>{};
    final token = await _tokens.accessToken();
    if (token != null) headers['authorization'] = 'Bearer $token';
    return _client.get(_uri(path, query), headers: headers).timeout(timeout);
  }

  Future<bool> _refresh() async {
    final refreshToken = await _tokens.refreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _client
          .post(
            _uri('/api/auth/refresh'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _tokens.clear();
        return false;
      }
      final json = _jsonMap(response.body);
      final access = json['accessToken']?.toString();
      final refresh = json['refreshToken']?.toString();
      if (access == null || refresh == null) return false;
      await _tokens.save(accessToken: access, refreshToken: refresh);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<Map<String, Object?>> _request(
    Future<Map<String, Object?>> Function() action,
  ) async {
    try {
      return await action();
    } on CloudApiException {
      rethrow;
    } on TimeoutException {
      throw const CloudApiException(
        CloudFailure.timeout,
        'La consulta remota agotó el tiempo de espera.',
      );
    } on SocketException {
      throw const CloudApiException(
        CloudFailure.network,
        'Sin conexión con el servidor.',
      );
    } on http.ClientException {
      throw const CloudApiException(
        CloudFailure.network,
        'No fue posible conectar con el servidor.',
      );
    } on FormatException {
      throw const CloudApiException(
        CloudFailure.unexpected,
        'El servidor devolvió una respuesta inválida.',
      );
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      String? errorCode;
      try {
        final error = _jsonMap(response.body);
        message = error['message']?.toString();
        errorCode = error['errorCode']?.toString();
      } on FormatException {
        message = null;
      }
      throw CloudApiException.fromStatus(
        response.statusCode,
        message,
        errorCode,
      );
    }
    return _jsonMap(response.body);
  }

  Map<String, Object?> _jsonMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : {'items': decoded};
  }
}
