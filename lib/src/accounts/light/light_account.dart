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

/// Configuration for creating a Light smart account.
class LightSmartAccountConfig {
  LightSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.entryPointVersion = EntryPointVersion.v07,
    BigInt? salt,
    this.customFactoryAddress,
    LightAccountVersion? version,
    this.publicClient,
    this.address,
  })  : salt = salt ?? BigInt.zero,
        version =
            version ?? LightAccountVersion.forEntryPoint(entryPointVersion);

  /// The owner of this Light account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// The EntryPoint version to use.
  final EntryPointVersion entryPointVersion;

  /// Light Account version.
  final LightAccountVersion version;

  /// Salt for deterministic address generation.
  final BigInt salt;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Public client for computing the account address via RPC.
  ///
  /// If provided, the account address will be computed using
  /// [PublicClient.getSenderAddress] which simulates account deployment.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  ///
  /// If provided, this address will be used instead of RPC computation.
  /// Use when you already know the account address.
  final EthereumAddress? address;
}

/// An Alchemy Light Account implementation for ERC-4337.
///
/// Light Account is a simple, gas-efficient smart account from Alchemy.
/// It features:
/// - Single owner (ECDSA validation)
/// - EIP-1271 signature validation with wrapped messages
/// - execute/executeBatch for transaction batching
/// - Low gas overhead
///
/// Example:
/// ```dart
/// final account = createLightSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Light account: $address');
/// ```
class LightSmartAccount implements SmartAccount {
  LightSmartAccount(this._config)
      : _factoryAddress = _config.customFactoryAddress ??
            LightAccountFactoryAddresses.fromVersion(_config.version);

  final LightSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The Light Account version.
  LightAccountVersion get version => _config.version;

  /// The EntryPoint version being used.
  EntryPointVersion get entryPointVersion => _config.entryPointVersion;

  /// The salt used for address derivation.
  BigInt get salt => _config.salt;

  @override
  BigInt get chainId => _config.chainId;

  @override
  EthereumAddress get entryPoint =>
      EntryPointAddresses.fromVersion(_config.entryPointVersion);

  @override
  BigInt get nonceKey => BigInt.zero;

  /// Gets the deterministic address of this Light account.
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
      'Light account address cannot be computed without a client. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }

  // String _computeSalt() {
  //   final encoded = Hex.concat([
  //     _config.owner.address.hex,
  //     Hex.fromBigInt(_config.salt, byteLength: 32),
  //   ]);
  //   return Hex.fromBytes(keccak256(Hex.decode(encoded)));
  // }

  // String _computeProxyInitCodeHash() {
  //   // Light Account Factory deploys ERC-1967 proxies
  //   // The init code hash depends on the implementation address
  //   // This is a simplified computation - in production, verify against actual factory
  //   final initData = Hex.concat([
  //     // Proxy creation code (simplified)
  //     '0x3d602d80600a3d3981f3363d3d373d3d3d363d73',
  //     Hex.strip0x(_factoryAddress.hex),
  //     '5af43d82803e903d91602b57fd5bf3',
  //   ]);
  //   return Hex.fromBytes(keccak256(Hex.decode(initData)));
  // }

  @override
  Future<String> getInitCode() async {
    final factoryData = _encodeCreateAccount();
    return Hex.concat([
      _factoryAddress.hex,
      Hex.strip0x(factoryData),
    ]);
  }

  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    final data = _encodeCreateAccount();
    return (factory: _factoryAddress, factoryData: data);
  }

  String _encodeCreateAccount() => Hex.concat([
        LightAccountSelectors.createAccount,
        AbiEncoder.encodeAddress(_config.owner.address),
        AbiEncoder.encodeUint256(_config.salt),
      ]);

  @override
  String encodeCall(Call call) =>
      _encodeExecute(call.to, call.value, call.data);

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

  String _encodeExecute(EthereumAddress to, BigInt value, String data) {
    const dataOffset = 3 * 32;
    final dataEncoded = AbiEncoder.encodeBytes(data);

    return Hex.concat([
      LightAccountSelectors.execute,
      AbiEncoder.encodeAddress(to),
      AbiEncoder.encodeUint256(value),
      AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
      Hex.strip0x(dataEncoded),
    ]);
  }

  String _encodeExecuteBatch(List<Call> calls) {
    final destArray = calls.map((c) => c.to).toList();
    final valuesArray = calls.map((c) => c.value).toList();
    final dataArray = calls.map((c) => c.data).toList();

    const destOffset = 3 * 32;
    final destEncoded = _encodeAddressArray(destArray);
    final valuesOffset = destOffset + Hex.byteLength(destEncoded);
    final valuesEncoded = _encodeUint256Array(valuesArray);
    final dataArrayOffset = valuesOffset + Hex.byteLength(valuesEncoded);
    final dataArrayEncoded = _encodeBytesArray(dataArray);

    return Hex.concat([
      LightAccountSelectors.executeBatch,
      AbiEncoder.encodeUint256(BigInt.from(destOffset)),
      AbiEncoder.encodeUint256(BigInt.from(valuesOffset)),
      AbiEncoder.encodeUint256(BigInt.from(dataArrayOffset)),
      Hex.strip0x(destEncoded),
      Hex.strip0x(valuesEncoded),
      Hex.strip0x(dataArrayEncoded),
    ]);
  }

  String _encodeAddressArray(List<EthereumAddress> addresses) => Hex.concat([
        AbiEncoder.encodeUint256(BigInt.from(addresses.length)),
        ...addresses.map((a) => Hex.strip0x(AbiEncoder.encodeAddress(a))),
      ]);

  String _encodeUint256Array(List<BigInt> values) => Hex.concat([
        AbiEncoder.encodeUint256(BigInt.from(values.length)),
        ...values.map((v) => Hex.strip0x(AbiEncoder.encodeUint256(v))),
      ]);

  String _encodeBytesArray(List<String> dataItems) {
    final length = AbiEncoder.encodeUint256(BigInt.from(dataItems.length));

    var currentOffset = dataItems.length * 32;
    final offsets = <String>[];
    final encodedData = <String>[];

    for (final data in dataItems) {
      offsets.add(
        Hex.strip0x(AbiEncoder.encodeUint256(BigInt.from(currentOffset))),
      );
      final encoded = AbiEncoder.encodeBytes(data);
      encodedData.add(Hex.strip0x(encoded));
      currentOffset += Hex.byteLength(encoded);
    }

    return Hex.concat([length, ...offsets, ...encodedData]);
  }

  @override
  String getStubSignature() {
    // Standard ECDSA stub signature
    const signature =
        '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

    // v2.0.0 prepends signature type
    if (_config.version == LightAccountVersion.v200) {
      return Hex.concat([
        Hex.fromBigInt(
          BigInt.from(LightAccountSignatureType.eoa),
          byteLength: 1,
        ),
        Hex.strip0x(signature),
      ]);
    }

    return signature;
  }

  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = _computeUserOpHash(userOp);
    final signature = await _config.owner.signPersonalMessage(userOpHash);

    // v2.0.0 prepends signature type
    if (_config.version == LightAccountVersion.v200) {
      return Hex.concat([
        Hex.fromBigInt(
          BigInt.from(LightAccountSignatureType.eoa),
          byteLength: 1,
        ),
        Hex.strip0x(signature),
      ]);
    }

    return signature;
  }

  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    final accountAddress = await getAddress();

    // Sign using EIP-1271 wrapper with LightAccountMessage typed data
    final signature = await _signLightAccountMessage(
      accountAddress,
      messageHash,
    );

    // v2.0.0 prepends signature type
    if (_config.version == LightAccountVersion.v200) {
      return Hex.concat([
        Hex.fromBigInt(
          BigInt.from(LightAccountSignatureType.eoa),
          byteLength: 1,
        ),
        Hex.strip0x(signature),
      ]);
    }

    return signature;
  }

  @override
  Future<String> signTypedData(TypedData typedData) async {
    final hash = hashTypedData(typedData);
    final accountAddress = await getAddress();

    // Sign using EIP-1271 wrapper with LightAccountMessage typed data
    final signature = await _signLightAccountMessage(
      accountAddress,
      hash,
    );

    // v2.0.0 prepends signature type
    if (_config.version == LightAccountVersion.v200) {
      return Hex.concat([
        Hex.fromBigInt(
          BigInt.from(LightAccountSignatureType.eoa),
          byteLength: 1,
        ),
        Hex.strip0x(signature),
      ]);
    }

    return signature;
  }

  /// Signs a message hash using the LightAccountMessage EIP-712 wrapper.
  Future<String> _signLightAccountMessage(
    EthereumAddress verifyingContract,
    String hashedMessage,
  ) async {
    final typedData = TypedData(
      domain: TypedDataDomain(
        name: 'LightAccount',
        version: '1',
        chainId: _config.chainId,
        verifyingContract: verifyingContract,
      ),
      types: {
        'LightAccountMessage': [
          const TypedDataField(name: 'message', type: 'bytes'),
        ],
      },
      primaryType: 'LightAccountMessage',
      message: {'message': hashedMessage},
    );

    final hash = hashTypedData(typedData);
    return _config.owner.signPersonalMessage(hash);
  }

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

/// Creates an Alchemy Light smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createLightSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Light account: $address');
/// ```
LightSmartAccount createLightSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  LightAccountVersion? version,
  BigInt? salt,
  EthereumAddress? customFactoryAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    LightSmartAccount(
      LightSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        entryPointVersion: entryPointVersion,
        version: version,
        salt: salt,
        customFactoryAddress: customFactoryAddress,
        publicClient: publicClient,
        address: address,
      ),
    );
