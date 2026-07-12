// Example: Kernel v0.3.1 smart account (EntryPoint v0.7, ERC-7579)
//
// USAGE:
//   dart run example/kernel_example.dart
//   dart run example/kernel_example.dart --self-fund
//
// For every Kernel version at once:
//   dart run example/kernel_all_versions_example.dart

import 'package:permissionless/permissionless.dart';

import 'kernel_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseKernelArgs(args);
  final result = await runKernelVersion(
    version: KernelVersion.v0_3_1,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
