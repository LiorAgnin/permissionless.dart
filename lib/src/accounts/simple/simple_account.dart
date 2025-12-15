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

/// Configuration for creating a Simple smart account.
class SimpleSmartAccountConfig {
  SimpleSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.entryPointVersion = EntryPointVersion.v07,
    BigInt? salt,
    this.customFactoryAddress,
    this.publicClient,
    this.address,
  }) : salt = salt ?? BigInt.zero;

  /// The owner of this Simple account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// The EntryPoint version to use.
  final EntryPointVersion entryPointVersion;

  /// Salt for deterministic address generation.
  final BigInt salt;

  /// Optional custom factory address.
  final EthAddress? customFactoryAddress;

  /// Public client for computing the account address via RPC.
  ///
  /// If provided, the account address will be computed using
  /// [PublicClient.getSenderAddress] which simulates account deployment.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  ///
  /// If provided, this address will be used instead of RPC computation.
  /// Use when you already know the account address.
  final EthAddress? address;
}

/// A Simple smart account implementation for ERC-4337.
///
/// This is the minimal reference implementation from eth-infinitism.
/// Unlike Safe accounts, Simple accounts have:
/// - Single owner (no multi-sig)
/// - Direct signature validation (no EIP-712 SafeOp)
/// - Built-in execute/executeBatch (no modules)
///
/// Example:
/// ```dart
/// final account = createSimpleSmartAccount(
///   owner: PrivateKeySimpleAccountOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Simple account: $address');
/// ```
class SimpleSmartAccount implements SmartAccount {
  SimpleSmartAccount(this._config)
      : _factoryAddress = _config.customFactoryAddress ??
            SimpleAccountFactoryAddresses.fromVersion(
              _config.entryPointVersion,
            );

  final SimpleSmartAccountConfig _config;
  final EthAddress _factoryAddress;
  EthAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The EntryPoint version being used.
  EntryPointVersion get entryPointVersion => _config.entryPointVersion;

  /// The salt used for address derivation.
  BigInt get salt => _config.salt;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address for this account.
  @override
  EthAddress get entryPoint =>
      EntryPointAddresses.fromVersion(_config.entryPointVersion);

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => BigInt.zero;

  /// Gets the deterministic address of this Simple account.
  ///
  /// The address is computed via RPC using [PublicClient.getSenderAddress].
  @override
  Future<EthAddress> getAddress() async {
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
      'Simple account address cannot be computed without a client. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }

  // /// Computes the combined salt for CREATE2.
  // String _computeSalt() {
  //   // salt = keccak256(abi.encodePacked(owner, saltNonce))
  //   final encoded = Hex.concat([
  //     _config.owner.address.hex,
  //     Hex.fromBigInt(_config.salt, byteLength: 32),
  //   ]);
  //   return Hex.fromBytes(keccak256(Hex.decode(encoded)));
  // }

  // /// Computes the init code hash for the proxy.
  // ///
  // /// SimpleAccountFactory deploys ERC-1967 proxies.
  // /// The init code is: creation code + abi.encode(implementation, "")
  // String _computeProxyInitCodeHash() {
  //   // The SimpleAccountFactory uses a standard ERC-1967 proxy
  //   // This is the init code hash for the proxy deployed by the factory
  //   // Note: This is a simplified version - in production you'd want to
  //   // verify this matches the actual factory deployment

  //   // Standard ERC-1967 proxy creation code used by SimpleAccountFactory
  //   const proxyCreationCode =
  //       '0x60806040526040516101c63803806101c68339810160408190526100229161012a565b61002e82826000610035565b5050610209565b61003e836100ad565b6040516001600160a01b038416907f1cf3b03a6cf19fa2baba4df148e9dcabedea7f8a5c07840e207e5c089be95d3e90600090a260008251118061007f5750805b156100a8576100a6836001600160a01b0316630a3cb66386604051602001610100565b505b505050565b6100b6816100ec565b6040516001600160a01b038216907fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b90600090a250565b6001600160a01b0381163b6100fd57600080fd5b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc55565b600060208284031215610132578081fd5b81516001600160a01b0381168114610148578182fd5b9392505050565b60006020828403121561015f578081fd5b5051919050565b61013c806101746000396000f3fe';

  //   // For a production implementation, compute based on actual factory bytecode
  //   // For now, use a deterministic hash based on owner
  //   final initData = Hex.concat([
  //     proxyCreationCode,
  //     AbiEncoder.encodeAddress(
  //         entryPoint,), // implementation points to entrypoint
  //   ]);

  //   return Hex.fromBytes(keccak256(Hex.decode(initData)));
  // }

  /// Gets the init code for deploying this Simple account.
  ///
  /// This is used in the UserOperation when the account doesn't exist yet.
  @override
  Future<String> getInitCode() async {
    final factoryData = _encodeCreateAccount();

    // InitCode = factory address (20 bytes) + factory calldata
    return Hex.concat([
      _factoryAddress.hex,
      Hex.strip0x(factoryData),
    ]);
  }

  /// Gets the factory address and data for UserOperation v0.7.
  @override
  Future<({EthAddress factory, String factoryData})?> getFactoryData() async {
    final data = _encodeCreateAccount();
    return (factory: _factoryAddress, factoryData: data);
  }

  /// Encodes the createAccount factory call.
  // createAccount(address owner, uint256 salt)
  String _encodeCreateAccount() => Hex.concat([
        SimpleAccountSelectors.createAccount,
        AbiEncoder.encodeAddress(_config.owner.address),
        AbiEncoder.encodeUint256(_config.salt),
      ]);

  /// Encodes a single call for execution.
  ///
  /// Uses SimpleAccount.execute(address, uint256, bytes).
  @override
  String encodeCall(Call call) =>
      _encodeExecute(call.to, call.value, call.data);

  /// Encodes multiple calls using executeBatch.
  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }

    if (calls.length == 1) {
      return encodeCall(calls.first);
    }

    // executeBatch(address[], uint256[], bytes[])
    return _encodeExecuteBatch(calls);
  }

  /// Encodes a single execute call.
  String _encodeExecute(EthAddress to, BigInt value, String data) {
    // execute(address dest, uint256 value, bytes calldata func)
    // Layout: selector + dest + value + offset + length + data
    const dataOffset = 3 * 32; // 3 static parameters before dynamic data
    final dataEncoded = AbiEncoder.encodeBytes(data);

    return Hex.concat([
      SimpleAccountSelectors.execute,
      AbiEncoder.encodeAddress(to),
      AbiEncoder.encodeUint256(value),
      AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
      Hex.strip0x(dataEncoded),
    ]);
  }

  /// Encodes a batch execute call.
  String _encodeExecuteBatch(List<Call> calls) {
    // executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func)
    // This is a complex ABI encoding with 3 dynamic arrays

    final destArray = calls.map((c) => c.to).toList();
    final valuesArray = calls.map((c) => c.value).toList();
    final dataArray = calls.map((c) => c.data).toList();

    // Offsets for each dynamic array (3 arrays = 3 * 32 bytes for offsets)
    const destOffset = 3 * 32;
    final destEncoded = _encodeAddressArray(destArray);
    final valuesOffset = destOffset + Hex.byteLength(destEncoded);
    final valuesEncoded = _encodeUint256Array(valuesArray);
    final dataArrayOffset = valuesOffset + Hex.byteLength(valuesEncoded);
    final dataArrayEncoded = _encodeBytesArray(dataArray);

    return Hex.concat([
      SimpleAccountSelectors.executeBatch,
      AbiEncoder.encodeUint256(BigInt.from(destOffset)),
      AbiEncoder.encodeUint256(BigInt.from(valuesOffset)),
      AbiEncoder.encodeUint256(BigInt.from(dataArrayOffset)),
      Hex.strip0x(destEncoded),
      Hex.strip0x(valuesEncoded),
      Hex.strip0x(dataArrayEncoded),
    ]);
  }

  /// Encodes an array of addresses.
  String _encodeAddressArray(List<EthAddress> addresses) => Hex.concat([
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
    // bytes[] encoding: length + offsets + data
    final length = AbiEncoder.encodeUint256(BigInt.from(dataItems.length));

    // Calculate offsets for each bytes element
    // First offset starts after the offsets array (length * 32 bytes)
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
  ///
  /// Returns a 65-byte dummy signature that can pass basic validation.
  /// This signature format is compatible with ERC-4337 bundler simulation.
  @override
  String getStubSignature() =>
      // Stub signature compatible with Simple Account validation
      // This format passes simulation without requiring actual signature verification
      '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

  /// Signs a UserOperation.
  ///
  /// For Simple accounts, this signs the userOpHash with personal message prefix.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = _computeUserOpHash(userOp);
    return _config.owner.signPersonalMessage(userOpHash);
  }

  /// Signs a personal message (EIP-191).
  ///
  /// Returns the raw ECDSA signature.
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    return _config.owner.signPersonalMessage(messageHash);
  }

  /// Signs EIP-712 typed data.
  ///
  /// Returns the raw ECDSA signature.
  @override
  Future<String> signTypedData(TypedData typedData) async =>
      _config.owner.signTypedData(typedData);

  /// Computes the userOpHash for signing.
  ///
  /// hash = keccak256(packUserOp(userOp), entryPoint, chainId)
  String _computeUserOpHash(UserOperationV07 userOp) {
    final packed = _packUserOpForHash(userOp);
    final packedHash = keccak256(Hex.decode(packed));

    // Final hash includes entryPoint and chainId
    final hashInput = Hex.concat([
      Hex.fromBytes(packedHash),
      AbiEncoder.encodeAddress(entryPoint),
      AbiEncoder.encodeUint256(_config.chainId),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(hashInput)));
  }

  /// Packs a UserOperation for hashing.
  String _packUserOpForHash(UserOperationV07 userOp) {
    // Pack initCode
    var initCode = '0x';
    if (userOp.factory != null) {
      initCode = Hex.concat([
        userOp.factory!.hex,
        Hex.strip0x(userOp.factoryData ?? '0x'),
      ]);
    }
    final initCodeHash = keccak256(Hex.decode(initCode));

    // Pack callData
    final callDataHash = keccak256(Hex.decode(userOp.callData));

    // Pack accountGasLimits (verificationGasLimit || callGasLimit)
    final accountGasLimits = Hex.concat([
      Hex.fromBigInt(userOp.verificationGasLimit, byteLength: 16),
      Hex.fromBigInt(userOp.callGasLimit, byteLength: 16),
    ]);

    // Pack gasFees (maxPriorityFeePerGas || maxFeePerGas)
    final gasFees = Hex.concat([
      Hex.fromBigInt(userOp.maxPriorityFeePerGas, byteLength: 16),
      Hex.fromBigInt(userOp.maxFeePerGas, byteLength: 16),
    ]);

    // Pack paymasterAndData
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

    // Pack all together
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

/// Creates a Simple smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createSimpleSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Simple account: $address');
/// ```
SimpleSmartAccount createSimpleSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  BigInt? salt,
  EthAddress? customFactoryAddress,
  PublicClient? publicClient,
  EthAddress? address,
}) =>
    SimpleSmartAccount(
      SimpleSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        entryPointVersion: entryPointVersion,
        salt: salt,
        customFactoryAddress: customFactoryAddress,
        publicClient: publicClient,
        address: address,
      ),
    );
