// Example: Safe v1.4.1 smart account (EntryPoint v0.7)
//
// USAGE:
//   dart run example/safe_example.dart
//   dart run example/safe_example.dart --self-fund
//
// For every Safe version / EntryPoint matrix cell:
//   dart run example/safe_all_versions_example.dart

import 'safe_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSafeArgs(args);
  final result = await runSafeVariant(
    variant: parseSafeVariant('1.4.1')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
