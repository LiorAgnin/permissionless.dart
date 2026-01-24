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
class NexusSmartAccount implements SmartAccount {
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
  EntryPointVersion get entryPointVersion => EntryPointVersion.v07;

  /// The index/salt used for address derivation.
  BigInt get index => _config.index;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address (v0.7).
  @override
  EthereumAddress get entryPoint => EntryPointAddresses.v07;

  /// The nonce key for Nexus accounts.
  ///
  /// Nexus uses a special nonce key format that includes the validator address.
  @override
  BigInt get nonceKey {
    // Nexus nonce key: (key % TIMESTAMP_ADJUSTMENT) || validationMode || validator
    // TIMESTAMP_ADJUSTMENT = 16777215 (max value for 3 bytes)
    // validationMode = 0x00 for regular validation
    const timestampAdjustment = 16777215;
    final defaultedKey = BigInt.zero % BigInt.from(timestampAdjustment);

    // Pack: key (3 bytes) || validationMode (1 byte) || validator (20 bytes)
    final keyHex = Hex.fromBigInt(defaultedKey, byteLength: 3);
    const validationMode = '0x00';
    final validatorHex = Hex.strip0x(_validatorAddress.hex);

    final packed = Hex.concat([keyHex, validationMode, validatorHex]);
    return Hex.toBigInt(packed);
  }

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Nexus account.
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
      'Nexus account address cannot be computed without a client. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }

  /// Gets the init code for deploying this Nexus account.
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
    // Sort attesters by address
    final sortedAttesters = List<EthereumAddress>.from(_config.attesters)
      ..sort((a, b) => a.hex.toLowerCase().compareTo(b.hex.toLowerCase()));

    // createAccount(address eoaOwner, uint256 index, address[] attesters, uint8 threshold)
    // This is a complex ABI encoding with a dynamic array

    // Calculate offsets
    const attestersOffset = 4 * 32; // 4 static params before dynamic array
    final attestersEncoded = _encodeAddressArray(sortedAttesters);

    return Hex.concat([
      NexusSelectors.createAccount,
      AbiEncoder.encodeAddress(_config.owner.address),
      AbiEncoder.encodeUint256(_config.index),
      AbiEncoder.encodeUint256(BigInt.from(attestersOffset)),
      AbiEncoder.encodeUint256(BigInt.from(_config.threshold)),
      Hex.strip0x(attestersEncoded),
    ]);
  }

  /// Encodes an array of addresses.
  String _encodeAddressArray(List<EthereumAddress> addresses) => Hex.concat([
        AbiEncoder.encodeUint256(BigInt.from(addresses.length)),
        ...addresses.map((a) => Hex.strip0x(AbiEncoder.encodeAddress(a))),
      ]);

  /// Encodes a single call using ERC-7579 execute mode.
  @override
  String encodeCall(Call call) => encode7579Execute(call);

  /// Encodes multiple calls using ERC-7579 execute batch mode.
  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }
    if (calls.length == 1) {
      return encodeCall(calls.first);
    }
    return encode7579ExecuteBatch(calls);
  }

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() {
    // Nexus stub signature format: offset + validator address + signature
    final dynamicPart = Hex.strip0x(_validatorAddress.hex).padRight(40, '0');
    return '0x0000000000000000000000000000000000000000000000000000000000000040'
        '000000000000000000000000$dynamicPart'
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
  /// 3. Pack as: validatorAddress (20 bytes) + signature (65 bytes)
  ///
  /// Note: Nexus expects the signature to be packed with validator address
  /// as the first 20 bytes, followed by the validator-specific signature.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = _computeUserOpHash(userOp);

    // K1 validator uses EIP-191 personal sign of userOpHash
    final signature = await _config.owner.signPersonalMessage(userOpHash);

    // Pack: validator address + signature (85 bytes total)
    return Hex.concat([
      _validatorAddress.hex,
      Hex.strip0x(signature),
    ]);
  }

  /// Signs a personal message (EIP-191) with Nexus wrapper.
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    final wrappedHash = await _wrapMessageHash(messageHash);
    final signature = await _config.owner.signPersonalMessage(wrappedHash);

    // Return packed: validator address + signature
    return Hex.concat([
      _validatorAddress.hex,
      Hex.strip0x(signature),
    ]);
  }

  /// Signs EIP-712 typed data with Nexus wrapper.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final hash = hashTypedData(typedData);
    final wrappedHash = await _wrapMessageHash(hash);
    final signature = await _config.owner.signPersonalMessage(wrappedHash);

    // Return packed: validator address + signature
    return Hex.concat([
      _validatorAddress.hex,
      Hex.strip0x(signature),
    ]);
  }

  /// Wraps a message hash with Nexus-specific EIP-712 domain.
  Future<String> _wrapMessageHash(String messageHash) async {
    final accountAddress = await getAddress();

    // Domain separator for Nexus
    final domain = TypedDataDomain(
      name: 'Nexus',
      version: _config.version,
      chainId: _config.chainId,
      verifyingContract: accountAddress,
    );

    final domainSep = computeDomainSeparator(domain);

    // PersonalSign struct hash
    // keccak256("PersonalSign(bytes prefixed)")
    final typeHash = keccak256(
      Uint8List.fromList('PersonalSign(bytes prefixed)'.codeUnits),
    );

    final structHash = keccak256(
      Hex.decode(
        Hex.concat(
          [
            Hex.fromBytes(typeHash),
            messageHash,
          ],
        ),
      ),
    );

    // Final hash: keccak256(0x1901 + domainSeparator + structHash)
    return Hex.fromBytes(
      keccak256(
        Hex.decode(
          Hex.concat(
            [
              '0x1901',
              Hex.strip0x(domainSep),
              Hex.fromBytes(structHash),
            ],
          ),
        ),
      ),
    );
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
        publicClient: publicClient,
        address: address,
      ),
    );
