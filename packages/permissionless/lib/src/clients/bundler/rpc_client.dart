import 'dart:convert';

import 'package:http/http.dart' as http;

import 'types.dart';

/// A JSON-RPC 2.0 client for HTTP transport.
///
/// Handles request/response formatting and error parsing for
/// communicating with Ethereum nodes and ERC-4337 bundlers.
class JsonRpcClient {
  /// Creates a JSON-RPC client with the given configuration.
  ///
  /// Prefer using [createRpcClient] factory function for URL strings.
  ///
  /// - [url]: The RPC endpoint URI
  /// - [httpClient]: Optional custom HTTP client (useful for testing)
  /// - [headers]: Additional headers to include in requests
  /// - [timeout]: Request timeout duration (default 30 seconds)
  JsonRpcClient({
    required this.url,
    http.Client? httpClient,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client();

  /// The RPC endpoint URL.
  final Uri url;

  /// Additional HTTP headers to include in requests.
  final Map<String, String> headers;

  /// Request timeout duration.
  final Duration timeout;

  final http.Client _httpClient;

  int _requestId = 0;

  /// Sends a JSON-RPC request and returns the result.
  ///
  /// Throws [BundlerRpcError] if the RPC returns an error response.
  Future<dynamic> call(String method, [List<dynamic>? params]) async {
    final requestId = ++_requestId;

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params ?? [],
      'id': requestId,
    });

    final response = await _httpClient
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            ...headers,
          },
          body: body,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw BundlerRpcError(
        code: response.statusCode,
        message: 'HTTP error: ${response.reasonPhrase}',
        data: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw BundlerRpcError(
        code: -32700,
        message: 'Invalid JSON-RPC response: expected object',
        data: response.body,
      );
    }

    _throwIfRpcError(decoded);

    return decoded['result'];
  }

  /// Sends multiple JSON-RPC requests in a batch.
  ///
  /// Returns results in the same order as requests.
  /// Throws if any request in the batch fails.
  Future<List<dynamic>> batch(List<RpcRequest> requests) async {
    if (requests.isEmpty) return [];

    final batchBody = <Map<String, dynamic>>[];
    final startId = _requestId + 1;

    for (final request in requests) {
      _requestId++;
      batchBody.add({
        'jsonrpc': '2.0',
        'method': request.method,
        'params': request.params ?? [],
        'id': _requestId,
      });
    }

    final response = await _httpClient
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            ...headers,
          },
          body: jsonEncode(batchBody),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw BundlerRpcError(
        code: response.statusCode,
        message: 'HTTP error: ${response.reasonPhrase}',
        data: response.body,
      );
    }

    final jsonList = jsonDecode(response.body) as List<dynamic>;
    final results = <int, dynamic>{};

    for (final json in jsonList) {
      final responseMap = json as Map<String, dynamic>;
      final id = responseMap['id'] as int;

      _throwIfRpcError(responseMap);

      results[id] = responseMap['result'];
    }

    // Return results in request order
    return [
      for (var i = startId; i <= _requestId; i++) results[i],
    ];
  }

  /// Closes the underlying HTTP client.
  void close() => _httpClient.close();
}

/// Throws [BundlerRpcError] when a JSON-RPC response contains an `error` field.
///
/// Handles both standard object errors (`{code, message, data}`) and
/// non-standard providers that return a bare string (or other) error value.
void _throwIfRpcError(Map<String, dynamic> json) {
  if (!json.containsKey('error') || json['error'] == null) {
    return;
  }

  final error = json['error'];
  if (error is Map) {
    throw BundlerRpcError(
      code: _parseRpcErrorCode(error['code']),
      message: error['message']?.toString() ?? 'Unknown RPC error',
      data: error['data'],
    );
  }

  // Non-standard: error is a string or other scalar.
  throw BundlerRpcError(
    code: -32000,
    message: error.toString(),
  );
}

/// Parses a JSON-RPC error code that may be int, num, or numeric string.
int _parseRpcErrorCode(dynamic code) {
  if (code is int) return code;
  if (code is num) return code.toInt();
  if (code is String) {
    return int.tryParse(code) ?? -32000;
  }
  return -32000;
}

/// A single RPC request for batch operations.
class RpcRequest {
  /// Creates an RPC request with the given method and optional parameters.
  const RpcRequest(this.method, [this.params]);

  /// The RPC method name.
  final String method;

  /// Optional parameters.
  final List<dynamic>? params;
}

/// Creates a [JsonRpcClient] from a URL string.
JsonRpcClient createRpcClient(
  String url, {
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    JsonRpcClient(
      url: Uri.parse(url),
      headers: headers ?? {},
      timeout: timeout ?? const Duration(seconds: 30),
    );
