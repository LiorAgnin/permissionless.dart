// Example: Thirdweb smart account with EntryPoint v0.7
//
// Same as thirdweb_example.dart — explicit name for discoverability.
//
// USAGE:
//   dart run example/thirdweb_ep07_example.dart
//   dart run example/thirdweb_ep07_example.dart --self-fund

import 'thirdweb_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseThirdwebArgs(args);
  final result = await runThirdwebVariant(
    variant: parseThirdwebVariant('0.7')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
