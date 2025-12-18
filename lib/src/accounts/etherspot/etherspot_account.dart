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
import '../../utils/erc7579.dart';
import '../../utils/message_hash.dart';
import '../account_owner.dart';
import 'constants.dart';

/// Configuration for creating an Etherspot smart account.
class EtherspotSmartAccountConfig {
  EtherspotSmartAccountConfig({
    required this.owner,
    required this.chainId,
    BigInt? index,
    this.customAddresses,
    this.address,
    this.publicClient,
  }) : index = index ?? BigInt.zero;

  /// The account owner.
  final AccountOwner owner;

  /// Chain ID for the network.
  final BigInt chainId;

  /// Index/salt for address derivation.
  final BigInt index;

  /// Custom contract addresses (optional).
  final EtherspotCustomAddresses? customAddresses;

  /// Pre-computed account address (optional).
  ///
  /// If provided, this address will be used directly.
  /// If not provided but [publicClient] is set, the address will be
  /// computed on-demand via [PublicClient.getSenderAddress].
  final EthereumAddress? address;

  /// Public client for on-chain address computation (optional).
  ///
  /// If provided, allows `getAddress` to compute the account address
  /// via RPC call to the EntryPoint. This matches how permissionless.js
  /// handles Etherspot address computation.
  final PublicClient? publicClient;
}

/// Custom addresses for Etherspot contracts.
class EtherspotCustomAddresses {
  const EtherspotCustomAddresses({
    this.factory,
    this.bootstrap,
    this.ecdsaValidator,
  });

  final EthereumAddress? factory;
  final EthereumAddress? bootstrap;
  final EthereumAddress? ecdsaValidator;
}

/// Etherspot ModularEtherspotWallet smart account implementation.
///
/// This implements the ERC-4337 smart account interface for Etherspot's
/// modular wallet. It uses ERC-7579 for call encoding and EntryPoint v0.7.
class EtherspotSmartAccount implements SmartAccount {
  EtherspotSmartAccount(this._config);

  final EtherspotSmartAccountConfig _config;
  EthereumAddress? _cachedAddress;

  /// The account owner.
  AccountOwner get owner => _config.owner;

  @override
  BigInt get chainId => _config.chainId;

  /// The salt index.
  BigInt get index => _config.index;

  /// The factory address.
  EthereumAddress get factory =>
      _config.customAddresses?.factory ?? EtherspotAddresses.factory;

  /// The bootstrap address.
  EthereumAddress get bootstrap =>
      _config.customAddresses?.bootstrap ?? EtherspotAddresses.bootstrap;

  /// The ECDSA validator address.
  EthereumAddress get ecdsaValidator =>
      _config.customAddresses?.ecdsaValidator ??
      EtherspotAddresses.ecdsaValidator;

  @override
  EthereumAddress get entryPoint => EntryPointAddresses.v07;

  @override
  BigInt get nonceKey {
    // Etherspot nonce key encoding:
    // validatorAddress (20 bytes) + validatorMode (1 byte) + validatorType (1 byte) + nonceKey (2 bytes)
    // Total: 24 bytes
    // See: getNonceKeyWithEncoding in permissionless.js
    final validatorHex = Hex.strip0x(ecdsaValidator.hex);
    const validatorMode = '00'; // DEFAULT
    const validatorType = '00'; // ROOT
    const nonceKeySuffix = '0000'; // 2 bytes

    // Concatenate: validator (40 chars) + mode (2 chars) + type (2 chars) + nonce (4 chars) = 48 chars = 24 bytes
    final encoding = '$validatorHex$validatorMode$validatorType$nonceKeySuffix';
    return BigInt.parse(encoding, radix: 16);
  }

  @override
  Future<EthereumAddress> getAddress() async {
    if (_cachedAddress != null) return _cachedAddress!;

    // Option 1: Use pre-computed address
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
      'Etherspot account address cannot be computed locally. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }

  @override
  Future<String> getInitCode() async {
    final factoryInfo = await getFactoryData();
    if (factoryInfo == null) return '0x';
    return Hex.concat([
      factoryInfo.factory.hex,
      Hex.strip0x(factoryInfo.factoryData),
    ]);
  }

  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    // Factory: createAccount(bytes32 salt, bytes initCode)
    final salt = Hex.fromBigInt(index, byteLength: 32);
    final initCode = _encodeInitCode();

    // Encode createAccount call
    final factoryData = Hex.concat([
      EtherspotSelectors.createAccount,
      Hex.strip0x(salt), // bytes32 salt (already 32 bytes)
      // bytes initCode - dynamic parameter
      AbiEncoder.encodeUint256(BigInt.from(64)), // offset to bytes
      AbiEncoder.encodeBytes(initCode),
    ]);

    return (factory: factory, factoryData: factoryData);
  }

  /// Encodes the initialization code.
  /// Format: abi.encode(owner, bootstrapAddress, initMSAData)
  String _encodeInitCode() {
    final initMSAData = _encodeInitMSA();

    // abi.encode(address owner, address bootstrap, bytes initMSAData)
    return Hex.concat([
      AbiEncoder.encodeAddress(owner.address),
      AbiEncoder.encodeAddress(bootstrap),
      // bytes initMSAData - dynamic parameter
      AbiEncoder.encodeUint256(BigInt.from(96)), // offset to bytes (3 * 32)
      AbiEncoder.encodeBytes(initMSAData),
    ]);
  }

  /// Encodes initMSA call.
  /// initMSA(BootstrapConfig[] validators, BootstrapConfig[] executors,
  ///   BootstrapConfig hook, BootstrapConfig[] fallbacks)
  /// where BootstrapConfig = (address module, bytes data)
  String _encodeInitMSA() {
    // Build validators array with ECDSA validator
    final validatorOnInstall = _encodeOnInstall('0x');
    final validatorConfig =
        _encodeBootstrapConfig(ecdsaValidator, validatorOnInstall);

    // Build executors array with zero address (matching TS implementation)
    final zeroOnInstall = _encodeOnInstall('0x');
    final executorConfig = _encodeBootstrapConfig(zeroAddress, zeroOnInstall);

    // Hook - single BootstrapConfig (not array)
    final hookConfig =
        _encodeBootstrapConfigTuple(zeroAddress, _encodeOnInstall('0x'));

    // Fallbacks array with zero address (matching TS implementation)
    final fallbackConfig = _encodeBootstrapConfig(zeroAddress, zeroOnInstall);

    // Calculate offsets for dynamic parameters
    // Header: 4 offsets * 32 = 128 bytes
    const headerSize = 4 * 32;

    // validators array size
    final validatorsSize = _calculateArraySize([validatorConfig]);
    // executors array size (1 element with zeroAddress)
    final executorsSize = _calculateArraySize([executorConfig]);
    // hook is inline (tuple, not dynamic by itself for offset calculation)
    // But the bytes inside the tuple is dynamic
    final hookSize = _calculateTupleSize(hookConfig);

    final parts = <String>[
      EtherspotSelectors.initMSA,
      // Offsets
      AbiEncoder.encodeUint256(BigInt.from(headerSize)), // validators
      AbiEncoder.encodeUint256(
        BigInt.from(headerSize + validatorsSize),
      ), // executors
      AbiEncoder.encodeUint256(
        BigInt.from(headerSize + validatorsSize + executorsSize),
      ), // hook
      AbiEncoder.encodeUint256(
        BigInt.from(headerSize + validatorsSize + executorsSize + hookSize),
      ), // fallbacks
      // validators array
      _encodeBootstrapConfigArray([validatorConfig]),
      // executors array (1 element with zeroAddress)
      _encodeBootstrapConfigArray([executorConfig]),
      // hook (single tuple)
      hookConfig,
      // fallbacks array (1 element with zeroAddress)
      _encodeBootstrapConfigArray([fallbackConfig]),
    ];

    return Hex.concat(parts);
  }

  /// Encodes onInstall(bytes data) call.
  String _encodeOnInstall(String data) {
    final dataBytes = Hex.decode(data);
    // Pad to next 32-byte boundary
    final paddedLength = ((dataBytes.length + 31) ~/ 32) * 32;
    return Hex.concat([
      EtherspotSelectors.onInstall,
      // bytes data - dynamic parameter
      AbiEncoder.encodeUint256(BigInt.from(32)), // offset
      AbiEncoder.encodeUint256(BigInt.from(dataBytes.length)),
      if (dataBytes.isNotEmpty)
        Hex.padRight(
          Hex.fromBytes(Uint8List.fromList(dataBytes)),
          paddedLength,
        ),
    ]);
  }

  /// Creates a BootstrapConfig tuple struct.
  ({EthereumAddress module, String data}) _encodeBootstrapConfig(
    EthereumAddress module,
    String data,
  ) =>
      (module: module, data: data);

  /// Encodes a single BootstrapConfig tuple for hook (inline, not in array).
  String _encodeBootstrapConfigTuple(EthereumAddress module, String data) {
    // Tuple (address, bytes) - address is static, bytes is dynamic
    final dataBytes = Hex.decode(data);
    // Pad to next 32-byte boundary
    final paddedLength = ((dataBytes.length + 31) ~/ 32) * 32;
    return Hex.concat([
      AbiEncoder.encodeAddress(module),
      AbiEncoder.encodeUint256(BigInt.from(64)), // offset to bytes (2 * 32)
      AbiEncoder.encodeUint256(BigInt.from(dataBytes.length)),
      if (dataBytes.isNotEmpty)
        Hex.padRight(
          Hex.fromBytes(Uint8List.fromList(dataBytes)),
          paddedLength,
        ),
    ]);
  }

  /// Calculates the size of a BootstrapConfig tuple.
  int _calculateTupleSize(String encodedTuple) => Hex.byteLength(encodedTuple);

  /// Calculates size of a BootstrapConfig array encoding.
  int _calculateArraySize(
    List<({EthereumAddress module, String data})> configs,
  ) {
    if (configs.isEmpty) return 32; // Just length = 0

    // Array structure:
    // - length (32 bytes)
    // - offsets for each element (n * 32 bytes)
    // - element data
    var size = 32 + configs.length * 32;
    for (final config in configs) {
      final dataBytes = Hex.decode(config.data);
      // Each element: address (32) + offset to bytes (32) + bytes length (32) + bytes data (padded)
      size += 32 + 32 + 32;
      if (dataBytes.isNotEmpty) {
        size += ((dataBytes.length + 31) ~/ 32) * 32;
      }
    }
    return size;
  }

  /// Encodes a BootstrapConfig[] array.
  String _encodeBootstrapConfigArray(
    List<({EthereumAddress module, String data})> configs,
  ) {
    if (configs.isEmpty) {
      return Hex.strip0x(AbiEncoder.encodeUint256(BigInt.zero));
    }

    final parts = <String>[
      AbiEncoder.encodeUint256(BigInt.from(configs.length)),
    ];

    // Calculate offsets for each element
    var currentOffset = configs.length * 32;
    final elementOffsets = <int>[];
    final elementData = <String>[];

    for (final config in configs) {
      elementOffsets.add(currentOffset);
      final dataBytes = Hex.decode(config.data);
      // Pad to next 32-byte boundary
      final paddedLength = ((dataBytes.length + 31) ~/ 32) * 32;
      final encoded = Hex.concat([
        AbiEncoder.encodeAddress(config.module),
        AbiEncoder.encodeUint256(
          BigInt.from(64),
        ), // offset to bytes within tuple
        AbiEncoder.encodeUint256(BigInt.from(dataBytes.length)),
        if (dataBytes.isNotEmpty)
          Hex.padRight(
            Hex.fromBytes(Uint8List.fromList(dataBytes)),
            paddedLength,
          ),
      ]);
      elementData.add(encoded);
      currentOffset += Hex.byteLength(encoded);
    }

    // Add offsets
    for (final offset in elementOffsets) {
      parts.add(Hex.strip0x(AbiEncoder.encodeUint256(BigInt.from(offset))));
    }

    // Add element data
    for (final data in elementData) {
      parts.add(Hex.strip0x(data));
    }

    return Hex.concat(parts);
  }

  @override
  String encodeCall(Call call) => encode7579Execute(call);

  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('Calls list cannot be empty');
    }
    if (calls.length == 1) {
      return encodeCall(calls.first);
    }
    return encode7579ExecuteBatch(calls);
  }

  @override
  String getStubSignature() => etherspotDummyEcdsaSignature;

  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    // Hash the user operation
    final opHash = _hashUserOperation(userOp);

    // Sign with owner (uses personal message signing)
    // Etherspot signUserOperation returns just the signature without validator prefix
    // This differs from signMessage/signTypedData which DO include the prefix
    return owner.signPersonalMessage(opHash);
  }

  /// Signs a personal message (EIP-191).
  ///
  /// Returns signature with validator prefix.
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    final signature = await owner.signPersonalMessage(messageHash);

    // Prepend validator address
    final validatorHex = Hex.strip0x(ecdsaValidator.hex).toLowerCase();
    final sigHex = Hex.strip0x(signature);
    return '0x$validatorHex$sigHex';
  }

  /// Signs EIP-712 typed data.
  ///
  /// Returns signature with validator prefix.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final hash = hashTypedData(typedData);
    final signature = await owner.signPersonalMessage(hash);

    // Prepend validator address
    final validatorHex = Hex.strip0x(ecdsaValidator.hex).toLowerCase();
    final sigHex = Hex.strip0x(signature);
    return '0x$validatorHex$sigHex';
  }

  String _hashUserOperation(UserOperationV07 userOp) {
    // Pack user operation fields according to ERC-4337 v0.7
    final packedData = _packUserOpV7(userOp);
    final opHash = keccak256(Hex.decode(packedData));

    // Hash with entry point and chain ID
    final finalHashInput = Hex.concat([
      Hex.fromBytes(opHash),
      AbiEncoder.encodeAddress(entryPoint),
      AbiEncoder.encodeUint256(chainId),
    ]);
    final finalHash = keccak256(Hex.decode(finalHashInput));

    return Hex.fromBytes(finalHash);
  }

  String _packUserOpV7(UserOperationV07 userOp) {
    // Pack according to EntryPoint v0.7 format
    final initCodeHash = keccak256(Hex.decode(_getInitCodeFromUserOp(userOp)));
    final callDataHash = keccak256(Hex.decode(userOp.callData));
    final accountGasLimits = _packAccountGasLimits(
      userOp.verificationGasLimit,
      userOp.callGasLimit,
    );
    final gasFees = _packGasFees(
      userOp.maxPriorityFeePerGas,
      userOp.maxFeePerGas,
    );
    final paymasterAndDataHash = keccak256(
      Hex.decode(_getPaymasterAndData(userOp)),
    );

    return Hex.concat([
      AbiEncoder.encodeAddress(userOp.sender),
      AbiEncoder.encodeUint256(userOp.nonce),
      Hex.fromBytes(initCodeHash),
      Hex.fromBytes(callDataHash),
      accountGasLimits,
      AbiEncoder.encodeUint256(userOp.preVerificationGas),
      gasFees,
      Hex.fromBytes(paymasterAndDataHash),
    ]);
  }

  String _getInitCodeFromUserOp(UserOperationV07 userOp) {
    if (userOp.factory == null || userOp.factoryData == null) {
      return '0x';
    }
    return Hex.concat([userOp.factory!.hex, userOp.factoryData!]);
  }

  String _getPaymasterAndData(UserOperationV07 userOp) {
    if (userOp.paymaster == null) {
      return '0x';
    }
    return Hex.concat([
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

  String _packAccountGasLimits(
    BigInt verificationGasLimit,
    BigInt callGasLimit,
  ) {
    final vgl = verificationGasLimit.toRadixString(16).padLeft(32, '0');
    final cgl = callGasLimit.toRadixString(16).padLeft(32, '0');
    return '0x$vgl$cgl';
  }

  String _packGasFees(BigInt maxPriorityFeePerGas, BigInt maxFeePerGas) {
    final mpf = maxPriorityFeePerGas.toRadixString(16).padLeft(32, '0');
    final mf = maxFeePerGas.toRadixString(16).padLeft(32, '0');
    return '0x$mpf$mf';
  }
}

/// Creates an Etherspot smart account.
///
/// Etherspot requires on-chain address computation. Provide either:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final owner = PrivateKeyOwner('0x...');
/// final publicClient = createPublicClient(url: rpcUrl);
///
/// final account = createEtherspotSmartAccount(
///   owner: owner,
///   chainId: BigInt.from(1),
///   publicClient: publicClient,
/// );
///
/// // Address is computed automatically on first access
/// final address = await account.getAddress();
/// ```
EtherspotSmartAccount createEtherspotSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  BigInt? index,
  EtherspotCustomAddresses? customAddresses,
  EthereumAddress? address,
  PublicClient? publicClient,
}) =>
    EtherspotSmartAccount(
      EtherspotSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        index: index,
        customAddresses: customAddresses,
        address: address,
        publicClient: publicClient,
      ),
    );
