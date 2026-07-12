// Example: Simple Account (EntryPoint v0.7)
//
// USAGE:
//   dart run example/simple_example.dart
//   dart run example/simple_example.dart --self-fund
//
// For every EntryPoint version:
//   dart run example/simple_all_versions_example.dart
//
// EIP-7702 Simple:
//   dart run example/eip7702_simple_example.dart

import 'simple_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSimpleArgs(args);
  final result = await runSimpleVariant(
    variant: parseSimpleVariant('0.7')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
