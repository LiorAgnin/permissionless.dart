// Example: Safe v1.4.1 smart account with EntryPoint v0.6
//
// USAGE:
//   dart run example/safe_v141_ep06_example.dart
//   dart run example/safe_v141_ep06_example.dart --self-fund

import 'safe_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSafeArgs(args);
  final result = await runSafeVariant(
    variant: parseSafeVariant('1.4.1-ep0.6')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
