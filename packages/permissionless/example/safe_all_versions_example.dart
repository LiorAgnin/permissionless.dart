// Run Safe smart-account examples for every supported version matrix cell.
//
// Covers:
//   Safe 1.4.1 + EntryPoint v0.6
//   Safe 1.4.1 + EntryPoint v0.7
//   Safe 1.5.0 + EntryPoint v0.7
//   Safe 1.4.1 + EntryPoint v0.7 + ERC-7579
//
// USAGE:
//   dart run example/safe_all_versions_example.dart
//   dart run example/safe_all_versions_example.dart --self-fund
//   dart run example/safe_all_versions_example.dart --version=1.5.0
//   dart run example/safe_all_versions_example.dart --version=1.4.1-ep0.6
//   dart run example/safe_all_versions_example.dart --version=7579
//
// REQUIREMENTS:
//   PIMLICO_API_KEY and optional TEST_PRIVATE_KEY / SEPOLIA_RPC_URL in .env

import 'safe_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseSafeArgs(args);

  final variants =
      parsed.variant != null ? <SafeVariant>[parsed.variant!] : allSafeVariants;

  print('='.padRight(60, '='));
  print('Safe — all versions runner');
  print('Variants: ${variants.map((v) => v.label).join(' | ')}');
  print('Mode: ${parsed.selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('='.padRight(60, '='));

  final results = <SafeRunResult>[];
  for (final variant in variants) {
    print('');
    final result = await runSafeVariant(
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
    throw StateError('$passed / ${results.length} Safe variants succeeded');
  }
}
