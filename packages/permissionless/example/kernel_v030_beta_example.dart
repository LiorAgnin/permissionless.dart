// Example: Kernel v0.3.0-beta smart account (EntryPoint v0.7 default)
//
// 4-arg initialize; EP-v0.7 default in permissionless.js.
//
// USAGE:
//   dart run example/kernel_v030_beta_example.dart
//   dart run example/kernel_v030_beta_example.dart --self-fund

import 'package:permissionless/permissionless.dart';

import 'kernel_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseKernelArgs(args);
  final result = await runKernelVersion(
    version: KernelVersion.v0_3_0_beta,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
