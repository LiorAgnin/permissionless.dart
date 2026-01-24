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

/// Configuration for creating a Thirdweb smart account.
class ThirdwebSmartAccountConfig {
  /// Creates a configuration for a Thirdweb smart account.
  ///
  /// Thirdweb accounts support both EntryPoint v0.6 and v0.7.
  ///
  /// - [owner]: The account owner who controls the account
  /// - [chainId]: Chain ID for the network
  /// - [salt]: Salt for deterministic address generation (defaults to "0x")
  /// - [entryPointVersion]: EntryPoint version (defaults to v0.7)
  /// - [nonceKey]: Custom nonce key for parallel transaction support
  /// - [publicClient]: For RPC-based address computation (recommended)
  /// - [address]: Pre-computed address (alternative to publicClient)
  ThirdwebSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.salt = '0x',
    this.entryPointVersion = EntryPointVersion.v07,
    this.customFactoryAddress,
    this.nonceKey,
    this.publicClient,
    this.address,
  });

  /// The owner of this Thirdweb account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Salt for deterministic address generation.
  final String salt;

  /// EntryPoint version (default: v0.7).
  final EntryPointVersion entryPointVersion;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom nonce key.
  final BigInt? nonceKey;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthereumAddress? address;
}

/// A Thirdweb smart account implementation for ERC-4337.
///
/// Thirdweb accounts support both EntryPoint v0.6 and v0.7.
///
/// Example:
/// ```dart
/// final account = createThirdwebSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Thirdweb account: $address');
/// ```
class ThirdwebSmartAccount implements SmartAccount {
  /// Creates a Thirdweb smart account from the given configuration.
  ///
  /// Prefer using [createThirdwebSmartAccount] factory function instead
  /// of calling this constructor directly.
  ThirdwebSmartAccount(this._config)
      : _factoryAddress = _config.customFactoryAddress ??
            (_config.entryPointVersion == EntryPointVersion.v07
                ? ThirdwebAddresses.factoryV07
                : ThirdwebAddresses.factoryV06);

  final ThirdwebSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The EntryPoint version.
  EntryPointVersion get entryPointVersion => _config.entryPointVersion;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address.
  @override
  EthereumAddress get entryPoint =>
      _config.entryPointVersion == EntryPointVersion.v07
          ? EntryPointAddresses.v07
          : EntryPointAddresses.v06;

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Thirdweb account.
  ///
  /// Note: Thirdweb uses an on-chain factory call to compute the address.
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
      'Thirdweb account address cannot be computed without a client. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }

  /// Gets the init code for deploying this Thirdweb account.
  @override
  Future<String> getInitCode() async {
    final factoryData = _encodeCreateAccount();
    return Hex.concat([
      _factoryAddress.hex,
      Hex.strip0x(factoryData),
    ]);
  }

  /// Gets the factory address and data for UserOperation v0.7.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    final data = _encodeCreateAccount();
    return (factory: _factoryAddress, factoryData: data);
  }

  /// Encodes the createAccount factory call.
  String _encodeCreateAccount() {
    // createAccount(address _admin, bytes _salt)
    final salt = _config.salt.isEmpty ? '0x' : _config.salt;
    final saltBytes = Hex.decode(salt);

    return Hex.concat([
      ThirdwebSelectors.createAccount,
      AbiEncoder.encodeAddress(_config.owner.address),
      // Dynamic bytes parameter: offset, length, data
      AbiEncoder.encodeUint256(BigInt.from(64)), // offset to bytes
      AbiEncoder.encodeUint256(BigInt.from(saltBytes.length)),
      if (saltBytes.isNotEmpty)
        Hex.fromBytes(
          Uint8List.fromList(
            saltBytes + List.filled((32 - saltBytes.length % 32) % 32, 0),
          ),
        ),
    ]);
  }

  /// Encodes a single call.
  @override
  String encodeCall(Call call) {
    // execute(address dest, uint256 value, bytes func)
    final dataBytes = Hex.decode(call.data);

    return Hex.concat([
      ThirdwebSelectors.execute,
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

    // executeBatch(address[] dest, uint256[] values, bytes[] func)
    return _encodeExecuteBatch(calls);
  }

  /// Encodes executeBatch call.
  String _encodeExecuteBatch(List<Call> calls) {
    // This is complex ABI encoding with dynamic arrays
    // Address array, uint256 array, bytes array

    final addresses = calls.map((c) => c.to).toList();
    final values = calls.map((c) => c.value).toList();
    final dataList = calls.map((c) => c.data).toList();

    // Calculate offsets
    const headerSize = 3 * 32; // 3 dynamic array offsets
    final addressArraySize = 32 + addresses.length * 32; // length + addresses
    final valuesArraySize = 32 + values.length * 32; // length + values

    final parts = <String>[
      ThirdwebSelectors.executeBatch,
      // Offsets to dynamic arrays
      AbiEncoder.encodeUint256(BigInt.from(headerSize)), // addresses offset
      AbiEncoder.encodeUint256(
        BigInt.from(headerSize + addressArraySize),
      ), // values offset
      AbiEncoder.encodeUint256(
        BigInt.from(headerSize + addressArraySize + valuesArraySize),
      ), // data offset
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

  /// Signs a UserOperation.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = _computeUserOpHash(userOp);
    return _config.owner.signPersonalMessage(userOpHash);
  }

  /// Signs a personal message (EIP-191) with Thirdweb wrapper.
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    final accountAddress = await getAddress();

    // Thirdweb wraps messages with Account domain
    final wrappedTypedData = TypedData(
      domain: TypedDataDomain(
        name: 'Account',
        version: '1',
        chainId: _config.chainId,
        verifyingContract: accountAddress,
      ),
      types: {
        'AccountMessage': [
          const TypedDataField(name: 'message', type: 'bytes'),
        ],
      },
      primaryType: 'AccountMessage',
      message: {'message': messageHash},
    );

    // Thirdweb signs typed data with personal message prefix
    final wrappedHash = hashTypedData(wrappedTypedData);
    return _config.owner.signPersonalMessage(wrappedHash);
  }

  /// Signs EIP-712 typed data with Thirdweb wrapper.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final accountAddress = await getAddress();

    // Check if self-verifying contract
    if (typedData.domain.verifyingContract?.hex.toLowerCase() ==
        accountAddress.hex.toLowerCase()) {
      final hash = hashTypedData(typedData);
      return _config.owner.signPersonalMessage(hash);
    }

    // Wrap the typed data hash
    final typedHash = hashTypedData(typedData);
    final wrappedHash = Hex.concat([
      AbiEncoder.encodeUint256(BigInt.parse(Hex.strip0x(typedHash), radix: 16)),
    ]);

    final wrappedTypedData = TypedData(
      domain: TypedDataDomain(
        name: 'Account',
        version: '1',
        chainId: _config.chainId,
        verifyingContract: accountAddress,
      ),
      types: {
        'AccountMessage': [
          const TypedDataField(name: 'message', type: 'bytes'),
        ],
      },
      primaryType: 'AccountMessage',
      message: {'message': wrappedHash},
    );

    // Thirdweb signs typed data with personal message prefix
    final finalHash = hashTypedData(wrappedTypedData);
    return _config.owner.signPersonalMessage(finalHash);
  }

  /// Computes the userOpHash for signing.
  String _computeUserOpHash(UserOperationV07 userOp) {
    final packed = _packUserOpForHash(userOp);
    final packedHash = keccak256(Hex.decode(packed));

    final hashInput = Hex.concat([
      Hex.fromBytes(packedHash),
      AbiEncoder.encodeAddress(entryPoint),
      AbiEncoder.encodeUint256(_config.chainId),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(hashInput)));
  }

  /// Packs a UserOperation for hashing.
  String _packUserOpForHash(UserOperationV07 userOp) {
    var initCode = '0x';
    if (userOp.factory != null) {
      initCode = Hex.concat([
        userOp.factory!.hex,
        Hex.strip0x(userOp.factoryData ?? '0x'),
      ]);
    }
    final initCodeHash = keccak256(Hex.decode(initCode));
    final callDataHash = keccak256(Hex.decode(userOp.callData));

    final accountGasLimits = Hex.concat([
      Hex.fromBigInt(userOp.verificationGasLimit, byteLength: 16),
      Hex.fromBigInt(userOp.callGasLimit, byteLength: 16),
    ]);

    final gasFees = Hex.concat([
      Hex.fromBigInt(userOp.maxPriorityFeePerGas, byteLength: 16),
      Hex.fromBigInt(userOp.maxFeePerGas, byteLength: 16),
    ]);

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
    final paymasterAndDataHash = keccak256(Hex.decode(paymasterAndData));

    return Hex.concat([
      AbiEncoder.encodeAddress(userOp.sender),
      AbiEncoder.encodeUint256(userOp.nonce),
      Hex.fromBytes(initCodeHash),
      Hex.fromBytes(callDataHash),
      Hex.strip0x(accountGasLimits),
      AbiEncoder.encodeUint256(userOp.preVerificationGas),
      Hex.strip0x(gasFees),
      Hex.fromBytes(paymasterAndDataHash),
    ]);
  }
}

/// Creates a Thirdweb smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createThirdwebSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Thirdweb account: $address');
/// ```
ThirdwebSmartAccount createThirdwebSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  String salt = '0x',
  EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  EthereumAddress? customFactoryAddress,
  BigInt? nonceKey,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    ThirdwebSmartAccount(
      ThirdwebSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        salt: salt,
        entryPointVersion: entryPointVersion,
        customFactoryAddress: customFactoryAddress,
        nonceKey: nonceKey,
        publicClient: publicClient,
        address: address,
      ),
    );
