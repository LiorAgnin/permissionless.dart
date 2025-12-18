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
import '../../utils/erc7579.dart';
import '../../utils/message_hash.dart';
import 'constants.dart';

/// Owner abstraction for EIP-7702 Kernel accounts.
///
/// This owner can sign messages, typed data, and EIP-7702 authorizations.
abstract class Eip7702KernelOwner {
  /// The Ethereum address of this owner (the EOA).
  EthereumAddress get address;

  /// Signs a raw message hash and returns the signature.
  Future<String> signHash(String messageHash);

  /// Signs EIP-712 typed data and returns the signature.
  Future<String> signTypedData(TypedData typedData);

  /// Creates an EIP-7702 authorization for this owner.
  Future<Eip7702Authorization> createAuthorization({
    required BigInt chainId,
    required EthereumAddress contractAddress,
    required BigInt nonce,
  });
}

/// A local private key owner for EIP-7702 Kernel accounts.
class PrivateKeyEip7702KernelOwner implements Eip7702KernelOwner {
  PrivateKeyEip7702KernelOwner(String privateKeyHex)
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

    // Sign directly without EIP-191 prefix (raw hash signing)
    final sig = crypto.sign(Uint8List.fromList(hash), _privateKey.privateKey);

    // Encode as r (32 bytes) + s (32 bytes) + v (1 byte)
    final r = Hex.fromBigInt(sig.r, byteLength: 32);
    final s = Hex.fromBigInt(sig.s, byteLength: 32);
    var v = sig.v;
    if (v < 27) {
      v += 27;
    }

    return Hex.concat([r, s, Hex.fromBigInt(BigInt.from(v), byteLength: 1)]);
  }

  @override
  Future<String> signTypedData(TypedData typedData) async {
    final hash = hashTypedData(typedData);
    final hashBytes = Hex.decode(hash);

    // Sign the typed data hash directly using raw sign function
    final sig =
        crypto.sign(Uint8List.fromList(hashBytes), _privateKey.privateKey);

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

/// Configuration for creating an EIP-7702 Kernel smart account.
class Eip7702KernelSmartAccountConfig {
  Eip7702KernelSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.version = KernelVersion.v0_3_3,
    this.publicClient,
    EthereumAddress? accountLogicAddress,
    EthereumAddress? ecdsaValidatorAddress,
  })  : accountLogicAddress = accountLogicAddress ??
            KernelVersionAddresses.getAddresses(version)!.accountImplementation,
        ecdsaValidatorAddress = ecdsaValidatorAddress ??
            KernelVersionAddresses.getAddresses(version)!.ecdsaValidator! {
    if (!version.supportsEip7702) {
      throw ArgumentError(
        'Kernel version ${version.value} does not support EIP-7702. '
        'Use v0.3.3 or later.',
      );
    }
  }

  /// The owner of this EIP-7702 account (the EOA).
  final Eip7702KernelOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Kernel version (must support EIP-7702).
  final KernelVersion version;

  /// Public client for checking deployment status.
  ///
  /// Required for EIP-1271 signature validation to check if the account
  /// has been delegated (deployed) before signing messages/typed data.
  final PublicClient? publicClient;

  /// The Kernel account logic contract address for delegation.
  final EthereumAddress accountLogicAddress;

  /// The ECDSA validator address.
  final EthereumAddress ecdsaValidatorAddress;
}

/// An EIP-7702 Kernel smart account implementation.
///
/// This account uses EIP-7702 to delegate code execution from an EOA to
/// a Kernel account implementation. Key characteristics:
///
/// - **Account address = EOA address**: No separate smart account deployment
/// - **No factory needed**: The authorization delegates code on-demand
/// - **EntryPoint v0.7**: Uses standard v0.7 UserOperation format
/// - **ERC-7579 compliant**: Uses modular account encoding
/// - **Kernel EIP-712 domain**: Message signing uses Kernel-specific domain
///
/// Example:
/// ```dart
/// final account = createEip7702KernelSmartAccount(
///   owner: PrivateKeyEip7702KernelOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // The account address is the same as the owner's EOA address
/// final address = await account.getAddress();
/// print('EIP-7702 Kernel account: $address');
///
/// // Get authorization for submitting to bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
class Eip7702KernelSmartAccount implements Eip7702SmartAccount {
  Eip7702KernelSmartAccount(this._config);

  final Eip7702KernelSmartAccountConfig _config;

  /// The owner of this account.
  Eip7702KernelOwner get owner => _config.owner;

  /// The Kernel account logic contract address.
  @override
  EthereumAddress get accountLogicAddress => _config.accountLogicAddress;

  /// Whether this account uses EIP-7702 code delegation.
  @override
  bool get isEip7702 => true;

  /// The EntryPoint version (v0.7 for Kernel EIP-7702).
  EntryPointVersion get entryPointVersion => EntryPointVersion.v07;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address for this account.
  @override
  EthereumAddress get entryPoint => EntryPointAddresses.v07;

  /// The nonce key for this account.
  ///
  /// For Kernel v3, the nonce key encodes: mode (1) + type (1) + validatorAddress (20) + salt (2).
  /// Uses ROOT type (0x00) with the ECDSA validator address.
  @override
  BigInt get nonceKey {
    // Kernel v3 nonce key: mode (1) + type (1) + validatorAddress (20) + salt (2) = 24 bytes
    final validatorBytes = Hex.decode(_config.ecdsaValidatorAddress.hex);

    final bytes = Uint8List(24);
    // Mode: default (0x00)
    bytes[0] = KernelValidatorMode.sudo;
    // Type: ROOT (0x00)
    bytes[1] = KernelValidatorType.root;
    // Validator address (20 bytes)
    for (var i = 0; i < 20; i++) {
      bytes[2 + i] = validatorBytes[i];
    }
    // Salt: 0x0000 (2 bytes) - already zero

    return Hex.toBigInt(Hex.fromBytes(bytes));
  }

  /// Gets the address of this EIP-7702 account.
  ///
  /// For EIP-7702 accounts, this is the same as the owner's EOA address.
  @override
  Future<EthereumAddress> getAddress() async => _config.owner.address;

  /// Gets the init code for deploying this account.
  ///
  /// For EIP-7702 accounts, this returns '0x' as no deployment is needed.
  @override
  Future<String> getInitCode() async => '0x';

  /// Gets the factory address and data for UserOperation v0.7.
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
  @override
  Future<Eip7702Authorization> getAuthorization({required BigInt nonce}) =>
      _config.owner.createAuthorization(
        chainId: _config.chainId,
        contractAddress: _config.accountLogicAddress,
        nonce: nonce,
      );

  /// Encodes a single call for execution using ERC-7579 format.
  @override
  String encodeCall(Call call) => encode7579Execute(call);

  /// Encodes multiple calls using ERC-7579 batch format.
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
  ///
  /// For Kernel v3 (including EIP-7702), the UserOperation signature is just
  /// the raw ECDSA signature without any validator identifier prefix.
  /// The validator identifier is only used for message/typedData signing (EIP-1271).
  @override
  String getStubSignature() => kernelDummyEcdsaSignature;

  /// Gets the EIP-7702 validator identifier.
  ///
  /// For EIP-7702, the identifier is just the type byte (0x00) with no address.
  /// Per permissionless.js: getEcdsaRootIdentifierForKernelV3(validatorAddress, eip7702)
  /// When eip7702=true: concatHex([VALIDATOR_TYPE.EIP7702, "0x"])
  String _getEip7702ValidatorIdentifier() =>
      Hex.fromBigInt(BigInt.from(KernelValidatorType.eip7702), byteLength: 1);

  /// Signs a UserOperation using v0.7 hash format.
  ///
  /// For Kernel v3 (including EIP-7702), the UserOperation is signed using
  /// EIP-191 personal_sign format: the UserOp hash is wrapped with
  /// "\x19Ethereum Signed Message:\n32" prefix before signing.
  ///
  /// This matches permissionless.js which uses owner.signMessage({ message: { raw: hash } }).
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = _computeUserOpHash(userOp);

    // Apply EIP-191 prefix: "\x19Ethereum Signed Message:\n32" + hashBytes
    // This matches viem's signMessage({ message: { raw: hash } }) behavior
    final prefixedHash = _hashMessageRaw(userOpHash);

    return _config.owner.signHash(prefixedHash);
  }

  /// Applies EIP-191 personal message prefix to raw bytes (32-byte hash).
  ///
  /// Format: keccak256("\x19Ethereum Signed Message:\n32" + hashBytes)
  ///
  /// This matches viem's `signMessage({ message: { raw: hash } })` which
  /// treats the raw bytes as the message content.
  String _hashMessageRaw(String hashHex) {
    final hashBytes = Hex.decode(hashHex);
    const prefix = '\x19Ethereum Signed Message:\n32';
    final prefixBytes = Uint8List.fromList(prefix.codeUnits);

    final combined = Uint8List(prefixBytes.length + hashBytes.length)
      ..setRange(0, prefixBytes.length, prefixBytes)
      ..setRange(
        prefixBytes.length,
        prefixBytes.length + hashBytes.length,
        hashBytes,
      );

    return Hex.fromBytes(crypto.keccak256(combined));
  }

  /// Computes the UserOperation hash for v0.7.
  String _computeUserOpHash(UserOperationV07 userOp) {
    final packedUserOp = _packUserOp(userOp);
    final userOpHashInner = crypto.keccak256(Hex.decode(packedUserOp));

    final finalPreImage = Hex.concat([
      Hex.fromBytes(userOpHashInner),
      AbiEncoder.encodeAddress(entryPoint),
      AbiEncoder.encodeUint256(chainId),
    ]);

    return Hex.fromBytes(crypto.keccak256(Hex.decode(finalPreImage)));
  }

  /// Packs a UserOperation for hashing (v0.7 format).
  String _packUserOp(UserOperationV07 userOp) {
    // Pack initCode
    final initCode = userOp.factory != null
        ? Hex.concat([
            userOp.factory!.hex,
            Hex.strip0x(userOp.factoryData ?? '0x'),
          ])
        : '0x';
    final initCodeHash = crypto.keccak256(Hex.decode(initCode));

    // Pack callData
    final callDataHash = crypto.keccak256(Hex.decode(userOp.callData));

    // Pack accountGasLimits (v0.7 packing)
    final verificationGasLimitHex =
        Hex.fromBigInt(userOp.verificationGasLimit, byteLength: 16);
    final callGasLimitHex = Hex.fromBigInt(userOp.callGasLimit, byteLength: 16);
    final accountGasLimits =
        Hex.concat([verificationGasLimitHex, callGasLimitHex]);

    // Pack gasFees
    final maxPriorityFeeHex =
        Hex.fromBigInt(userOp.maxPriorityFeePerGas, byteLength: 16);
    final maxFeeHex = Hex.fromBigInt(userOp.maxFeePerGas, byteLength: 16);
    final gasFees = Hex.concat([maxPriorityFeeHex, maxFeeHex]);

    // Pack paymasterAndData
    final paymasterAndData = userOp.paymaster != null
        ? Hex.concat([
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
          ])
        : '0x';
    final paymasterAndDataHash = crypto.keccak256(Hex.decode(paymasterAndData));

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

  /// Signs a personal message using Kernel's EIP-712 wrapper.
  ///
  /// Kernel wraps messages in its own EIP-712 domain for 1271 compliance.
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signMessage(String message) async {
    await _ensureDeployedForEip1271();
    final messageHash = hashMessage(message);
    return _signWithKernelWrapper(messageHash);
  }

  /// Signs EIP-712 typed data using Kernel's EIP-712 wrapper.
  ///
  /// Kernel wraps the typed data hash in its own EIP-712 domain.
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    await _ensureDeployedForEip1271();
    final hash = hashTypedData(typedData);
    return _signWithKernelWrapper(hash);
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
        'Kernel with EIP-7702 is not EIP-1271 compliant before delegation. '
        'Submit a UserOperation with the EIP-7702 authorization first.',
      );
    }
  }

  /// Signs a hash using Kernel's EIP-712 wrapper domain.
  ///
  /// This is how Kernel achieves EIP-1271 compliance for message signing.
  Future<String> _signWithKernelWrapper(String messageHash) async {
    // Create Kernel-specific typed data for wrapping the message
    final kernelTypedData = TypedData(
      domain: TypedDataDomain(
        name: 'Kernel',
        version: _config.version.value,
        chainId: _config.chainId,
        verifyingContract: _config.owner.address,
      ),
      types: {
        'EIP712Domain': [
          const TypedDataField(name: 'name', type: 'string'),
          const TypedDataField(name: 'version', type: 'string'),
          const TypedDataField(name: 'chainId', type: 'uint256'),
          const TypedDataField(name: 'verifyingContract', type: 'address'),
        ],
        'Kernel': [
          const TypedDataField(name: 'hash', type: 'bytes32'),
        ],
      },
      primaryType: 'Kernel',
      message: {
        'hash': messageHash,
      },
    );

    final signature = await _config.owner.signTypedData(kernelTypedData);

    // Prepend validator identifier
    final validatorId = _getEip7702ValidatorIdentifier();
    return Hex.concat([validatorId, Hex.strip0x(signature)]);
  }
}

/// Creates an EIP-7702 Kernel smart account.
///
/// This creates an account that uses EIP-7702 code delegation, enabling
/// an EOA to function as a Kernel smart account without deployment.
///
/// **Requirements:**
/// - EntryPoint v0.7 (automatically used)
/// - Bundler with EIP-7702 support
/// - Chain with EIP-7702 enabled
///
/// Example:
/// ```dart
/// final account = createEip7702KernelSmartAccount(
///   owner: PrivateKeyEip7702KernelOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // Account address = owner's EOA address
/// final address = await account.getAddress();
///
/// // Create authorization for bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
Eip7702KernelSmartAccount createEip7702KernelSmartAccount({
  required Eip7702KernelOwner owner,
  required BigInt chainId,
  KernelVersion version = KernelVersion.v0_3_3,
  PublicClient? publicClient,
  EthereumAddress? accountLogicAddress,
  EthereumAddress? ecdsaValidatorAddress,
}) =>
    Eip7702KernelSmartAccount(
      Eip7702KernelSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        version: version,
        publicClient: publicClient,
        accountLogicAddress: accountLogicAddress,
        ecdsaValidatorAddress: ecdsaValidatorAddress,
      ),
    );
