import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' as crypto;
import 'package:web3dart/web3dart.dart' show EthPrivateKey;

import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../../utils/message_hash.dart';
import 'constants.dart';

/// Owner abstraction for EIP-7702 Simple accounts.
///
/// This owner can sign both messages and EIP-7702 authorizations.
abstract class Eip7702SimpleAccountOwner {
  /// The Ethereum address of this owner (the EOA).
  EthereumAddress get address;

  /// Signs a message hash and returns the signature.
  Future<String> signHash(String messageHash);

  /// Signs EIP-712 typed data and returns the signature.
  Future<String> signTypedData(TypedData typedData);

  /// Creates an EIP-7702 authorization for this owner.
  ///
  /// The authorization allows the EOA to delegate code execution to
  /// the specified contract address.
  Future<Eip7702Authorization> createAuthorization({
    required BigInt chainId,
    required EthereumAddress contractAddress,
    required BigInt nonce,
  });
}

/// A local private key owner for EIP-7702 Simple accounts.
class PrivateKeyEip7702Owner implements Eip7702SimpleAccountOwner {
  PrivateKeyEip7702Owner(String privateKeyHex)
      : _privateKey = EthPrivateKey.fromHex(privateKeyHex),
        _privateKeyHex = privateKeyHex;

  final EthPrivateKey _privateKey;
  final String _privateKeyHex;

  @override
  EthereumAddress get address =>
      EthereumAddress.fromHex(_privateKey.address.eip55With0x);

  @override
  Future<String> signHash(String messageHash) async {
    final hash = Hex.decode(messageHash);

    // Sign with personal message prefix
    final sig = _privateKey.signPersonalMessageToUint8List(
      Uint8List.fromList(hash),
    );

    return Hex.fromBytes(sig);
  }

  @override
  Future<String> signTypedData(TypedData typedData) async {
    final hash = hashTypedData(typedData);
    final hashBytes = Hex.decode(hash);

    // Sign the typed data hash directly using the raw sign function.
    // Note: signToEcSignature adds an extra keccak256 hash, which we don't want
    // for EIP-712 typed data (the hash is already computed).
    final sig = crypto.sign(
      Uint8List.fromList(hashBytes),
      _privateKey.privateKey,
    );

    // Pack r, s, v into 65 bytes
    final rBytes = Hex.decode(Hex.fromBigInt(sig.r, byteLength: 32));
    final sBytes = Hex.decode(Hex.fromBigInt(sig.s, byteLength: 32));

    return Hex.fromBytes(Uint8List.fromList([...rBytes, ...sBytes, sig.v]));
  }

  @override
  Future<Eip7702Authorization> createAuthorization({
    required BigInt chainId,
    required EthereumAddress contractAddress,
    required BigInt nonce,
  }) =>
      Eip7702Authorization.sign(
        chainId: chainId,
        contractAddress: contractAddress,
        nonce: nonce,
        privateKey: _privateKeyHex,
      );
}

/// Configuration for creating an EIP-7702 Simple smart account.
class Eip7702SimpleSmartAccountConfig {
  Eip7702SimpleSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.publicClient,
    EthereumAddress? accountLogicAddress,
  }) : accountLogicAddress =
            accountLogicAddress ?? Simple7702AccountAddresses.defaultLogic;

  /// The owner of this EIP-7702 account (the EOA).
  final Eip7702SimpleAccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Public client for checking deployment status.
  ///
  /// Required for EIP-1271 signature validation to check if the account
  /// has been delegated (deployed) before signing messages/typed data.
  final PublicClient? publicClient;

  /// The Simple7702Account logic contract address.
  ///
  /// Defaults to the official eth-infinitism Simple7702Account.
  final EthereumAddress accountLogicAddress;
}

/// An EIP-7702 Simple smart account implementation.
///
/// This account uses EIP-7702 to delegate code execution from an EOA to
/// a Simple7702Account implementation. Key characteristics:
///
/// - **Account address = EOA address**: No separate smart account deployment
/// - **No factory needed**: The authorization delegates code on-demand
/// - **EntryPoint v0.8**: Required for native EIP-7702 support
/// - **Typed data signing**: v0.8 uses EIP-712 typed data for UserOperation signing
///
/// Example:
/// ```dart
/// final account = createEip7702SimpleSmartAccount(
///   owner: PrivateKeyEip7702Owner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // The account address is the same as the owner's EOA address
/// final address = await account.getAddress();
/// print('EIP-7702 account: $address');
///
/// // Get authorization for submitting to bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
class Eip7702SimpleSmartAccount implements Eip7702SmartAccount {
  Eip7702SimpleSmartAccount(this._config);

  final Eip7702SimpleSmartAccountConfig _config;

  /// The owner of this account.
  Eip7702SimpleAccountOwner get owner => _config.owner;

  /// The Simple7702Account logic contract address.
  @override
  EthereumAddress get accountLogicAddress => _config.accountLogicAddress;

  /// Whether this account uses EIP-7702 code delegation.
  @override
  bool get isEip7702 => true;

  /// The EntryPoint version (always v0.8 for EIP-7702).
  EntryPointVersion get entryPointVersion => EntryPointVersion.v08;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address for this account.
  @override
  EthereumAddress get entryPoint => EntryPointAddresses.v08;

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => BigInt.zero;

  /// Gets the address of this EIP-7702 account.
  ///
  /// For EIP-7702 accounts, this is the same as the owner's EOA address.
  @override
  Future<EthereumAddress> getAddress() async => _config.owner.address;

  /// Gets the init code for deploying this account.
  ///
  /// For EIP-7702 accounts, this returns '0x' as no deployment is needed.
  /// The authorization handles code delegation.
  @override
  Future<String> getInitCode() async => '0x';

  /// Gets the factory address and data for UserOperation v0.7/v0.8.
  ///
  /// For EIP-7702 accounts, this returns null as no factory is used.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async => null;

  /// Creates an EIP-7702 authorization for this account.
  ///
  /// The authorization must be included in the transaction that submits
  /// the UserOperation to enable the EOA to execute smart account code.
  ///
  /// [nonce] should be the EOA's current transaction nonce.
  ///
  /// Example:
  /// ```dart
  /// final nonce = await publicClient.getTransactionCount(ownerAddress);
  /// final auth = await account.getAuthorization(nonce: nonce);
  /// ```
  @override
  Future<Eip7702Authorization> getAuthorization({required BigInt nonce}) =>
      _config.owner.createAuthorization(
        chainId: _config.chainId,
        contractAddress: _config.accountLogicAddress,
        nonce: nonce,
      );

  /// Encodes a single call for execution.
  ///
  /// Uses SimpleAccount.execute(address, uint256, bytes).
  @override
  String encodeCall(Call call) =>
      _encodeExecute(call.to, call.value, call.data);

  /// Encodes multiple calls using the v0.8 executeBatch format.
  ///
  /// v0.8 uses a Call[] tuple array instead of separate arrays.
  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }

    if (calls.length == 1) {
      return encodeCall(calls.first);
    }

    // v0.8 executeBatch(Call[] calls) where Call = (address target, uint256 value, bytes data)
    return _encodeExecuteBatchV08(calls);
  }

  /// Encodes a single execute call.
  String _encodeExecute(EthereumAddress to, BigInt value, String data) {
    // execute(address dest, uint256 value, bytes calldata func)
    const dataOffset = 3 * 32;
    final dataEncoded = AbiEncoder.encodeBytes(data);

    return Hex.concat([
      SimpleAccountSelectors.execute,
      AbiEncoder.encodeAddress(to),
      AbiEncoder.encodeUint256(value),
      AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
      Hex.strip0x(dataEncoded),
    ]);
  }

  /// Encodes a v0.8 batch execute call.
  ///
  /// v0.8 format: executeBatch(Call[] calls)
  /// where Call is a tuple (address target, uint256 value, bytes data)
  String _encodeExecuteBatchV08(List<Call> calls) {
    // ABI encoding for tuple array:
    // - offset to array (32 bytes)
    // - array length (32 bytes)
    // - offsets to each tuple (32 bytes each)
    // - tuple data

    const arrayOffset = 32; // Offset to array data

    // Build the encoded call data
    final parts = <String>[
      Hex.strip0x(AbiEncoder.encodeUint256(BigInt.from(arrayOffset))),
      Hex.strip0x(AbiEncoder.encodeUint256(BigInt.from(calls.length))),
    ]
        // Array offset

        // Array length
        ;

    // Calculate offsets for each tuple
    // Each tuple has 3 fields: address (static), uint256 (static), bytes (dynamic)
    // Base offset after the offsets array
    var currentOffset = calls.length * 32;
    final tupleOffsets = <String>[];
    final tupleData = <String>[];

    for (final call in calls) {
      tupleOffsets.add(
        Hex.strip0x(AbiEncoder.encodeUint256(BigInt.from(currentOffset))),
      );

      final encodedTuple = _encodeTupleCall(call);
      tupleData.add(encodedTuple);

      currentOffset += Hex.byteLength('0x$encodedTuple');
    }

    // Add offsets and tuple data
    parts
      ..addAll(tupleOffsets)
      ..addAll(tupleData);

    return Hex.concat([
      SimpleAccountSelectors.executeBatchV08,
      ...parts.map((p) => p.startsWith('0x') ? p : '0x$p'),
    ]);
  }

  /// Encodes a single Call tuple.
  String _encodeTupleCall(Call call) {
    // Tuple: (address target, uint256 value, bytes data)
    // address and uint256 are static, bytes is dynamic

    const bytesOffset = 3 * 32; // After the 3 fields
    final bytesEncoded = AbiEncoder.encodeBytes(call.data);

    return Hex.strip0x(
      Hex.concat([
        AbiEncoder.encodeAddress(call.to),
        AbiEncoder.encodeUint256(call.value),
        AbiEncoder.encodeUint256(BigInt.from(bytesOffset)),
        bytesEncoded,
      ]),
    );
  }

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() =>
      '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

  /// Signs a UserOperation using EIP-712 typed data (v0.8 format).
  ///
  /// EntryPoint v0.8 uses typed data signing instead of raw hash signing.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    // v0.8 uses EIP-712 typed data for signing
    final typedData = _getUserOperationTypedData(userOp);
    return _config.owner.signTypedData(typedData);
  }

  /// Gets the typed data for a UserOperation (for debugging).
  TypedData getUserOperationTypedData(UserOperationV07 userOp) =>
      _getUserOperationTypedData(userOp);

  /// Gets the hash of the UserOperation typed data (for debugging).
  String getUserOperationHash(UserOperationV07 userOp) =>
      hashTypedData(_getUserOperationTypedData(userOp));

  /// Signs a personal message (EIP-191).
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signMessage(String message) async {
    await _ensureDeployedForEip1271();
    final messageHash = hashMessage(message);
    return _config.owner.signHash(messageHash);
  }

  /// Signs EIP-712 typed data.
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    await _ensureDeployedForEip1271();
    return _config.owner.signTypedData(typedData);
  }

  /// Checks if the account is deployed (delegated) before EIP-1271 signing.
  ///
  /// EIP-7702 accounts are not EIP-1271 compliant before delegation because
  /// the EOA has no code to execute `isValidSignature`.
  Future<void> _ensureDeployedForEip1271() async {
    if (_config.publicClient == null) return;

    final address = await getAddress();
    final isDeployed = await _config.publicClient!.isDeployed(address);
    if (!isDeployed) {
      throw StateError(
        'EIP-7702 Simple account is not EIP-1271 compliant before delegation. '
        'Submit a UserOperation with the EIP-7702 authorization first.',
      );
    }
  }

  /// Creates the EIP-712 typed data for a UserOperation.
  ///
  /// This is the v0.8 format for UserOperation signing.
  /// Matches viem's getUserOperationTypedData implementation.
  TypedData _getUserOperationTypedData(UserOperationV07 userOp) {
    // Pack gas limits: verificationGasLimit (16 bytes) + callGasLimit (16 bytes)
    final accountGasLimits = Hex.concat([
      Hex.fromBigInt(userOp.verificationGasLimit, byteLength: 16),
      Hex.fromBigInt(userOp.callGasLimit, byteLength: 16),
    ]);

    // Pack gas fees: maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes)
    final gasFees = Hex.concat([
      Hex.fromBigInt(userOp.maxPriorityFeePerGas, byteLength: 16),
      Hex.fromBigInt(userOp.maxFeePerGas, byteLength: 16),
    ]);

    // Pack paymaster fields into paymasterAndData
    var paymasterAndData = '0x';
    if (userOp.paymaster != null) {
      paymasterAndData = Hex.concat([
        userOp.paymaster!.hex,
        Hex.fromBigInt(
          userOp.paymasterVerificationGasLimit ?? BigInt.zero,
          byteLength: 16,
        ),
        Hex.fromBigInt(
          userOp.paymasterPostOpGasLimit ?? BigInt.zero,
          byteLength: 16,
        ),
        Hex.strip0x(userOp.paymasterData ?? '0x'),
      ]);
    }

    // initCode should match what's in the userOp being sent
    // - If factory is set: concat(factory, factoryData)
    // - If factory is null (account already deployed): '0x'
    String initCode;
    if (userOp.factory != null) {
      initCode = Hex.concat([
        userOp.factory!.hex,
        Hex.strip0x(userOp.factoryData ?? '0x'),
      ]);
    } else {
      initCode = '0x';
    }

    // Per viem: domain name is 'ERC4337' (no hyphen)
    // Per viem: uses raw bytes fields, not hashed versions
    return TypedData(
      domain: TypedDataDomain(
        name: 'ERC4337',
        version: '1',
        chainId: _config.chainId,
        verifyingContract: entryPoint,
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
        'sender': userOp.sender.hex,
        'nonce': userOp.nonce.toString(),
        'initCode': initCode,
        'callData': userOp.callData,
        'accountGasLimits': accountGasLimits,
        'preVerificationGas': userOp.preVerificationGas.toString(),
        'gasFees': gasFees,
        'paymasterAndData': paymasterAndData,
      },
    );
  }
}

/// Creates an EIP-7702 Simple smart account.
///
/// This creates an account that uses EIP-7702 code delegation, enabling
/// an EOA to function as a smart account without deploying a separate contract.
///
/// **Requirements:**
/// - EntryPoint v0.8 (automatically used)
/// - Bundler with EIP-7702 support
/// - Chain with EIP-7702 enabled
///
/// Example:
/// ```dart
/// final account = createEip7702SimpleSmartAccount(
///   owner: PrivateKeyEip7702Owner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // Account address = owner's EOA address
/// final address = await account.getAddress();
///
/// // Create authorization for bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
Eip7702SimpleSmartAccount createEip7702SimpleSmartAccount({
  required Eip7702SimpleAccountOwner owner,
  required BigInt chainId,
  PublicClient? publicClient,
  EthereumAddress? accountLogicAddress,
}) =>
    Eip7702SimpleSmartAccount(
      Eip7702SimpleSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        publicClient: publicClient,
        accountLogicAddress: accountLogicAddress,
      ),
    );
