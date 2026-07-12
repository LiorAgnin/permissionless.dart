// Example: Kernel v0.2.1 smart account (EntryPoint v0.6)
//
// USAGE:
//   dart run example/kernel_v021_example.dart
//   dart run example/kernel_v021_example.dart --self-fund

import 'package:permissionless/permissionless.dart';

import 'kernel_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseKernelArgs(args);
  final result = await runKernelVersion(
    version: KernelVersion.v0_2_1,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
