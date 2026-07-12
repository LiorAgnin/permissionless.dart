// Example: Thirdweb smart account with EntryPoint v0.6
//
// USAGE:
//   dart run example/thirdweb_ep06_example.dart
//   dart run example/thirdweb_ep06_example.dart --self-fund

import 'thirdweb_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseThirdwebArgs(args);
  final result = await runThirdwebVariant(
    variant: parseThirdwebVariant('0.6')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
