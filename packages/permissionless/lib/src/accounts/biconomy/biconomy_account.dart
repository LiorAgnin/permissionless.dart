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

/// Configuration for creating a Biconomy smart account.
@Deprecated('Use NexusSmartAccountConfig instead')
class BiconomySmartAccountConfig {
  /// Creates a configuration for a Biconomy smart account.
  ///
  /// Required parameters:
  /// - [owner]: The account owner that controls this smart account
  /// - [chainId]: The chain ID for signature domain separation
  ///
  /// Optional parameters:
  /// - [index]: Salt for deterministic address generation (defaults to 0)
  /// - [customFactoryAddress]: Override the default factory address
  /// - [customEcdsaModuleAddress]: Override the default ECDSA module address
  /// - [publicClient]: Client for computing the account address via RPC
  /// - [address]: Pre-computed account address to skip address derivation
  BiconomySmartAccountConfig({
    required this.owner,
    required this.chainId,
    BigInt? index,
    this.customFactoryAddress,
    this.customEcdsaModuleAddress,
    this.publicClient,
    this.address,
  }) : index = index ?? BigInt.zero;

  /// The owner of this Biconomy account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Salt/index for deterministic address generation.
  final BigInt index;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom ECDSA module address.
  final EthereumAddress? customEcdsaModuleAddress;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthereumAddress? address;
}

/// A Biconomy smart account implementation for ERC-4337 v0.6.
///
/// **Deprecated**: Biconomy Smart Account is deprecated. Use [NexusSmartAccount]
/// for new projects.
///
/// Key features:
/// - ECDSA Ownership Module for signature validation
/// - Custom execute functions (execute_ncC, executeBatch_y6U)
/// - EntryPoint v0.6 only
///
/// Example:
/// ```dart
/// // ignore: deprecated_member_use_from_same_package
/// final account = createBiconomySmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
/// ```
@Deprecated('Use NexusSmartAccount instead')
class BiconomySmartAccount implements SmartAccountV06 {
  /// Creates a Biconomy smart account from the given configuration.
  ///
  /// Prefer using [createBiconomySmartAccount] factory function instead
  /// of calling this constructor directly.
  ///
  /// The account uses the factory and ECDSA module addresses from the config,
  /// or falls back to the default Biconomy addresses if not specified.
  BiconomySmartAccount(this._config)
      : _factoryAddress =
            _config.customFactoryAddress ?? BiconomyAddresses.factory,
        _ecdsaModuleAddress = _config.customEcdsaModuleAddress ??
            BiconomyAddresses.ecdsaOwnershipModule;

  final BiconomySmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  final EthereumAddress _ecdsaModuleAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The EntryPoint version (always v0.6 for Biconomy).
  EntryPointVersion get entryPointVersion => EntryPointVersion.v06;

  /// The index/salt used for address derivation.
  BigInt get index => _config.index;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address (v0.6).
  @override
  EthereumAddress get entryPoint => EntryPointAddresses.v06;

  /// The nonce key (always 0 for Biconomy v0.6).
  @override
  BigInt get nonceKey => BigInt.zero;

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Biconomy account.
  ///
  /// The address is computed locally using CREATE2 formula:
  /// `address = keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))[12:]`
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

    // Option 2: Compute address locally using CREATE2
    // This is more reliable than RPC-based getSenderAddress which can fail
    // when the account is already deployed or in edge cases.
    _cachedAddress = _computeAccountAddress();
    return _cachedAddress!;
  }

  /// Computes the account address using CREATE2.
  EthereumAddress _computeAccountAddress() {
    // Build the module setup data: initForSmartAccount(address owner)
    final ecdsaOwnershipInitData = Hex.concat([
      BiconomySelectors.initForSmartAccount,
      AbiEncoder.encodeAddress(_config.owner.address),
    ]);

    // ABI encode: init(address handler, address moduleSetupContract, bytes moduleSetupData)
    // Layout: selector + address + address + offset for bytes + bytes data
    final initialisationData = Hex.concat([
      BiconomySelectors.init,
      AbiEncoder.encodeAddress(BiconomyAddresses.defaultFallbackHandler),
      AbiEncoder.encodeAddress(_ecdsaModuleAddress),
      // Offset for dynamic bytes (3 * 32 = 96 bytes from start of params)
      AbiEncoder.encodeUint256(BigInt.from(96)),
      // Bytes data (encodeBytes includes length prefix + 32-byte padding)
      Hex.strip0x(AbiEncoder.encodeBytes(ecdsaOwnershipInitData)),
    ]);

    // Compute the salt
    final initHash = keccak256(Hex.decode(initialisationData));
    final saltInput = Hex.concat([
      Hex.fromBytes(initHash),
      Hex.fromBigInt(_config.index, byteLength: 32),
    ]);
    final salt = keccak256(Hex.decode(saltInput));

    // Proxy creation code (simplified)
    // In production, this should match BiconomyAddresses.accountV2Logic
    final deploymentCode = Hex.concat([
      _getBiconomyProxyCreationCode(),
      AbiEncoder.encodeUint256(
        Hex.toBigInt(BiconomyAddresses.accountV2Logic.hex),
      ),
    ]);

    final initCodeHash = keccak256(Hex.decode(deploymentCode));

    // CREATE2: address = keccak256(0xff ++ factory ++ salt ++ initCodeHash)[12:]
    final preImage = Hex.concat([
      '0xff',
      Hex.strip0x(_factoryAddress.hex),
      Hex.fromBytes(salt),
      Hex.fromBytes(initCodeHash),
    ]);

    final addressHash = keccak256(Hex.decode(preImage));
    return EthereumAddress.fromHex(Hex.slice(Hex.fromBytes(addressHash), 12));
  }

  /// Returns the Biconomy proxy creation code.
  // This is the actual proxy creation code used by Biconomy
  String _getBiconomyProxyCreationCode() =>
      '0x6080346100aa57601f61012038819003918201601f19168301916001600160401b038311848410176100af578084926020946040528339810103126100aa57516001600160a01b0381168082036100aa5715610065573055604051605a90816100c68239f35b60405162461bcd60e51b815260206004820152601e60248201527f496e76616c696420696d706c656d656e746174696f6e206164647265737300006044820152606490fd5b600080fd5b634e487b7160e01b600052604160045260246000fdfe608060405230546000808092368280378136915af43d82803e156020573d90f35b3d90fdfea2646970667358221220a03b18dce0be0b4c9afe58a9eb85c35205e2cf087da098bbf1d23945bf89496064736f6c63430008110033';

  /// Gets the init code for deploying this Biconomy account.
  @override
  Future<String> getInitCode() async {
    final factoryData = _encodeDeployCounterFactualAccount();
    return Hex.concat([
      _factoryAddress.hex,
      Hex.strip0x(factoryData),
    ]);
  }

  /// Gets the factory address and data for UserOperation.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    final data = _encodeDeployCounterFactualAccount();
    return (factory: _factoryAddress, factoryData: data);
  }

  /// Encodes the deployCounterFactualAccount factory call.
  String _encodeDeployCounterFactualAccount() {
    // Build the module setup data: initForSmartAccount(address owner)
    final ecdsaOwnershipInitData = Hex.concat([
      BiconomySelectors.initForSmartAccount,
      AbiEncoder.encodeAddress(_config.owner.address),
    ]);

    // ABI encode: deployCounterFactualAccount(address, bytes, uint256)
    // Layout: selector + address + offset for bytes + uint256 + bytes data
    return Hex.concat([
      BiconomySelectors.deployCounterFactualAccount,
      AbiEncoder.encodeAddress(_ecdsaModuleAddress),
      // Offset for dynamic bytes (3 * 32 = 96 bytes from start of params)
      AbiEncoder.encodeUint256(BigInt.from(96)),
      AbiEncoder.encodeUint256(_config.index),
      // Bytes data (encodeBytes includes length prefix + 32-byte padding)
      Hex.strip0x(AbiEncoder.encodeBytes(ecdsaOwnershipInitData)),
    ]);
  }

  /// Encodes a single call for execution.
  @override
  String encodeCall(Call call) => Hex.concat([
        BiconomySelectors.execute,
        AbiEncoder.encodeAddress(call.to),
        AbiEncoder.encodeUint256(call.value),
        // Offset for dynamic bytes
        AbiEncoder.encodeUint256(BigInt.from(96)),
        // Encode the data
        Hex.strip0x(AbiEncoder.encodeBytes(call.data)),
      ]);

  /// Encodes multiple calls using executeBatch_y6U.
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

  /// Encodes a batch execute call.
  String _encodeExecuteBatch(List<Call> calls) {
    final destArray = calls.map((c) => c.to).toList();
    final valuesArray = calls.map((c) => c.value).toList();
    final dataArray = calls.map((c) => c.data).toList();

    // Offsets for each dynamic array
    const destOffset = 3 * 32;
    final destEncoded = _encodeAddressArray(destArray);
    final valuesOffset = destOffset + Hex.byteLength(destEncoded);
    final valuesEncoded = _encodeUint256Array(valuesArray);
    final dataArrayOffset = valuesOffset + Hex.byteLength(valuesEncoded);
    final dataArrayEncoded = _encodeBytesArray(dataArray);

    return Hex.concat([
      BiconomySelectors.executeBatch,
      AbiEncoder.encodeUint256(BigInt.from(destOffset)),
      AbiEncoder.encodeUint256(BigInt.from(valuesOffset)),
      AbiEncoder.encodeUint256(BigInt.from(dataArrayOffset)),
      Hex.strip0x(destEncoded),
      Hex.strip0x(valuesEncoded),
      Hex.strip0x(dataArrayEncoded),
    ]);
  }

  /// Encodes an array of addresses.
  String _encodeAddressArray(List<EthereumAddress> addresses) => Hex.concat([
        AbiEncoder.encodeUint256(BigInt.from(addresses.length)),
        ...addresses.map((a) => Hex.strip0x(AbiEncoder.encodeAddress(a))),
      ]);

  /// Encodes an array of uint256 values.
  String _encodeUint256Array(List<BigInt> values) => Hex.concat([
        AbiEncoder.encodeUint256(BigInt.from(values.length)),
        ...values.map((v) => Hex.strip0x(AbiEncoder.encodeUint256(v))),
      ]);

  /// Encodes an array of bytes.
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

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() {
    final dynamicPart = Hex.strip0x(_ecdsaModuleAddress.hex).padRight(40, '0');
    return '0x0000000000000000000000000000000000000000000000000000000000000040'
        '000000000000000000000000$dynamicPart'
        '0000000000000000000000000000000000000000000000000000000000000041'
        '81d4b4981670cb18f99f0b4a66446df1bf5b204d24cfcb659bf38ba27a4359b5'
        '711649ec2423c5e1247245eba2964679b6a1dbb85c992ae40b9b00c6935b02ff'
        '1b00000000000000000000000000000000000000000000000000000000000000';
  }

  /// Signs a UserOperation (v0.6).
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) async {
    final userOpHash = _computeUserOpHashV06(userOp);
    final signature = await _config.owner.signPersonalMessage(userOpHash);

    // Biconomy signature format: ABI encoded (signature, moduleAddress)
    return _encodeModuleSignature(signature);
  }

  /// Signs a UserOperation (v0.7) - not supported for Biconomy v0.6 accounts.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) {
    throw UnsupportedError(
      'Biconomy is a v0.6 account. Use signUserOperationV06 instead.',
    );
  }

  /// Signs a personal message (EIP-191).
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    final signature = await _config.owner.signPersonalMessage(messageHash);
    return _encodeModuleSignature(signature);
  }

  /// Signs EIP-712 typed data.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final signature = await _config.owner.signTypedData(typedData);
    return _encodeModuleSignature(signature);
  }

  /// Encodes signature with module address (Biconomy format).
  ///
  /// ABI encode: (bytes signature, address moduleAddress)
  /// Layout for tuple with dynamic + static types:
  /// - offset for bytes (32) pointing to 64
  /// - address value (32)
  /// - bytes length (32) + bytes data (padded to 32-byte boundary)
  String _encodeModuleSignature(String signature) => Hex.concat([
        AbiEncoder.encodeUint256(BigInt.from(64)), // Offset for bytes
        AbiEncoder.encodeAddress(_ecdsaModuleAddress),
        // Use encodeBytes which handles length prefix + padding
        Hex.strip0x(AbiEncoder.encodeBytes(signature)),
      ]);

  /// Computes the userOpHash for v0.6 UserOperation.
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

  /// Packs a v0.6 UserOperation for hashing.
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

/// Creates a Biconomy smart account.
///
/// **Deprecated**: Use [createNexusSmartAccount] for new projects.
@Deprecated('Use createNexusSmartAccount instead')
BiconomySmartAccount createBiconomySmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  BigInt? index,
  EthereumAddress? customFactoryAddress,
  EthereumAddress? customEcdsaModuleAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    BiconomySmartAccount(
      BiconomySmartAccountConfig(
        owner: owner,
        chainId: chainId,
        index: index,
        customFactoryAddress: customFactoryAddress,
        customEcdsaModuleAddress: customEcdsaModuleAddress,
        publicClient: publicClient,
        address: address,
      ),
    );
