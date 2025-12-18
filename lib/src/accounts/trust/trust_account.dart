import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../../utils/message_hash.dart';
import '../account_owner.dart';
import 'constants.dart';

/// Configuration for creating a Trust smart account.
class TrustSmartAccountConfig {
  TrustSmartAccountConfig({
    required this.owner,
    required this.chainId,
    BigInt? index,
    this.customFactoryAddress,
    this.customVerificationFacetAddress,
    this.nonceKey,
    this.publicClient,
    this.address,
  }) : index = index ?? BigInt.zero;

  /// The owner of this Trust account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Salt/index for deterministic address generation.
  final BigInt index;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom verification facet address.
  final EthereumAddress? customVerificationFacetAddress;

  /// Optional custom nonce key.
  final BigInt? nonceKey;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthereumAddress? address;
}

/// A Trust (Barz) smart account implementation for ERC-4337 v0.6.
///
/// Trust Wallet's smart account uses a diamond-based architecture with
/// verification facets. This implementation only supports EntryPoint v0.6.
///
/// Example:
/// ```dart
/// final account = createTrustSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Trust account: $address');
/// ```
class TrustSmartAccount implements SmartAccountV06 {
  TrustSmartAccount(this._config)
      : _factoryAddress =
            _config.customFactoryAddress ?? TrustAddresses.factory,
        _verificationFacetAddress = _config.customVerificationFacetAddress ??
            TrustAddresses.secp256k1VerificationFacet;

  final TrustSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  final EthereumAddress _verificationFacetAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The index/salt used for address derivation.
  BigInt get index => _config.index;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address (v0.6).
  @override
  EthereumAddress get entryPoint => EntryPointAddresses.v06;

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

  /// Gets the deterministic address of this Trust account.
  ///
  /// Note: Trust uses getSenderAddress via EntryPoint simulation.
  /// This implementation computes a deterministic address locally.
  @override
  Future<EthereumAddress> getAddress() async {
    if (_cachedAddress != null) {
      return _cachedAddress!;
    }

    // Option 1: Use pre-computed address if provided
    if (_config.address != null) {
      _cachedAddress = _config.address;
      return _cachedAddress!;
    }

    // Option 2: Compute address via RPC if publicClient is provided
    if (_config.publicClient != null) {
      final initCode = await getInitCode();
      _cachedAddress = await _config.publicClient!.getSenderAddress(
        initCode: initCode,
        entryPoint: entryPoint,
      );
      return _cachedAddress!;
    }

    // Option 3: Neither address nor publicClient provided
    throw StateError(
      'Trust account address cannot be computed without a client. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }

  /// Gets the init code for deploying this Trust account.
  @override
  Future<String> getInitCode() async {
    final factoryData = _encodeCreateAccount();
    return Hex.concat([
      _factoryAddress.hex,
      Hex.strip0x(factoryData),
    ]);
  }

  /// Gets the factory address and data for UserOperation v0.7.
  ///
  /// Note: Trust only supports v0.6, so this returns v0.6-compatible format.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    final data = _encodeCreateAccount();
    return (factory: _factoryAddress, factoryData: data);
  }

  /// Encodes the createAccount factory call.
  String _encodeCreateAccount() {
    // createAccount(address _verificationFacet, bytes _owner, uint256 _salt)
    // The owner is the 20-byte address (not public key, despite Barz docs)
    // This matches permissionless.js implementation
    final ownerBytes = Hex.decode(_config.owner.address.hex);
    // Pad to 32-byte boundary
    final paddedLength = ((ownerBytes.length + 31) ~/ 32) * 32;
    final paddedOwner = Uint8List(paddedLength)..setAll(0, ownerBytes);

    return Hex.concat([
      TrustSelectors.createAccount,
      AbiEncoder.encodeAddress(_verificationFacetAddress),
      // Dynamic bytes parameter offset
      AbiEncoder.encodeUint256(BigInt.from(96)), // offset to bytes
      AbiEncoder.encodeUint256(_config.index),
      // Bytes length
      AbiEncoder.encodeUint256(BigInt.from(ownerBytes.length)),
      // Bytes data (padded to 32-byte boundary)
      Hex.fromBytes(paddedOwner),
    ]);
  }

  /// Encodes a single call.
  @override
  String encodeCall(Call call) {
    // execute(address dest, uint256 value, bytes func)
    final dataBytes = Hex.decode(call.data);

    return Hex.concat([
      TrustSelectors.execute,
      AbiEncoder.encodeAddress(call.to),
      AbiEncoder.encodeUint256(call.value),
      // Dynamic bytes parameter: offset, length, data
      AbiEncoder.encodeUint256(BigInt.from(96)), // offset to bytes
      AbiEncoder.encodeUint256(BigInt.from(dataBytes.length)),
      if (dataBytes.isNotEmpty)
        Hex.fromBytes(
          Uint8List.fromList(
            dataBytes + List.filled((32 - dataBytes.length % 32) % 32, 0),
          ),
        ),
    ]);
  }

  /// Encodes multiple calls using executeBatch.
  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }
    if (calls.length == 1) {
      return encodeCall(calls.first);
    }

    return _encodeExecuteBatch(calls);
  }

  /// Encodes executeBatch call.
  String _encodeExecuteBatch(List<Call> calls) {
    final addresses = calls.map((c) => c.to).toList();
    final values = calls.map((c) => c.value).toList();
    final dataList = calls.map((c) => c.data).toList();

    // Calculate offsets
    const headerSize = 3 * 32; // 3 dynamic array offsets
    final addressArraySize = 32 + addresses.length * 32;
    final valuesArraySize = 32 + values.length * 32;

    final parts = <String>[
      TrustSelectors.executeBatch,
      // Offsets to dynamic arrays
      AbiEncoder.encodeUint256(BigInt.from(headerSize)),
      AbiEncoder.encodeUint256(BigInt.from(headerSize + addressArraySize)),
      AbiEncoder.encodeUint256(
        BigInt.from(headerSize + addressArraySize + valuesArraySize),
      ),
      // Addresses array
      AbiEncoder.encodeUint256(BigInt.from(addresses.length)),
      ...addresses.map((a) => Hex.strip0x(AbiEncoder.encodeAddress(a))),
      // Values array
      AbiEncoder.encodeUint256(BigInt.from(values.length)),
      ...values.map((v) => Hex.strip0x(AbiEncoder.encodeUint256(v))),
      // Bytes array
      AbiEncoder.encodeUint256(BigInt.from(dataList.length)),
    ];

    // Calculate offsets for each bytes element
    var currentOffset = dataList.length * 32;
    final bytesOffsets = <int>[];
    for (var i = 0; i < dataList.length; i++) {
      bytesOffsets.add(currentOffset);
      final bytes = Hex.decode(dataList[i]);
      final paddedSize = bytes.isEmpty ? 0 : ((bytes.length + 31) ~/ 32) * 32;
      currentOffset += 32 + paddedSize;
    }

    // Add offsets
    for (final offset in bytesOffsets) {
      parts.add(Hex.strip0x(AbiEncoder.encodeUint256(BigInt.from(offset))));
    }

    // Add each bytes element
    for (var i = 0; i < dataList.length; i++) {
      final bytes = Hex.decode(dataList[i]);
      parts.add(
        Hex.strip0x(AbiEncoder.encodeUint256(BigInt.from(bytes.length))),
      );
      if (bytes.isNotEmpty) {
        final paddedSize = ((bytes.length + 31) ~/ 32) * 32;
        parts.add(
          Hex.strip0x(
            Hex.fromBytes(
              Uint8List.fromList(
                bytes + List.filled(paddedSize - bytes.length, 0),
              ),
            ),
          ),
        );
      }
    }

    return Hex.concat(parts);
  }

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() =>
      '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

  /// Signs a UserOperation v0.7.
  ///
  /// Note: Trust only supports v0.6. Use signUserOperationV06 instead.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async =>
      throw UnsupportedError(
        'Trust Smart Account only supports EntryPoint v0.6. '
        'Use signUserOperationV06 instead.',
      );

  /// Signs a UserOperation v0.6.
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) async {
    final userOpHash = _computeUserOpHashV06(userOp);
    return _config.owner.signPersonalMessage(userOpHash);
  }

  /// Signs a personal message (EIP-191) with Barz wrapper.
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    return _signWithBarzWrapper(messageHash);
  }

  /// Signs EIP-712 typed data with Barz wrapper.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final hash = hashTypedData(typedData);
    return _signWithBarzWrapper(hash);
  }

  /// Wraps and signs a hash with the Barz EIP-712 domain.
  Future<String> _signWithBarzWrapper(String hashedMessage) async {
    final accountAddress = await getAddress();

    // Barz wraps messages with its domain
    final wrappedTypedData = TypedData(
      domain: TypedDataDomain(
        name: 'Barz',
        version: 'v0.2.0',
        chainId: _config.chainId,
        verifyingContract: accountAddress,
      ),
      types: {
        'BarzMessage': [
          const TypedDataField(name: 'message', type: 'bytes'),
        ],
      },
      primaryType: 'BarzMessage',
      message: {'message': hashedMessage},
    );

    // Trust signs typed data with personal message prefix
    final hash = hashTypedData(wrappedTypedData);
    return _config.owner.signPersonalMessage(hash);
  }

  /// Computes the userOpHash for v0.6.
  String _computeUserOpHashV06(UserOperationV06 userOp) {
    final packed = _packUserOpForHashV06(userOp);
    final packedHash = keccak256(Hex.decode(packed));

    final hashInput = Hex.concat([
      Hex.fromBytes(packedHash),
      AbiEncoder.encodeAddress(entryPoint),
      AbiEncoder.encodeUint256(_config.chainId),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(hashInput)));
  }

  /// Packs a UserOperation v0.6 for hashing.
  String _packUserOpForHashV06(UserOperationV06 userOp) {
    final initCodeHash = keccak256(Hex.decode(userOp.initCode));
    final callDataHash = keccak256(Hex.decode(userOp.callData));
    final paymasterAndDataHash = keccak256(Hex.decode(userOp.paymasterAndData));

    return Hex.concat([
      AbiEncoder.encodeAddress(userOp.sender),
      AbiEncoder.encodeUint256(userOp.nonce),
      Hex.fromBytes(initCodeHash),
      Hex.fromBytes(callDataHash),
      AbiEncoder.encodeUint256(userOp.callGasLimit),
      AbiEncoder.encodeUint256(userOp.verificationGasLimit),
      AbiEncoder.encodeUint256(userOp.preVerificationGas),
      AbiEncoder.encodeUint256(userOp.maxFeePerGas),
      AbiEncoder.encodeUint256(userOp.maxPriorityFeePerGas),
      Hex.fromBytes(paymasterAndDataHash),
    ]);
  }
}

/// Creates a Trust (Barz) smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Trust accounts only support EntryPoint v0.6.
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createTrustSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Trust account: $address');
/// ```
TrustSmartAccount createTrustSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  BigInt? index,
  EthereumAddress? customFactoryAddress,
  EthereumAddress? customVerificationFacetAddress,
  BigInt? nonceKey,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    TrustSmartAccount(
      TrustSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        index: index,
        customFactoryAddress: customFactoryAddress,
        customVerificationFacetAddress: customVerificationFacetAddress,
        nonceKey: nonceKey,
        publicClient: publicClient,
        address: address,
      ),
    );
