import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Retry wrapper for flaky network tests.
///
/// Retries the action up to [maxAttempts] times with [delay] between attempts.
/// When [retryIf] is given, an error it rejects is rethrown at once.
Future<T> withRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration delay = const Duration(seconds: 2),
  bool Function(Object error)? retryIf,
}) async {
  var attempts = 0;
  while (true) {
    try {
      return await action();
    } catch (e) {
      attempts++;
      if (attempts >= maxAttempts) rethrow;
      if (retryIf != null && !retryIf(e)) rethrow;
      await Future<void>.delayed(delay);
    }
  }
}

/// Whether [error] is the bundler's AA25 (invalid account nonce), which a
/// still-pending UserOp from an earlier run causes.
bool isAa25(Object error) =>
    error is BundlerRpcError && error.aaErrorCode == 'AA25';

/// Common timeout durations for network tests.
class TestTimeouts {
  TestTimeouts._();

  /// Short timeout for simple RPC calls (30 seconds).
  static const Duration shortNetwork = Duration(seconds: 30);

  /// Medium timeout for gas estimation (60 seconds).
  static const Duration mediumNetwork = Duration(seconds: 60);

  /// Long timeout for complex operations (2 minutes).
  static const Duration longNetwork = Duration(seconds: 120);

  /// E2E wait-for-receipt timeout (3 minutes).
  static const Duration e2eFlow = Duration(minutes: 3);

  /// Full E2E test timeout: receipt wait + AA25 submit retries + network slack.
  static const Duration e2eTest = Duration(minutes: 6);
}

/// Custom matcher for BigInt greater than comparison.
Matcher greaterThanBigInt(BigInt value) =>
    predicate<BigInt>((v) => v > value, 'is greater than $value');

/// Custom matcher for BigInt greater than or equal comparison.
Matcher greaterThanOrEqualToBigInt(BigInt value) =>
    predicate<BigInt>((v) => v >= value, 'is greater than or equal to $value');
