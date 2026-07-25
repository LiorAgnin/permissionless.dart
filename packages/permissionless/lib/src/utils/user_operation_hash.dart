import 'package:web3dart/web3dart.dart';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/typed_data.dart';
import '../types/user_operation.dart';
import 'encoding.dart';
import 'message_hash.dart';
import 'packed_user_operation.dart';

/// The userOpHash for a UserOperation, for every supported EntryPoint version.
///
/// This is the digest an account signs, and the value the EntryPoint recomputes
/// during validation. Accounts should call this rather than reimplementing the
/// packing rules, which differ per version in ways that are easy to get subtly
/// wrong.
///
/// ## How the versions differ
///
/// - **v0.6** — `keccak(abi.encode(keccak(packedFields), entryPoint, chainId))`
///   over the unpacked gas fields.
/// - **v0.7** — the same outer shape, but over the packed
///   `accountGasLimits` / `gasFees` / `paymasterAndData` layout.
/// - **v0.8 and v0.9** — an EIP-712 typed-data digest over
///   `PackedUserOperation`, with the EntryPoint as `verifyingContract`. See
///   [getUserOperationTypedData].
/// - **v0.9** additionally excludes any paymaster signature from the digest.
///
/// ## Parameters
///
/// [userOperation] must be a [UserOperationV06] for
/// [EntryPointVersion.v06] and a [UserOperationV07] for every later version;
/// a mismatch throws [ArgumentError] rather than silently hashing the wrong
/// layout.
///
/// [delegationAddress] supplies the EIP-7702 delegate for operations whose
/// factory is the `0x7702` marker. The EntryPoint substitutes the account's
/// actual delegate when hashing, so omitting it for a 7702 operation produces a
/// digest the chain will not agree with.
///
/// Example:
/// ```dart
/// final hash = getUserOperationHash(
///   userOperation: userOp,
///   entryPointAddress: EntryPointAddresses.v09,
///   entryPointVersion: EntryPointVersion.v09,
///   chainId: BigInt.one,
/// );
/// final signature = await owner.signPersonalMessage(hash);
/// ```
String getUserOperationHash({
  required UserOperation userOperation,
  required EthereumAddress entryPointAddress,
  required EntryPointVersion entryPointVersion,
  required BigInt chainId,
  EthereumAddress? delegationAddress,
}) {
  switch (entryPointVersion) {
    case EntryPointVersion.v06:
      return _wrapWithEntryPoint(
        _packUserOperationV06(_asV06(userOperation, entryPointVersion)),
        entryPointAddress,
        chainId,
      );

    case EntryPointVersion.v07:
      return _wrapWithEntryPoint(
        _packUserOperationV07(
          _checkedV07(userOperation, entryPointVersion),
          delegationAddress: delegationAddress,
        ),
        entryPointAddress,
        chainId,
      );

    case EntryPointVersion.v08:
    case EntryPointVersion.v09:
      return hashTypedData(
        getUserOperationTypedData(
          userOperation: _checkedV07(userOperation, entryPointVersion),
          entryPointAddress: entryPointAddress,
          chainId: chainId,
          delegationAddress: delegationAddress,
        ),
      );
  }
}

/// The EIP-712 typed data an EntryPoint v0.8 or v0.9 UserOperation is signed
/// over.
///
/// Use this when an owner signs via `eth_signTypedData_v4` and needs the
/// structured payload rather than a bare digest; [getUserOperationHash]
/// returns the digest of exactly this.
///
/// The domain is `ERC4337` / version `1`, bound to [chainId] and the
/// EntryPoint. The message is the packed operation, with two substitutions the
/// EntryPoint performs while hashing:
///
/// - `initCode` becomes `delegate ‖ factoryData` for EIP-7702 operations, so
///   the digest commits to the code the account will actually run.
/// - `paymasterAndData` drops any paymaster signature and its length,
///   retaining only the magic marker — see [getHashedPaymasterAndData].
TypedData getUserOperationTypedData({
  required UserOperationV07 userOperation,
  required EthereumAddress entryPointAddress,
  required BigInt chainId,
  EthereumAddress? delegationAddress,
}) =>
    TypedData(
      domain: TypedDataDomain(
        name: 'ERC4337',
        version: '1',
        chainId: chainId,
        verifyingContract: entryPointAddress,
      ),
      types: const {
        'EIP712Domain': [
          TypedDataField(name: 'name', type: 'string'),
          TypedDataField(name: 'version', type: 'string'),
          TypedDataField(name: 'chainId', type: 'uint256'),
          TypedDataField(name: 'verifyingContract', type: 'address'),
        ],
        'PackedUserOperation': [
          TypedDataField(name: 'sender', type: 'address'),
          TypedDataField(name: 'nonce', type: 'uint256'),
          TypedDataField(name: 'initCode', type: 'bytes'),
          TypedDataField(name: 'callData', type: 'bytes'),
          TypedDataField(name: 'accountGasLimits', type: 'bytes32'),
          TypedDataField(name: 'preVerificationGas', type: 'uint256'),
          TypedDataField(name: 'gasFees', type: 'bytes32'),
          TypedDataField(name: 'paymasterAndData', type: 'bytes'),
        ],
      },
      primaryType: 'PackedUserOperation',
      message: {
        'sender': userOperation.sender.hex,
        'nonce': userOperation.nonce.toString(),
        'initCode':
            getInitCode(userOperation, delegationAddress: delegationAddress),
        'callData': userOperation.callData,
        'accountGasLimits': getAccountGasLimits(userOperation),
        'preVerificationGas': userOperation.preVerificationGas.toString(),
        'gasFees': getGasFees(userOperation),
        'paymasterAndData':
            getHashedPaymasterAndData(getPaymasterAndData(userOperation)),
      },
    );

// ============================================================================
// Internals
// ============================================================================

/// Binds a packed operation to an EntryPoint and chain:
/// `keccak(abi.encode(keccak(packed), entryPoint, chainId))`.
///
/// Shared by the v0.6 and v0.7 hash paths. From v0.8 onwards this binding moves
/// into the EIP-712 domain instead.
String _wrapWithEntryPoint(
  String packed,
  EthereumAddress entryPointAddress,
  BigInt chainId,
) {
  final packedHash = keccak256(Hex.decode(packed));
  final hashInput = Hex.concat([
    Hex.fromBytes(packedHash),
    AbiEncoder.encodeAddress(entryPointAddress),
    AbiEncoder.encodeUint256(chainId),
  ]);
  return Hex.fromBytes(keccak256(Hex.decode(hashInput)));
}

/// `abi.encode` of the v0.6 UserOperation fields, with dynamic fields hashed.
String _packUserOperationV06(UserOperationV06 userOp) => Hex.concat([
      AbiEncoder.encodeAddress(userOp.sender),
      AbiEncoder.encodeUint256(userOp.nonce),
      Hex.fromBytes(keccak256(Hex.decode(userOp.initCode))),
      Hex.fromBytes(keccak256(Hex.decode(userOp.callData))),
      AbiEncoder.encodeUint256(userOp.callGasLimit),
      AbiEncoder.encodeUint256(userOp.verificationGasLimit),
      AbiEncoder.encodeUint256(userOp.preVerificationGas),
      AbiEncoder.encodeUint256(userOp.maxFeePerGas),
      AbiEncoder.encodeUint256(userOp.maxPriorityFeePerGas),
      Hex.fromBytes(keccak256(Hex.decode(userOp.paymasterAndData))),
    ]);

/// `abi.encode` of the v0.7 packed UserOperation fields.
String _packUserOperationV07(
  UserOperationV07 userOp, {
  EthereumAddress? delegationAddress,
}) {
  final initCode = getInitCode(userOp, delegationAddress: delegationAddress);
  final paymasterAndData =
      getHashedPaymasterAndData(getPaymasterAndData(userOp));

  return Hex.concat([
    AbiEncoder.encodeAddress(userOp.sender),
    AbiEncoder.encodeUint256(userOp.nonce),
    Hex.fromBytes(keccak256(Hex.decode(initCode))),
    Hex.fromBytes(keccak256(Hex.decode(userOp.callData))),
    getAccountGasLimits(userOp),
    AbiEncoder.encodeUint256(userOp.preVerificationGas),
    getGasFees(userOp),
    Hex.fromBytes(keccak256(Hex.decode(paymasterAndData))),
  ]);
}

UserOperationV06 _asV06(UserOperation userOp, EntryPointVersion version) {
  if (userOp is! UserOperationV06) {
    throw ArgumentError.value(
      userOp.runtimeType.toString(),
      'userOperation',
      'EntryPoint ${version.value} requires a UserOperationV06',
    );
  }
  return userOp;
}

/// Narrows to [UserOperationV07] and rejects a paymaster signature on the
/// versions that have no concept of one.
UserOperationV07 _checkedV07(UserOperation userOp, EntryPointVersion version) {
  if (userOp is! UserOperationV07) {
    throw ArgumentError.value(
      userOp.runtimeType.toString(),
      'userOperation',
      'EntryPoint ${version.value} requires a UserOperationV07',
    );
  }
  if (userOp.paymasterSignature != null && version != EntryPointVersion.v09) {
    throw ArgumentError.value(
      userOp.paymasterSignature,
      'userOperation.paymasterSignature',
      'paymaster signatures were introduced in EntryPoint v0.9; '
          '${version.value} has no such field',
    );
  }
  return userOp;
}
