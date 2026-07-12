// Example: Kernel v0.3.3 smart account (EntryPoint v0.7, EIP-7702 capable)
//
// Standard (non-EIP-7702) deployment via meta factory. For EIP-7702
// code-delegation flow see eip7702_kernel_example.dart.
//
// USAGE:
//   dart run example/kernel_v033_example.dart
//   dart run example/kernel_v033_example.dart --self-fund

import 'package:permissionless/permissionless.dart';

import 'kernel_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseKernelArgs(args);
  final result = await runKernelVersion(
    version: KernelVersion.v0_3_3,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
