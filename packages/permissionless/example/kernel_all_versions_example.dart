// Run Kernel smart-account examples for every supported version.
//
// Covers:
//   v0.2.1, v0.2.2, v0.2.3, v0.2.4  (EntryPoint v0.6)
//   v0.3.0-beta, v0.3.1, v0.3.2, v0.3.3  (EntryPoint v0.7)
//
// USAGE:
//   dart run example/kernel_all_versions_example.dart
//   dart run example/kernel_all_versions_example.dart --self-fund
//   dart run example/kernel_all_versions_example.dart --version=0.3.2
//
// REQUIREMENTS:
//   PIMLICO_API_KEY and optional TEST_PRIVATE_KEY / SEPOLIA_RPC_URL in .env

import 'package:permissionless/permissionless.dart';

import 'kernel_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseKernelArgs(args);

  final versions = parsed.version != null
      ? <KernelVersion>[parsed.version!]
      : KernelVersion.values.toList();

  print('='.padRight(60, '='));
  print('Kernel — all versions runner');
  print('Versions: ${versions.map((v) => v.value).join(', ')}');
  print('Mode: ${parsed.selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('='.padRight(60, '='));

  final results = <KernelRunResult>[];
  for (final version in versions) {
    print('');
    final result = await runKernelVersion(
      version: version,
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
  print('$passed / ${results.length} versions succeeded');
  print('='.padRight(60, '='));

  if (passed != results.length) {
    // Non-zero exit so CI / scripts can detect partial failure
    throw StateError('$passed / ${results.length} Kernel versions succeeded');
  }
}
