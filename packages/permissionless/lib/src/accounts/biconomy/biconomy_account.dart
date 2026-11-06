import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show keccak256;

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
import '../../utils/user_operation_hash.dart';
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
  /// - [nonceKey]: Custom nonce key for parallel transactions (defaults to 0)
  /// - [entryPointAddress]: Override the canonical EntryPoint v0.6 address
  /// - [publicClient]: Client for computing the account address via RPC
  /// - [address]: Pre-computed account address to skip address derivation
  BiconomySmartAccountConfig({
    required this.owner,
    required this.chainId,
    BigInt? index,
    this.customFactoryAddress,
    this.customEcdsaModuleAddress,
    this.nonceKey,
    this.entryPointAddress,
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

  /// Optional custom nonce key.
  final BigInt? nonceKey;

  /// Optional EntryPoint address override.
  final EthereumAddress? entryPointAddress;

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
class BiconomySmartAccount implements SmartAccountV06, EntryPointVersioned {
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
  @override
  EntryPointVersion get entryPointVersion => EntryPointVersion.v06;

  /// The index/salt used for address derivation.
  BigInt get index => _config.index;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address (v0.6).
  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(entryPointVersion);

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Biconomy account.
  ///
  /// The address is computed locally using CREATE2 formula:
  /// `address = keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))[12:]`
  @override
  Future<EthereumAddress> getAddress() async =>
      // Local CREATE2 rather than getSenderAddress, which can fail when the
      // account is already deployed.
      _cachedAddress ??= _config.address ?? _computeAccountAddress();

  EthereumAddress _computeAccountAddress() {
    final initialisationData = AbiEncoder.encodeFunctionData(
      _initSignature,
      [
        BiconomyAddresses.defaultFallbackHandler,
        _ecdsaModuleAddress,
        _ecdsaOwnershipInitData,
      ],
    );

    final salt = _keccak(
      Hex.concat([
        _keccak(initialisationData),
        Hex.fromBigInt(_config.index, byteLength: 32),
      ]),
    );

    final initCodeHash = _keccak(
      Hex.concat([
        _proxyCreationCode,
        AbiEncoder.encodeAddress(BiconomyAddresses.accountV2Logic),
      ]),
    );

    final addressHash = _keccak(
      Hex.concat(['0xff', _factoryAddress.hex, salt, initCodeHash]),
    );
    return EthereumAddress.fromHex(Hex.slice(addressHash, 12));
  }

  /// `initForSmartAccount(owner)`: the ECDSA ownership module setup data.
  String get _ecdsaOwnershipInitData => AbiEncoder.encodeFunctionData(
        _initForSmartAccountSignature,
        [_config.owner.address],
      );

  /// Gets the init code for deploying this Biconomy account.
  @override
  Future<String> getInitCode() async => packUserOperationInitCode(
        factory: _factoryAddress,
        factoryData: _deployCounterFactualAccountData(),
      );

  /// Gets the factory address and data for UserOperation.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async => (
            factory: _factoryAddress,
            factoryData: _deployCounterFactualAccountData(),
          );

  String _deployCounterFactualAccountData() => AbiEncoder.encodeFunctionData(
        _deployCounterFactualAccountSignature,
        [_ecdsaModuleAddress, _ecdsaOwnershipInitData, _config.index],
      );

  /// Encodes a single call as `execute_ncC(address,uint256,bytes)`.
  @override
  String encodeCall(Call call) => AbiEncoder.encodeFunctionData(
        _executeSignature,
        [call.to, call.value, call.data],
      );

  /// Encodes multiple calls using executeBatch_y6U.
  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }
    if (calls.length == 1) {
      return encodeCall(calls.single);
    }
    return AbiEncoder.encodeFunctionData(_executeBatchSignature, [
      [for (final c in calls) c.to],
      [for (final c in calls) c.value],
      [for (final c in calls) c.data],
    ]);
  }

  @override
  List<Call> decodeCalls(String callData) {
    final selector = Hex.slice(callData, 0, 4).toLowerCase();
    if (selector == AbiEncoder.functionSelector(_executeBatchSignature)) {
      final [to as List, value as List, data as List] =
          AbiEncoder.decodeFunctionData(_executeBatchSignature, callData);
      return [
        for (var i = 0; i < to.length; i++)
          Call(
            to: to[i] as EthereumAddress,
            value: value[i] as BigInt,
            data: Hex.fromBytes(data[i] as Uint8List),
          ),
      ];
    }
    final [to, value, data] =
        AbiEncoder.decodeFunctionData(_executeSignature, callData);
    return [
      Call(
        to: to as EthereumAddress,
        value: value as BigInt,
        data: Hex.fromBytes(data as Uint8List),
      ),
    ];
  }

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() => _encodeModuleSignature(_dummyEcdsaSignature);

  /// Signs a UserOperation (v0.6).
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) async {
    final signature = await _config.owner.signPersonalMessage(
      getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        entryPointVersion: entryPointVersion,
        chainId: _config.chainId,
      ),
    );
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
    // hashMessage already applies the EIP-191 prefix; sign that digest raw
    // (matches viem localOwner.signMessage — one prefix only).
    final signature = await _config.owner.signRawHash(hashMessage(message));
    return _encodeModuleSignature(signature);
  }

  /// Signs EIP-712 typed data.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final signature = await _config.owner.signTypedData(typedData);
    return _encodeModuleSignature(signature);
  }

  /// `abi.encode(bytes signature, address moduleAddress)`: Biconomy routes
  /// validation to the module named next to the signature.
  String _encodeModuleSignature(String signature) =>
      AbiEncoder.encodeWithDynamics([
        (false, AbiEncoder.encodeBytes(signature)),
        (true, AbiEncoder.encodeAddress(_ecdsaModuleAddress)),
      ]);
}

const _executeSignature = 'execute_ncC(address,uint256,bytes)';
const _executeBatchSignature = 'executeBatch_y6U(address[],uint256[],bytes[])';
const _deployCounterFactualAccountSignature =
    'deployCounterFactualAccount(address,bytes,uint256)';
const _initForSmartAccountSignature = 'initForSmartAccount(address)';
const _initSignature = 'init(address,address,bytes)';

/// 65-byte ECDSA-shaped dummy signature permissionless.js uses for Biconomy
/// stub signatures (wrapped with the module address).
const _dummyEcdsaSignature =
    '0x81d4b4981670cb18f99f0b4a66446df1bf5b204d24cfcb659bf38ba27a4359b5711649ec2423c5e1247245eba2964679b6a1dbb85c992ae40b9b00c6935b02ff1b';

/// Creation code of the Biconomy account proxy the factory deploys (the
/// implementation address is appended as its constructor argument).
const _proxyCreationCode =
    '0x6080346100aa57601f61012038819003918201601f19168301916001600160401b038311848410176100af578084926020946040528339810103126100aa57516001600160a01b0381168082036100aa5715610065573055604051605a90816100c68239f35b60405162461bcd60e51b815260206004820152601e60248201527f496e76616c696420696d706c656d656e746174696f6e206164647265737300006044820152606490fd5b600080fd5b634e487b7160e01b600052604160045260246000fdfe608060405230546000808092368280378136915af43d82803e156020573d90f35b3d90fdfea2646970667358221220a03b18dce0be0b4c9afe58a9eb85c35205e2cf087da098bbf1d23945bf89496064736f6c63430008110033';

String _keccak(String data) => Hex.fromBytes(keccak256(Hex.decode(data)));

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
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
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
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );
