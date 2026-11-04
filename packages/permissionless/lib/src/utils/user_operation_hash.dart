import 'package:web3dart/web3dart.dart' show keccak256;

import '../constants/entry_point.dart';
import '../types/address.dart';
import '../types/hex.dart';
import '../types/typed_data.dart';
import '../types/user_operation.dart';
import 'encoding.dart';
import 'message_hash.dart';
import 'packed_user_operation.dart';

/// Returns the [EntryPointVersion] of a canonical EntryPoint address, or
/// `null` when [entryPoint] is not one of [EntryPointAddresses].
EntryPointVersion? entryPointVersionOf(EthereumAddress entryPoint) {
  for (final version in EntryPointVersion.values) {
    if (EntryPointAddresses.fromVersion(version).hex == entryPoint.hex) {
      return version;
    }
  }
  return null;
}

/// Computes the hash the EntryPoint assigns to a v0.7/v0.8 UserOperation.
///
/// Mirrors viem `getUserOperationHash`:
/// - **v0.7**: `keccak256(abi.encode(keccak256(packedUserOp), entryPoint, chainId))`
/// - **v0.8**: EIP-712 hash of the `PackedUserOperation` typed data with
///   domain `{name: 'ERC4337', version: '1', chainId, verifyingContract}`
///
/// When [userOperation]'s factory is the EIP-7702 marker, pass the delegation
/// (authorization) address as [eip7702DelegationAddress] so `initCode` is
/// `delegation ‖ factoryData`, as the EntryPoint hashes it (viem
/// `getInitCode`).
///
/// Throws [ArgumentError] for [EntryPointVersion.v06], whose UserOperation
/// layout is not [UserOperationV07].
String getUserOperationHash({
  required UserOperationV07 userOperation,
  required EthereumAddress entryPointAddress,
  required EntryPointVersion entryPointVersion,
  required BigInt chainId,
  EthereumAddress? eip7702DelegationAddress,
}) {
  final initCode = getInitCode(
    userOperation,
    delegationAddress: eip7702DelegationAddress,
  );

  switch (entryPointVersion) {
    case EntryPointVersion.v06:
      throw ArgumentError.value(
        entryPointVersion,
        'entryPointVersion',
        'getUserOperationHash takes a v0.7/v0.8 UserOperationV07',
      );
    case EntryPointVersion.v07:
      final packed = Hex.concat([
        AbiEncoder.encodeAddress(userOperation.sender),
        AbiEncoder.encodeUint256(userOperation.nonce),
        Hex.fromBytes(keccak256(Hex.decode(initCode))),
        Hex.fromBytes(keccak256(Hex.decode(userOperation.callData))),
        Hex.strip0x(getAccountGasLimits(userOperation)),
        AbiEncoder.encodeUint256(userOperation.preVerificationGas),
        Hex.strip0x(getGasFees(userOperation)),
        Hex.fromBytes(
          keccak256(Hex.decode(getPaymasterAndData(userOperation))),
        ),
      ]);
      return Hex.fromBytes(
        keccak256(
          Hex.decode(
            Hex.concat([
              Hex.fromBytes(keccak256(Hex.decode(packed))),
              AbiEncoder.encodeAddress(entryPointAddress),
              AbiEncoder.encodeUint256(chainId),
            ]),
          ),
        ),
      );
    case EntryPointVersion.v08:
      return hashTypedData(
        TypedData(
          domain: TypedDataDomain(
            name: 'ERC4337',
            version: '1',
            chainId: chainId,
            verifyingContract: entryPointAddress,
          ),
          types: {
            'EIP712Domain': [
              const TypedDataField(name: 'name', type: 'string'),
              const TypedDataField(name: 'version', type: 'string'),
              const TypedDataField(name: 'chainId', type: 'uint256'),
              const TypedDataField(name: 'verifyingContract', type: 'address'),
            ],
            'PackedUserOperation': [
              const TypedDataField(name: 'sender', type: 'address'),
              const TypedDataField(name: 'nonce', type: 'uint256'),
              const TypedDataField(name: 'initCode', type: 'bytes'),
              const TypedDataField(name: 'callData', type: 'bytes'),
              const TypedDataField(name: 'accountGasLimits', type: 'bytes32'),
              const TypedDataField(name: 'preVerificationGas', type: 'uint256'),
              const TypedDataField(name: 'gasFees', type: 'bytes32'),
              const TypedDataField(name: 'paymasterAndData', type: 'bytes'),
            ],
          },
          primaryType: 'PackedUserOperation',
          message: {
            'sender': userOperation.sender.hex,
            'nonce': userOperation.nonce.toString(),
            'initCode': initCode,
            'callData': userOperation.callData,
            'accountGasLimits': getAccountGasLimits(userOperation),
            'preVerificationGas': userOperation.preVerificationGas.toString(),
            'gasFees': getGasFees(userOperation),
            'paymasterAndData': getPaymasterAndData(userOperation),
          },
        ),
      );
  }
}
