import 'dart:typed_data';

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../standard_execute.dart';
import 'constants.dart';

// Kernel contract functions, declared once as Solidity signatures; the hex
// values in [KernelSelectors] are their selectors.

/// v0.2.x `execute(address to, uint256 value, bytes data, uint8 operation)`.
const String kernelV2ExecuteSignature = 'execute(address,uint256,bytes,uint8)';

/// v0.2.x factory `createAccount(address implementation, bytes data,
/// uint256 index)`.
const String kernelV2CreateAccountSignature =
    'createAccount(address,bytes,uint256)';

/// v0.2.x `initialize(address defaultValidator, bytes enableData)`.
const String kernelV2InitializeSignature = 'initialize(address,bytes)';

/// v0.3.x inner factory `createAccount(bytes data, bytes32 salt)`.
const String kernelV3CreateAccountSignature = 'createAccount(bytes,bytes32)';

/// v0.3.x meta factory `deployWithFactory(address factory, bytes createData,
/// bytes32 salt)`.
const String kernelDeployWithFactorySignature =
    'deployWithFactory(address,bytes,bytes32)';

/// v0.3.0-beta `initialize(bytes21 rootValidator, address hook,
/// bytes validatorData, bytes hookData)`.
const String kernelV3BetaInitializeSignature =
    'initialize(bytes21,address,bytes,bytes)';

/// v0.3.1+ `initialize(bytes21 rootValidator, address hook,
/// bytes validatorData, bytes hookData, bytes[] initConfig)`.
const String kernelV3InitializeSignature =
    'initialize(bytes21,address,bytes,bytes,bytes[])';

/// ROOT_MODE prefix of Kernel v0.2.x UserOperation signatures (sudo mode;
/// permissionless.js always uses it since paymasters are external).
const String kernelV2RootMode = '0x00000000';

/// Encodes [call] as Kernel v0.2.x `execute` with operation = call (0).
String encodeKernelV2Execute(Call call) => AbiEncoder.encodeFunctionData(
      kernelV2ExecuteSignature,
      [call.to, call.value, call.data, 0],
    );

/// Kernel v0.2.x call data: one call as `execute`, several as
/// `executeBatch((address,uint256,bytes)[])`.
String encodeKernelV2Calls(List<Call> calls) {
  if (calls.isEmpty) {
    throw ArgumentError('At least one call is required');
  }
  if (calls.length == 1) return encodeKernelV2Execute(calls.single);
  return encodeExecuteBatch(calls, ExecuteBatchAbi.callTuples);
}

/// Decodes Kernel v0.2.x `execute(address,uint256,bytes,uint8)`.
List<Call> decodeKernelV2Execute(String callData) {
  final args =
      AbiEncoder.decodeFunctionData(kernelV2ExecuteSignature, callData);
  return [
    Call(
      to: args[0] as EthereumAddress,
      value: args[1] as BigInt,
      data: Hex.fromBytes(args[2] as Uint8List),
    ),
  ];
}

/// Inverse of [encodeKernelV2Calls].
List<Call> decodeKernelV2Calls(String callData) {
  if (Hex.slice(callData, 0, 4).toLowerCase() ==
      AbiEncoder.functionSelector(kernelV2ExecuteSignature)) {
    return decodeKernelV2Execute(callData);
  }
  final args = AbiEncoder.decodeFunctionData(
    ExecuteBatchAbi.callTuples.signature,
    callData,
  );
  return [
    for (final t in (args[0] as List).cast<List<dynamic>>())
      Call(
        to: t[0] as EthereumAddress,
        value: t[1] as BigInt,
        data: Hex.fromBytes(t[2] as Uint8List),
      ),
  ];
}

final BigInt _maxUint16 = BigInt.from(0xffff);

/// Throws [ArgumentError] unless [nonceKey] fits the 2-byte v0.3.x salt slot.
void checkKernelV3NonceKey(BigInt? nonceKey, KernelVersion version) {
  if (nonceKey != null && nonceKey > _maxUint16) {
    throw ArgumentError(
      'nonce key must be equal or less than 2 bytes(maxUint16) for '
      'Kernel version ${version.value}',
    );
  }
}

/// Kernel v0.3.x 24-byte nonce key (permissionless.js
/// `getNonceKeyWithEncoding`): mode sudo (1) ‖ type root (1) ‖
/// [validator] (20) ‖ [nonceKey] salt (2).
BigInt encodeKernelV3NonceKey({
  required EthereumAddress validator,
  BigInt? nonceKey,
}) =>
    Hex.toBigInt(
      Hex.concat([
        Hex.fromBigInt(BigInt.from(KernelValidatorMode.sudo), byteLength: 1),
        Hex.fromBigInt(BigInt.from(KernelValidatorType.root), byteLength: 1),
        validator.hex,
        Hex.fromBigInt(nonceKey ?? BigInt.zero, byteLength: 2),
      ]),
    );
