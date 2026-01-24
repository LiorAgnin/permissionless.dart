import 'package:test/test.dart';

import 'test_config.dart';

/// Skips the current test if API keys are not configured.
void requireApiKeys() {
  if (!TestConfig.hasApiKeys) {
    markTestSkipped(TestConfig.skipNoApiKey);
  }
}

/// Skips the current test if funded account is not configured.
void requireFundedAccount() {
  if (!TestConfig.hasFundedAccount) {
    markTestSkipped(TestConfig.skipNoFundedAccount);
  }
}

/// Retry wrapper for flaky network tests.
///
/// Retries the action up to [maxAttempts] times with [delay] between attempts.
Future<T> withRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration delay = const Duration(seconds: 2),
}) async {
  var attempts = 0;
  while (true) {
    try {
      return await action();
    } catch (e) {
      attempts++;
      if (attempts >= maxAttempts) rethrow;
      await Future<void>.delayed(delay);
    }
  }
}

/// Common timeout durations for network tests.
class TestTimeouts {
  TestTimeouts._();

  /// Short timeout for simple RPC calls (30 seconds).
  static const Duration shortNetwork = Duration(seconds: 30);

  /// Medium timeout for gas estimation (60 seconds).
  static const Duration mediumNetwork = Duration(seconds: 60);

  /// Long timeout for complex operations (2 minutes).
  static const Duration longNetwork = Duration(seconds: 120);

  /// E2E flow timeout (3 minutes).
  static const Duration e2eFlow = Duration(minutes: 3);
}

/// Custom matcher for BigInt greater than comparison.
Matcher greaterThanBigInt(BigInt value) =>
    predicate<BigInt>((v) => v > value, 'is greater than $value');

/// Custom matcher for BigInt greater than or equal comparison.
Matcher greaterThanOrEqualToBigInt(BigInt value) =>
    predicate<BigInt>((v) => v >= value, 'is greater than or equal to $value');
