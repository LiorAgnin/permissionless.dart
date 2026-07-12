// Example: Simple Account with EntryPoint v0.6
//
// USAGE:
//   dart run example/simple_ep06_example.dart
//   dart run example/simple_ep06_example.dart --self-fund

import 'simple_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSimpleArgs(args);
  final result = await runSimpleVariant(
    variant: parseSimpleVariant('0.6')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
