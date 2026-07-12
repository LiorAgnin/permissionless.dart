// Example: Simple Account with EntryPoint v0.7
//
// Same as simple_example.dart — explicit name for discoverability.
//
// USAGE:
//   dart run example/simple_ep07_example.dart
//   dart run example/simple_ep07_example.dart --self-fund

import 'simple_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSimpleArgs(args);
  final result = await runSimpleVariant(
    variant: parseSimpleVariant('0.7')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
