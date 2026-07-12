// Run Light Account examples for every supported version.
//
// Covers:
//   Light v1.1.0 + EntryPoint v0.6
//   Light v2.0.0 + EntryPoint v0.7
//
// USAGE:
//   dart run example/light_all_versions_example.dart
//   dart run example/light_all_versions_example.dart --self-fund
//   dart run example/light_all_versions_example.dart --version=1.1.0
//   dart run example/light_all_versions_example.dart --version=2.0.0
//
// REQUIREMENTS:
//   PIMLICO_API_KEY and optional TEST_PRIVATE_KEY / SEPOLIA_RPC_URL in .env

import 'light_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseLightArgs(args);

  final variants = parsed.variant != null
      ? <LightVariant>[parsed.variant!]
      : allLightVariants;

  print('='.padRight(60, '='));
  print('Light Account — all versions runner');
  print('Variants: ${variants.map((v) => v.label).join(' | ')}');
  print('Mode: ${parsed.selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('='.padRight(60, '='));

  final results = <LightRunResult>[];
  for (final variant in variants) {
    print('');
    final result = await runLightVariant(
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
    throw StateError('$passed / ${results.length} Light variants succeeded');
  }
}
