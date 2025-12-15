import 'dart:convert';

import 'package:http/http.dart' as http;

import 'types.dart';

/// A JSON-RPC 2.0 client for HTTP transport.
///
/// Handles request/response formatting and error parsing for
/// communicating with Ethereum nodes and ERC-4337 bundlers.
class JsonRpcClient {
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

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json.containsKey('error')) {
      final error = json['error'] as Map<String, dynamic>;
      throw BundlerRpcError(
        code: error['code'] as int,
        message: error['message'] as String,
        data: error['data'],
      );
    }

    return json['result'];
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

      if (responseMap.containsKey('error')) {
        final error = responseMap['error'] as Map<String, dynamic>;
        throw BundlerRpcError(
          code: error['code'] as int,
          message: error['message'] as String,
          data: error['data'],
        );
      }

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

/// A single RPC request for batch operations.
class RpcRequest {
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
