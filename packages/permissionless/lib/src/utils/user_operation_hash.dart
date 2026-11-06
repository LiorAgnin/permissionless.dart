import 'package:web3dart/web3dart.dart' show keccak256;

import '../types/address.dart';
import '../types/hex.dart';
import '../types/typed_data.dart';
import '../types/user_operation.dart';
import 'encoding.dart';
import 'message_hash.dart';
import 'packed_user_operation.dart';

/// Computes the hash the EntryPoint assigns to a UserOperation
/// (`EntryPoint.getUserOpHash`), mirroring viem `getUserOperationHash`:
/// - **v0.6** ([UserOperationV06]): `keccak256(abi.encode(keccak256(pack(op)),
///   entryPoint, chainId))` with unpacked uint256 gas fields
/// - **v0.7** ([UserOperationV07]): the same outer hash over the packed layout
/// - **v0.8** ([UserOperationV07]): EIP-712 hash of
///   [getUserOperationTypedData]
///
/// When [userOperation]'s factory is the EIP-7702 marker, pass the delegation
/// (authorization) address as [eip7702DelegationAddress] so `initCode` is
/// `delegation ‖ factoryData`, as the EntryPoint hashes it.
///
/// Throws [ArgumentError] when the operation layout does not match
/// [entryPointVersion].
String getUserOperationHash({
  required UserOperation userOperation,
  required EthereumAddress entryPointAddress,
  required EntryPointVersion entryPointVersion,
  required BigInt chainId,
  EthereumAddress? eip7702DelegationAddress,
}) {
  switch ((entryPointVersion, userOperation)) {
    case (EntryPointVersion.v06, final UserOperationV06 op):
      return _outerHash(_packV06(op), entryPointAddress, chainId);
    case (EntryPointVersion.v07, final UserOperationV07 op):
      return _outerHash(
        _packV07(op, eip7702DelegationAddress),
        entryPointAddress,
        chainId,
      );
    case (EntryPointVersion.v08, final UserOperationV07 op):
      return hashTypedData(
        getUserOperationTypedData(
          userOperation: op,
          entryPointAddress: entryPointAddress,
          chainId: chainId,
          eip7702DelegationAddress: eip7702DelegationAddress,
        ),
      );
    case _:
      throw ArgumentError.value(
        userOperation.runtimeType,
        'userOperation',
        'EntryPoint ${entryPointVersion.value} does not hash this '
            'UserOperation layout',
      );
  }
}

/// The EIP-712 typed data an EntryPoint v0.8 account signs for
/// [userOperation] (viem `getUserOperationTypedData`).
TypedData getUserOperationTypedData({
  required UserOperationV07 userOperation,
  required EthereumAddress entryPointAddress,
  required BigInt chainId,
  EthereumAddress? eip7702DelegationAddress,
}) =>
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
        'initCode': getInitCode(
          userOperation,
          delegationAddress: eip7702DelegationAddress,
        ),
        'callData': userOperation.callData,
        'accountGasLimits': getAccountGasLimits(userOperation),
        'preVerificationGas': userOperation.preVerificationGas.toString(),
        'gasFees': getGasFees(userOperation),
        'paymasterAndData': getPaymasterAndData(userOperation),
      },
    );

String _keccakHex(String data) => Hex.fromBytes(keccak256(Hex.decode(data)));

String _outerHash(
  String packed,
  EthereumAddress entryPoint,
  BigInt chainId,
) =>
    _keccakHex(
      Hex.concat([
        _keccakHex(packed),
        AbiEncoder.encodeAddress(entryPoint),
        AbiEncoder.encodeUint256(chainId),
      ]),
    );

String _packV06(UserOperationV06 op) => Hex.concat([
      AbiEncoder.encodeAddress(op.sender),
      AbiEncoder.encodeUint256(op.nonce),
      _keccakHex(op.initCode),
      _keccakHex(op.callData),
      AbiEncoder.encodeUint256(op.callGasLimit),
      AbiEncoder.encodeUint256(op.verificationGasLimit),
      AbiEncoder.encodeUint256(op.preVerificationGas),
      AbiEncoder.encodeUint256(op.maxFeePerGas),
      AbiEncoder.encodeUint256(op.maxPriorityFeePerGas),
      _keccakHex(op.paymasterAndData),
    ]);

String _packV07(UserOperationV07 op, EthereumAddress? delegation) =>
    Hex.concat([
      AbiEncoder.encodeAddress(op.sender),
      AbiEncoder.encodeUint256(op.nonce),
      _keccakHex(getInitCode(op, delegationAddress: delegation)),
      _keccakHex(op.callData),
      getAccountGasLimits(op),
      AbiEncoder.encodeUint256(op.preVerificationGas),
      getGasFees(op),
      _keccakHex(getPaymasterAndData(op)),
    ]);
