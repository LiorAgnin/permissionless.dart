/// Error returned by bundler RPC calls.
///
/// ERC-4337 defines specific error codes (AA* codes) for different
/// validation and execution failures.
class BundlerRpcError implements Exception {
  /// Creates a bundler RPC error with the given details.
  ///
  /// - [code]: The JSON-RPC error code (e.g., -32000 for execution errors)
  /// - [message]: Human-readable error description
  /// - [data]: Optional additional data, often contains AA* error codes
  ///
  /// Use [aaErrorCode] to extract ERC-4337 specific error codes like
  /// "AA21" (insufficient funds) or "AA25" (invalid nonce).
  const BundlerRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  /// JSON-RPC error code.
  final int code;

  /// Error message.
  final String message;

  /// Additional error data (often contains AA* error code).
  final dynamic data;

  /// Case-insensitive AA## matcher (matches viem `getBundlerError` lowercasing).
  static final RegExp _aaCodePattern = RegExp(r'AA\d+', caseSensitive: false);

  /// Known ERC-4337 AA code short descriptions (EntryPoint / bundler).
  static const Map<String, String> aaErrorDescriptions = {
    'AA10': 'Sender already constructed',
    'AA13': 'InitCode failed or OOG',
    'AA14': 'InitCode must return sender',
    'AA15': 'InitCode must create sender',
    'AA20': 'Account not deployed',
    'AA21': "Didn't pay prefund",
    'AA22': 'Expired or not due',
    'AA23': 'Reverted (or OOG)',
    'AA24': 'Signature error',
    'AA25': 'Invalid account nonce',
    'AA30': 'Paymaster not deployed',
    'AA31': 'Paymaster deposit too low',
    'AA32': 'Paymaster expired or not due',
    'AA33': 'Paymaster reverted (or OOG)',
    'AA34': 'Paymaster signature error',
    'AA40': 'Over verificationGasLimit',
    'AA41': 'Over paymasterVerificationGasLimit',
    'AA50': 'PostOp reverted',
    'AA51': 'Paymaster postOp reverted',
    'AA90': 'Invalid aggregator',
    'AA91': 'Failed to send to beneficiary',
    'AA92': 'Gas values overflow',
    'AA93': 'Internal call only',
    'AA94': 'Gas value overflow',
    'AA95': 'Out of gas',
    'AA96': 'Invalid aggregator',
  };

  /// Returns the AA error code if present (e.g., `"AA21"`, `"AA25"`).
  ///
  /// Scans both [message] and [data] (case-insensitive), matching viem's
  /// `getBundlerError` which lowercases the error details before matching.
  /// Codes are always returned uppercased.
  String? get aaErrorCode {
    for (final source in [message, if (data != null) data.toString()]) {
      final match = _aaCodePattern.firstMatch(source);
      if (match != null) {
        return match.group(0)!.toUpperCase();
      }
    }
    return null;
  }

  /// Human-readable description for [aaErrorCode], if known.
  String? get aaErrorDescription {
    final code = aaErrorCode;
    if (code == null) return null;
    return aaErrorDescriptions[code];
  }

  @override
  String toString() {
    final aa = aaErrorCode;
    final desc = aaErrorDescription;
    final aaPart = aa == null
        ? ''
        : desc == null
            ? ' [$aa]'
            : ' [$aa: $desc]';
    return 'BundlerRpcError($code)$aaPart: $message'
        '${data != null ? ' - $data' : ''}';
  }
}

/// A non-200 HTTP response from the RPC endpoint.
///
/// Subclasses [BundlerRpcError] so existing `on BundlerRpcError` handlers
/// keep catching it. [code] is the HTTP status, not a JSON-RPC error code:
/// the request never produced a JSON-RPC answer, so callers that classify
/// JSON-RPC errors (e.g. `sendUserOperationSync`) treat it as "no answer".
class BundlerHttpError extends BundlerRpcError {
  /// Creates an HTTP error for [statusCode] with the response [body].
  const BundlerHttpError({
    required int statusCode,
    String? reasonPhrase,
    String? body,
  }) : super(
          code: statusCode,
          message: 'HTTP error: $reasonPhrase',
          data: body,
        );

  /// The HTTP status code (same as [code]).
  int get statusCode => code;
}
