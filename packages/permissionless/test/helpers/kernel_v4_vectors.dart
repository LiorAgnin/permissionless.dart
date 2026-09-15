import 'dart:convert';
import 'dart:io';

import 'package:permissionless/permissionless.dart';

/// Loads the vectors generated from the pinned Kernel v4.0 Solidity
/// contracts. See `tool/kernel_v4_vectors/` to regenerate.
Map<String, dynamic> loadKernelV4Vectors() {
  final file = File('test/fixtures/kernel_v4_vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Rebuilds the `Install[]` packages described by a fixture address case.
List<KernelV4Install> kernelV4PackagesFromCase(Map<String, dynamic> c) =>
    (c['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (p) => KernelV4Install(
            moduleType: BigInt.from(p['moduleType'] as int),
            module: EthereumAddress.fromHex(p['module'] as String),
            moduleData: p['moduleData'] as String,
            internalData: p['internalData'] as String,
          ),
        )
        .toList();
