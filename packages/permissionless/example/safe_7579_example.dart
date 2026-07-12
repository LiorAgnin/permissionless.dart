// Example: Safe v1.4.1 with ERC-7579 modular support (EntryPoint v0.7)
//
// USAGE:
//   dart run example/safe_7579_example.dart
//   dart run example/safe_7579_example.dart --self-fund
//
// Note: Safe 1.5.0 + ERC-7579 is not supported by permissionless.js / Dart.

import 'safe_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSafeArgs(args);
  final result = await runSafeVariant(
    variant: parseSafeVariant('7579')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
