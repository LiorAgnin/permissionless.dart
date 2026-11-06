import 'dart:convert';

import 'package:web3dart/web3dart.dart' show keccak256;

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
import '../../utils/sort_addresses.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../account_support.dart';
import '../erc7579_calls.dart';
import 'constants.dart';

/// Configuration for creating a Nexus smart account.
class NexusSmartAccountConfig {
  /// Creates a configuration for a Nexus (Biconomy ERC-7579) smart account.
  ///
  /// - [owner]: The account owner who controls the account
  /// - [chainId]: Chain ID for the network
  /// - [version]: Nexus version (defaults to "1.0.0")
  /// - [index]: Salt for deterministic address generation (defaults to 0)
  /// - [attesters]: Optional attesters for multi-sig validation
  /// - [threshold]: Threshold for multi-sig (0 = disabled)
  /// - [nonceKey]: User nonce key (3-byte slot, `key % 16777215`)
  /// - [entryPointAddress]: Override the canonical EntryPoint v0.7 address
  /// - [publicClient]: For RPC-based address computation (recommended)
  /// - [address]: Pre-computed address (alternative to publicClient)
  NexusSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.version = '1.0.0',
    BigInt? index,
    this.customFactoryAddress,
    this.customValidatorAddress,
    this.attesters = const [],
    this.threshold = 0,
    this.nonceKey,
    this.entryPointAddress,
    this.publicClient,
    this.address,
  }) : index = index ?? BigInt.zero;

  /// The owner of this Nexus account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Nexus version (default: "1.0.0").
  final String version;

  /// Salt/index for deterministic address generation.
  final BigInt index;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom K1 validator address.
  final EthereumAddress? customValidatorAddress;

  /// Optional attesters for multi-sig validation.
  final List<EthereumAddress> attesters;

  /// Threshold for multi-sig (0 = no multi-sig).
  final int threshold;

  /// Optional user nonce key (encoded into a 3-byte slot: `key % 16777215`).
  final BigInt? nonceKey;

  /// Optional EntryPoint address override.
  final EthereumAddress? entryPointAddress;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthereumAddress? address;
}

/// A Nexus smart account implementation for ERC-4337 v0.7.
///
/// Nexus is Biconomy's ERC-7579 modular smart account, succeeding
/// the original Biconomy Smart Account. Key features:
/// - ERC-7579 modular architecture
/// - K1 validator for ECDSA signatures
/// - Optional attester-based multi-sig
///
/// Example:
/// ```dart
/// final account = createNexusSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Nexus account: $address');
/// ```
class NexusSmartAccount implements SmartAccount, EntryPointVersioned {
  /// Creates a Nexus smart account from the given configuration.
  ///
  /// Prefer using [createNexusSmartAccount] factory function instead
  /// of calling this constructor directly.
  NexusSmartAccount(this._config)
      : _factoryAddress =
            _config.customFactoryAddress ?? NexusAddresses.k1ValidatorFactory,
        _validatorAddress =
            _config.customValidatorAddress ?? NexusAddresses.k1Validator;

  final NexusSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  final EthereumAddress _validatorAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The EntryPoint version (always v0.7 for Nexus).
  @override
  EntryPointVersion get entryPointVersion => EntryPointVersion.v07;

  /// The index/salt used for address derivation.
  BigInt get index => _config.index;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address (v0.7).
  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(entryPointVersion);

  /// The nonce key for Nexus accounts.
  ///
  /// Nexus uses a special nonce key format that includes the validator address.
  /// Layout: `(key % 16777215)` (3 bytes) ‖ validationMode (1) ‖ validator (20).
  @override
  BigInt get nonceKey {
    // permissionless.js TIMESTAMP_ADJUSTMENT (max 3-byte value).
    const timestampAdjustment = 16777215;
    final defaultedKey =
        (_config.nonceKey ?? BigInt.zero) % BigInt.from(timestampAdjustment);
    const validationMode = '0x00';
    return Hex.toBigInt(
      Hex.concat([
        Hex.fromBigInt(defaultedKey, byteLength: 3),
        validationMode,
        _validatorAddress.hex,
      ]),
    );
  }

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Nexus account.
  @override
  Future<EthereumAddress> getAddress() async =>
      _cachedAddress ??= await resolveCounterfactualAddress(
        accountName: 'Nexus',
        address: _config.address,
        publicClient: _config.publicClient,
        entryPoint: entryPoint,
        initCode: getInitCode,
      );

  /// Gets the init code for deploying this Nexus account.
  @override
  Future<String> getInitCode() => initCodeFromFactory(getFactoryData());

  /// Gets the factory address and data for UserOperation v0.7.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async => (
            factory: _factoryAddress,
            factoryData: AbiEncoder.encodeFunctionData(
              'createAccount(address,uint256,address[],uint8)',
              [
                _config.owner.address,
                _config.index,
                sortAddresses(_config.attesters),
                _config.threshold,
              ],
            ),
          );

  /// Encodes a single call using ERC-7579 execute mode.
  @override
  String encodeCall(Call call) => encode7579Execute(call);

  /// Encodes multiple calls using ERC-7579 execute batch mode.
  @override
  String encodeCalls(List<Call> calls) => encodeErc7579AccountCalls(calls);

  @override
  List<Call> decodeCalls(String callData) => decode7579Calls(callData).calls;

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() {
    // permissionless.js Nexus dummy: offset ‖ validator ‖ 65-byte signature.
    final validator = Hex.strip0x(_validatorAddress.hex);
    return '0x0000000000000000000000000000000000000000000000000000000000000040'
        '000000000000000000000000$validator'
        '0000000000000000000000000000000000000000000000000000000000000041'
        '81d4b4981670cb18f99f0b4a66446df1bf5b204d24cfcb659bf38ba27a4359b5'
        '711649ec2423c5e1247245eba2964679b6a1dbb85c992ae40b9b00c6935b02ff'
        '1b00000000000000000000000000000000000000000000000000000000000000';
  }

  /// Signs a UserOperation.
  ///
  /// The signing flow for Nexus K1 validator:
  /// 1. Compute userOpHash
  /// 2. Sign with EIP-191 personal message
  /// 3. Return the bare 65-byte ECDSA signature
  ///
  /// Nexus selects the validator via the **nonce key** and forwards
  /// `userOp.signature` untouched to K1Validator's ECDSA recover — so the
  /// signature must be the bare 65-byte personal signature (no validator
  /// address prefix). The validator prefix is only used for ERC-1271
  /// [signMessage] / [signTypedData] packing.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) =>
      _config.owner.signPersonalMessage(
        getUserOperationHash(
          userOperation: userOp,
          entryPointAddress: entryPoint,
          entryPointVersion: entryPointVersion,
          chainId: chainId,
        ),
      );

  /// Signs a personal message (EIP-191) with Nexus wrapper.
  @override
  Future<String> signMessage(String message) =>
      _signWrapped(hashMessage(message));

  /// Signs EIP-712 typed data with Nexus wrapper.
  @override
  Future<String> signTypedData(TypedData typedData) =>
      _signWrapped(hashTypedData(typedData));

  /// ERC-1271 signature: `validator ‖ personal_sign(wrap(hash))`.
  Future<String> _signWrapped(String hash) async {
    final signature = await _config.owner.signPersonalMessage(
      await _wrapMessageHash(hash),
    );
    return Hex.concat([_validatorAddress.hex, signature]);
  }

  /// Wraps a message hash with Nexus-specific EIP-712 domain.
  ///
  /// Mirrors permissionless.js `wrapMessageHash`: the struct hash is
  /// `keccak256(PERSONAL_SIGN_TYPEHASH ‖ messageHash)`, i.e. EIP-712
  /// `PersonalSign(bytes prefixed)` with [messageHash] standing in for
  /// `keccak256(prefixed)`. hashTypedData would need the prefixed preimage,
  /// which callers only have as a hash.
  Future<String> _wrapMessageHash(String messageHash) async {
    final domainSeparator = computeDomainSeparator(
      TypedDataDomain(
        name: 'Nexus',
        version: _config.version,
        chainId: _config.chainId,
        verifyingContract: await getAddress(),
      ),
    );
    final structHash = _keccak(
      Hex.concat([
        _keccak(Hex.fromBytes(utf8.encode('PersonalSign(bytes prefixed)'))),
        messageHash,
      ]),
    );
    return _keccak(Hex.concat(['0x1901', domainSeparator, structHash]));
  }
}

String _keccak(String hex) => Hex.fromBytes(keccak256(Hex.decode(hex)));

/// Creates a Nexus smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createNexusSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Nexus account: $address');
/// ```
NexusSmartAccount createNexusSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  String version = '1.0.0',
  BigInt? index,
  EthereumAddress? customFactoryAddress,
  EthereumAddress? customValidatorAddress,
  List<EthereumAddress> attesters = const [],
  int threshold = 0,
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    NexusSmartAccount(
      NexusSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        version: version,
        index: index,
        customFactoryAddress: customFactoryAddress,
        customValidatorAddress: customValidatorAddress,
        attesters: attesters,
        threshold: threshold,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );
