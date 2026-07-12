// Run Thirdweb smart-account examples for every supported EntryPoint version.
//
// Covers:
//   Thirdweb + EntryPoint v0.6
//   Thirdweb + EntryPoint v0.7
//
// USAGE:
//   dart run example/thirdweb_all_versions_example.dart
//   dart run example/thirdweb_all_versions_example.dart --self-fund
//   dart run example/thirdweb_all_versions_example.dart --version=0.6
//   dart run example/thirdweb_all_versions_example.dart --version=0.7
//
// REQUIREMENTS:
//   PIMLICO_API_KEY and optional TEST_PRIVATE_KEY / SEPOLIA_RPC_URL in .env

import 'thirdweb_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseThirdwebArgs(args);

  final variants = parsed.variant != null
      ? <ThirdwebVariant>[parsed.variant!]
      : allThirdwebVariants;

  print('='.padRight(60, '='));
  print('Thirdweb — all versions runner');
  print('Variants: ${variants.map((v) => v.label).join(' | ')}');
  print('Mode: ${parsed.selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('='.padRight(60, '='));

  final results = <ThirdwebRunResult>[];
  for (final variant in variants) {
    print('');
    final result = await runThirdwebVariant(
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
      '$passed / ${results.length} Thirdweb variants succeeded',
    );
  }
}
