// Example: Safe v1.5.0 smart account (EntryPoint v0.7)
//
// USAGE:
//   dart run example/safe_v150_example.dart
//   dart run example/safe_v150_example.dart --self-fund
//
// Note: Safe 1.5.0 + ERC-7579 is not supported.

import 'safe_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSafeArgs(args);
  final result = await runSafeVariant(
    variant: parseSafeVariant('1.5.0')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
