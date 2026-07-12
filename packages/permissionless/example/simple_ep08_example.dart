// Example: Simple Account with EntryPoint v0.8 (factory-deployed)
//
// Uses EIP-712 PackedUserOperation typed-data signing (not EIP-7702).
// For EIP-7702 Simple (EOA code delegation) see eip7702_simple_example.dart.
//
// USAGE:
//   dart run example/simple_ep08_example.dart
//   dart run example/simple_ep08_example.dart --self-fund

import 'simple_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSimpleArgs(args);
  final result = await runSimpleVariant(
    variant: parseSimpleVariant('0.8')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
