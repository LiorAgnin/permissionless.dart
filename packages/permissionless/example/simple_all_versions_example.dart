// Run Simple Account examples for every supported EntryPoint version.
//
// Covers (factory-deployed eth-infinitism SimpleAccount):
//   Simple + EntryPoint v0.6
//   Simple + EntryPoint v0.7
//   Simple + EntryPoint v0.8
//
// EIP-7702 Simple (code delegation) is separate:
//   dart run example/eip7702_simple_example.dart
//
// USAGE:
//   dart run example/simple_all_versions_example.dart
//   dart run example/simple_all_versions_example.dart --self-fund
//   dart run example/simple_all_versions_example.dart --version=0.6
//   dart run example/simple_all_versions_example.dart --version=0.8
//
// REQUIREMENTS:
//   PIMLICO_API_KEY and optional TEST_PRIVATE_KEY / SEPOLIA_RPC_URL in .env

import 'simple_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSimpleArgs(args);

  final variants = parsed.variant != null
      ? <SimpleVariant>[parsed.variant!]
      : allSimpleVariants;

  print('='.padRight(60, '='));
  print('Simple Account — all versions runner');
  print('Variants: ${variants.map((v) => v.label).join(' | ')}');
  print('Mode: ${parsed.selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('Note: EIP-7702 Simple is covered by eip7702_simple_example.dart');
  print('='.padRight(60, '='));

  final results = <SimpleRunResult>[];
  for (final variant in variants) {
    print('');
    final result = await runSimpleVariant(
      variant: variant,
      selfFunded: parsed.selfFunded,
    );
    results.add(result);
  }

  print('\n${'='.padRight(60, '=')}');
  print('SUMMARY');
  print('='.padRight(60, '='));
  var passed = 0;
  for (final r in results) {
    print(r);
    if (r.ok) passed++;
  }
  print('');
  print('$passed / ${results.length} variants succeeded');
  print('='.padRight(60, '='));

  if (passed != results.length) {
    throw StateError(
      '$passed / ${results.length} Simple variants succeeded',
    );
  }
}
