import 'dart:convert';
import 'dart:io';

import 'package:permissionless/permissionless.dart';

/// Loads the vectors generated from the pinned Kernel v4.0 Solidity
/// contracts. See `tool/kernel_v4_vectors/` to regenerate.
Map<String, dynamic> loadKernelV4Vectors() {
  final file = File('test/fixtures/kernel_v4_vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Rebuilds the unsigned [UserOperationV07] described by a fixture userOp
/// case (`rootUserOp`, `validatorUserOp`, `permissionUserOp`,
/// `replayableUserOp`, …).
UserOperationV07 kernelV4UserOpFromCase(Map<String, dynamic> c) =>
    UserOperationV07(
      sender: EthereumAddress.fromHex(c['sender'] as String),
      nonce: BigInt.parse(c['nonce'] as String),
      callData: c['callData'] as String,
      callGasLimit: BigInt.from(c['callGasLimit'] as int),
      verificationGasLimit: BigInt.from(c['verificationGasLimit'] as int),
      preVerificationGas: BigInt.from(c['preVerificationGas'] as int),
      maxFeePerGas: BigInt.from(c['maxFeePerGas'] as int),
      maxPriorityFeePerGas: BigInt.from(c['maxPriorityFeePerGas'] as int),
    );

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

/// Rebuilds the app-side typed data of the ERC-1271 TypedDataSign fixture
/// cases — the classic EIP-712 `Mail` example (its nested `Person` reference
/// exercises the encodeType appending rules inside `TypedDataSign`). The
/// field values live on the `typedDataSignRoot` case.
TypedData kernelV4MailTypedDataFromCase(Map<String, dynamic> c) {
  final domain = c['appDomain'] as Map<String, dynamic>;
  return TypedData(
    domain: TypedDataDomain(
      name: domain['name'] as String,
      version: domain['version'] as String,
      chainId: BigInt.from(domain['chainId'] as int),
      verifyingContract:
          EthereumAddress.fromHex(domain['verifyingContract'] as String),
    ),
    types: {
      'Person': [
        const TypedDataField(name: 'name', type: 'string'),
        const TypedDataField(name: 'wallet', type: 'address'),
      ],
      'Mail': [
        const TypedDataField(name: 'from', type: 'Person'),
        const TypedDataField(name: 'to', type: 'Person'),
        const TypedDataField(name: 'contents', type: 'string'),
      ],
    },
    primaryType: 'Mail',
    message: {
      'from': {
        'name': c['mailFromName'] as String,
        'wallet': c['mailFromWallet'] as String,
      },
      'to': {
        'name': c['mailToName'] as String,
        'wallet': c['mailToWallet'] as String,
      },
      'contents': c['mailContents'] as String,
    },
  );
}
