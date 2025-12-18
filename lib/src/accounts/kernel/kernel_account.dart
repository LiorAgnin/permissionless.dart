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

/// Configuration for creating a Kernel smart account.
class KernelSmartAccountConfig {
  KernelSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.version = KernelVersion.v0_3_1,
    BigInt? index,
    this.customAddresses,
    this.publicClient,
    this.address,
  }) : index = index ?? BigInt.zero {
    // Validate version-specific requirements
    final addresses =
        customAddresses ?? KernelVersionAddresses.getAddresses(version);
    if (addresses == null) {
      throw ArgumentError(
        'No addresses found for Kernel version ${version.value}',
      );
    }
    if (version.hasExternalValidator && addresses.ecdsaValidator == null) {
      throw ArgumentError(
        'ECDSA validator address required for Kernel ${version.value}',
      );
    }
  }

  /// The account owner.
  final AccountOwner owner;

  /// Chain ID for the network.
  final BigInt chainId;

  /// Kernel version to use.
  final KernelVersion version;

  /// Index/salt for address derivation.
  final BigInt index;

  /// Custom contract addresses (optional).
  final KernelAddresses? customAddresses;

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

/// Kernel smart account implementation.
///
/// Supports both v0.2.x (EntryPoint v0.6) and v0.3.x (EntryPoint v0.7).
class KernelSmartAccount implements SmartAccount {
  KernelSmartAccount(this._config)
      : _addresses = _config.customAddresses ??
            KernelVersionAddresses.getAddresses(_config.version)!;

  final KernelSmartAccountConfig _config;
  final KernelAddresses _addresses;
  EthereumAddress? _cachedAddress;

  /// Returns the entry point version for this account.
  EntryPointVersion get entryPointVersion =>
      _config.version == KernelVersion.v0_2_4
          ? EntryPointVersion.v06
          : EntryPointVersion.v07;

  @override
  BigInt get chainId => _config.chainId;

  @override
  EthereumAddress get entryPoint => entryPointVersion == EntryPointVersion.v06
      ? EntryPointAddresses.v06
      : EntryPointAddresses.v07;

  @override
  BigInt get nonceKey {
    if (_config.version == KernelVersion.v0_2_4) {
      return BigInt.zero;
    }

    // v0.3.x: 24-byte encoding
    // mode (1) + type (1) + validator (20) + salt (2)
    final validator = _addresses.ecdsaValidator!;
    final bytes = Uint8List(24);

    // Mode: sudo (0x00)
    bytes[0] = KernelValidatorMode.sudo;
    // Type: root (0x00)
    bytes[1] = KernelValidatorType.root;
    // Validator address (20 bytes)
    bytes.setRange(2, 22, validator.bytes);
    // Nonce salt (2 bytes) - defaults to 0

    return Hex.toBigInt(Hex.fromBytes(bytes));
  }

  @override
  Future<EthereumAddress> getAddress() async {
    if (_cachedAddress != null) return _cachedAddress!;

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
      'Kernel account address cannot be computed without a client. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }

  // Future<EthereumAddress> _computeAddressV2() async {
  //   // v0.2.x uses ERC1967 proxy via AdminLessERC1967Factory
  //   // Salt = bytes32(uint256(keccak256(abi.encodePacked(data, index))) & type(uint96).max)
  //   //
  //   // NOTE: Local address computation may not match the factory's CREATE2 output
  //   // due to variations in Solady's ERC1967 init code hash across versions.
  //   // For production use, always verify with PublicClient.getSenderAddress().

  //   // Get the initialize calldata (with selector)
  //   final initializeCalldata = _encodeInitializeV2();

  //   // Compute salt: keccak256(data, index) then mask to 96 bits
  //   final saltPreImage = Hex.concat([
  //     initializeCalldata,
  //     Hex.fromBigInt(_config.index, byteLength: 32),
  //   ]);
  //   final saltHash = keccak256(Hex.decode(saltPreImage));
  //   final saltBigInt = Hex.toBigInt(Hex.fromBytes(saltHash));

  //   // Mask to 96 bits (type(uint96).max = 2^96 - 1)
  //   final uint96Max = (BigInt.one << 96) - BigInt.one;
  //   final maskedSalt = saltBigInt & uint96Max;
  //   final salt = Hex.fromBigInt(maskedSalt, byteLength: 32);

  //   // Init code hash for the ERC1967 proxy
  //   final initCodeHash =
  //       _computeERC1967InitCodeHash(_addresses.accountImplementation);

  //   // CREATE2: keccak256(0xff ++ factory ++ salt ++ initCodeHash)[12:]
  //   final preImage = Hex.concat([
  //     '0xff',
  //     Hex.strip0x(_addresses.factory.hex),
  //     Hex.strip0x(salt),
  //     Hex.fromBytes(initCodeHash),
  //   ]);

  //   final addressHash = keccak256(Hex.decode(preImage));
  //   return EthereumAddress.fromHex(Hex.slice(Hex.fromBytes(addressHash), 12));
  // }

  // Future<EthereumAddress> _computeAddressV3() async {
  //   // v0.3.x uses meta factory pattern
  //   // The inner factory (KernelFactory) computes the address using:
  //   // actualSalt = keccak256(abi.encodePacked(initializeCalldata, index))
  //   // Then deploys an ERC1967 proxy with that salt

  //   final initializeData = _encodeInitializeV3();
  //   final initializeCalldata = Hex.concat([
  //     KernelSelectors.initializeV3,
  //     Hex.strip0x(initializeData),
  //   ]);

  //   // The inner factory computes actualSalt = keccak256(data, salt)
  //   // where data = initializeCalldata and salt = index
  //   final saltPreImage = Hex.concat([
  //     initializeCalldata,
  //     Hex.fromBigInt(_config.index, byteLength: 32),
  //   ]);
  //   final actualSalt = keccak256(Hex.decode(saltPreImage));

  //   // Kernel v0.3.x uses Solady's LibClone.createDeterministicERC1967
  //   // The init code hash is computed using initCodeHashERC1967
  //   final initCodeHash =
  //       _computeERC1967InitCodeHash(_addresses.accountImplementation);

  //   // CREATE2 from inner factory (not meta factory)
  //   final preImage = Hex.concat([
  //     '0xff',
  //     Hex.strip0x(_addresses.factory.hex),
  //     Hex.fromBytes(actualSalt),
  //     Hex.fromBytes(initCodeHash),
  //   ]);

  //   final addressHash = keccak256(Hex.decode(preImage));
  //   return EthereumAddress.fromHex(Hex.slice(Hex.fromBytes(addressHash), 12));
  // }

  // /// Computes the ERC1967 init code hash as Solady's LibClone does.
  // /// See: https://github.com/Vectorized/solady/blob/main/src/utils/LibClone.sol
  // Uint8List _computeERC1967InitCodeHash(EthereumAddress implementation) {
  //   // Simulate the Solady assembly that builds the init code
  //   final memory = Uint8List(0x80);
  //   final impl = BigInt.parse(Hex.strip0x(implementation.hex), radix: 16);

  //   // mstore(0x60, 0xcc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3)
  //   _mstore(
  //     memory,
  //     0x60,
  //     BigInt.parse(
  //       'cc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3',
  //       radix: 16,
  //     ),
  //   );

  //   // mstore(0x40, 0x5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076)
  //   _mstore(
  //     memory,
  //     0x40,
  //     BigInt.parse(
  //       '5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076',
  //       radix: 16,
  //     ),
  //   );

  //   // mstore(0x20, 0x6009)
  //   _mstore(memory, 0x20, BigInt.from(0x6009));

  //   // mstore(0x1e, implementation)
  //   _mstore(memory, 0x1e, impl);

  //   // mstore(0x0a, 0x603d3d8160223d3973)
  //   _mstore(memory, 0x0a, BigInt.parse('603d3d8160223d3973', radix: 16));

  //   // Extract bytes from 0x21 for 0x5f (95) bytes and hash
  //   return keccak256(memory.sublist(0x21, 0x21 + 0x5f));
  // }

  // void _mstore(Uint8List memory, int offset, BigInt value) {
  //   for (var i = 31; i >= 0 && offset + (31 - i) < memory.length; i--) {
  //     memory[offset + (31 - i)] =
  //         ((value >> (i * 8)) & BigInt.from(0xff)).toInt();
  //   }
  // }

  @override
  Future<String> getInitCode() async {
    final factoryData = await getFactoryData();
    if (factoryData == null) return '0x';

    return Hex.concat([
      factoryData.factory.hex,
      Hex.strip0x(factoryData.factoryData),
    ]);
  }

  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    if (_config.version == KernelVersion.v0_2_4) {
      return _getFactoryDataV2();
    } else {
      return _getFactoryDataV3();
    }
  }

  Future<({EthereumAddress factory, String factoryData})>
      _getFactoryDataV2() async {
    // Build the full initialize calldata including selector
    final initializeCalldata = _encodeInitializeV2();

    // createAccount(address implementation, bytes data, uint256 index)
    // The data is the full initialize calldata that will be called on the deployed kernel
    final factoryData = Hex.concat([
      KernelSelectors.createAccountV2,
      AbiEncoder.encodeAddress(_addresses.accountImplementation),
      AbiEncoder.encodeUint256(BigInt.from(3 * 32)), // offset to bytes
      AbiEncoder.encodeUint256(_config.index),
      Hex.strip0x(AbiEncoder.encodeBytes(initializeCalldata)),
    ]);

    return (factory: _addresses.factory, factoryData: factoryData);
  }

  Future<({EthereumAddress factory, String factoryData})>
      _getFactoryDataV3() async {
    final initializeData = _encodeInitializeV3();

    // Full initialize calldata (with selector) for the factory
    final initializeCalldata = Hex.concat([
      KernelSelectors.initializeV3,
      Hex.strip0x(initializeData),
    ]);

    // Salt for deployment
    final salt = Hex.fromBigInt(_config.index, byteLength: 32);

    // Use metaFactory with deployWithFactory(address factory, bytes createData, bytes32 salt)
    // This is the default pattern in permissionless.js
    final factoryData = Hex.concat([
      KernelSelectors.deployWithFactory,
      AbiEncoder.encodeAddress(_addresses.factory),
      // bytes createData - dynamic parameter
      AbiEncoder.encodeUint256(BigInt.from(3 * 32)), // offset to bytes (96)
      Hex.strip0x(salt),
      Hex.strip0x(AbiEncoder.encodeBytes(initializeCalldata)),
    ]);

    // Return metaFactory address (not inner factory)
    return (factory: _addresses.metaFactory!, factoryData: factoryData);
  }

  String _encodeInitializeV2() {
    // initialize(IKernelValidator defaultValidator, bytes enableData)
    // For ECDSA validator, enableData is the owner address

    // Use ECDSA validator address (or account implementation as fallback for backwards compat)
    final validatorAddress =
        _addresses.ecdsaValidator ?? _addresses.accountImplementation;

    // Enable data for ECDSA validator is the owner address
    final enableData = _config.owner.address.hex;

    // Encode initialize call with selector
    return Hex.concat([
      KernelSelectors.initializeV2, // 0xd1f57894
      AbiEncoder.encodeAddress(validatorAddress),
      AbiEncoder.encodeUint256(BigInt.from(2 * 32)), // offset to bytes
      Hex.strip0x(AbiEncoder.encodeBytes(enableData)),
    ]);
  }

  String _encodeInitializeV3() {
    // initialize(bytes21 rootValidator, address hook, bytes validatorData, bytes hookData, bytes[] initConfig)

    // Root validator ID: type (1) + validator address (20) = 21 bytes
    // Type 0x01 = VALIDATOR (not 0x00 which is ROOT/sudo mode)
    final validatorId = Hex.concat([
      Hex.fromBigInt(BigInt.from(KernelValidatorType.validator), byteLength: 1),
      _addresses.ecdsaValidator!.hex,
    ]);

    // Validator data: raw owner address (20 bytes) for ECDSA validator
    // The validator expects: address owner = address(bytes20(_data[0:20]))
    final validatorData = _config.owner.address.hex;

    // Hook address (none)
    final hookAddress = zeroAddress;

    // Hook data (empty)
    const hookData = '0x';

    // Dynamic offsets (relative to start of params, not including selector)
    const validatorDataOffset = 5 * 32; // 5 static params (160 bytes)
    final validatorDataEncoded = AbiEncoder.encodeBytes(validatorData);
    final hookDataOffset =
        validatorDataOffset + Hex.byteLength(validatorDataEncoded);
    final hookDataEncoded = AbiEncoder.encodeBytes(hookData);
    final initConfigOffset = hookDataOffset + Hex.byteLength(hookDataEncoded);

    return Hex.concat([
      // bytes21 rootValidator (right-padded to 32 bytes per ABI spec)
      Hex.padRight(validatorId, 32),
      // address hook
      AbiEncoder.encodeAddress(hookAddress),
      // offset to validatorData
      AbiEncoder.encodeUint256(BigInt.from(validatorDataOffset)),
      // offset to hookData
      AbiEncoder.encodeUint256(BigInt.from(hookDataOffset)),
      // offset to initConfig
      AbiEncoder.encodeUint256(BigInt.from(initConfigOffset)),
      // validatorData (bytes) - raw 20-byte owner address
      Hex.strip0x(validatorDataEncoded),
      // hookData (bytes) - empty
      Hex.strip0x(hookDataEncoded),
      // initConfig (bytes[]) - empty array
      AbiEncoder.encodeUint256(BigInt.zero), // array length = 0
    ]);
  }

  @override
  String encodeCall(Call call) {
    if (_config.version == KernelVersion.v0_2_4) {
      return _encodeCallV2(call);
    } else {
      return encode7579Execute(call);
    }
  }

  // execute(address to, uint256 value, bytes data, uint8 operation)
  String _encodeCallV2(Call call) => Hex.concat([
        KernelSelectors.executeV2,
        AbiEncoder.encodeAddress(call.to),
        AbiEncoder.encodeUint256(call.value),
        AbiEncoder.encodeUint256(BigInt.from(4 * 32)), // offset to bytes
        AbiEncoder.encodeUint256(BigInt.zero), // operation = call
        Hex.strip0x(AbiEncoder.encodeBytes(call.data)),
      ]);

  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }

    if (calls.length == 1) {
      return encodeCall(calls.first);
    }

    if (_config.version == KernelVersion.v0_2_4) {
      return _encodeCallsV2(calls);
    } else {
      return encode7579ExecuteBatch(calls);
    }
  }

  String _encodeCallsV2(List<Call> calls) {
    // executeBatch((address,uint256,bytes)[])
    // Each element is a struct with to, value, data

    const structsOffset = 32; // offset to array
    final arrayLength = AbiEncoder.encodeUint256(BigInt.from(calls.length));

    // Calculate offsets for each struct
    final structOffsets = <String>[];
    final structData = <String>[];

    var currentOffset = calls.length * 32;

    for (final call in calls) {
      structOffsets.add(AbiEncoder.encodeUint256(BigInt.from(currentOffset)));

      final encoded = _encodeCallStructV2(call);
      structData.add(encoded);
      currentOffset += Hex.byteLength(encoded);
    }

    return Hex.concat([
      KernelSelectors.executeBatchV2,
      AbiEncoder.encodeUint256(BigInt.from(structsOffset)),
      arrayLength,
      ...structOffsets,
      ...structData,
    ]);
  }

  String _encodeCallStructV2(Call call) {
    // (address to, uint256 value, bytes data)
    const dataOffset = 3 * 32;

    return Hex.concat([
      AbiEncoder.encodeAddress(call.to),
      AbiEncoder.encodeUint256(call.value),
      AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
      Hex.strip0x(AbiEncoder.encodeBytes(call.data)),
    ]);
  }

  @override
  String getStubSignature() {
    if (_config.version == KernelVersion.v0_2_4) {
      // v0.2.x: ROOT_MODE (4 bytes) + ECDSA signature (65 bytes)
      return Hex.concat([
        '0x00000000', // ROOT_MODE
        Hex.strip0x(kernelDummyEcdsaSignature),
      ]);
    } else {
      // v0.3.x: just the ECDSA signature (65 bytes)
      return kernelDummyEcdsaSignature;
    }
  }

  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = await _computeUserOpHash(userOp);
    final signature = await _config.owner.signRawHash(userOpHash);

    if (_config.version == KernelVersion.v0_2_4) {
      // v0.2.x: ROOT_MODE (4 bytes) + signature
      return Hex.concat([
        '0x00000000',
        Hex.strip0x(signature),
      ]);
    } else {
      // v0.3.x: just the signature (no prefix)
      return signature;
    }
  }

  /// Signs a v0.6 UserOperation (for Kernel v0.2.4).
  ///
  /// This method computes the correct hash for EntryPoint v0.6 format
  /// and returns the signature with ROOT_MODE prefix.
  Future<String> signUserOperationV06(UserOperationV06 userOp) async {
    final userOpHash = _computeUserOpHashV06(userOp);
    final signature = await _config.owner.signRawHash(userOpHash);

    // v0.2.x: ROOT_MODE (4 bytes) + signature
    return Hex.concat([
      '0x00000000',
      Hex.strip0x(signature),
    ]);
  }

  /// Computes the userOpHash for v0.6 UserOperation.
  String _computeUserOpHashV06(UserOperationV06 userOp) {
    final packed = _packUserOpV06(userOp);
    final packedHash = keccak256(Hex.decode(packed));

    final hashInput = Hex.concat([
      Hex.fromBytes(packedHash),
      AbiEncoder.encodeAddress(entryPoint),
      AbiEncoder.encodeUint256(chainId),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(hashInput)));
  }

  /// Packs a v0.6 UserOperation for hashing.
  String _packUserOpV06(UserOperationV06 userOp) {
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

  /// Signs a personal message (EIP-191).
  ///
  /// Returns the raw ECDSA signature without Kernel-specific prefixes.
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    return _config.owner.signRawHash(messageHash);
  }

  /// Signs EIP-712 typed data.
  ///
  /// Returns the raw ECDSA signature without Kernel-specific prefixes.
  @override
  Future<String> signTypedData(TypedData typedData) async =>
      _config.owner.signTypedData(typedData);

  Future<String> _computeUserOpHash(UserOperationV07 userOp) async {
    // Pack the UserOperation according to ERC-4337
    final packedUserOp = _packUserOp(userOp);
    final userOpHashInner = keccak256(Hex.decode(packedUserOp));

    // Final hash: keccak256(userOpHash, entryPoint, chainId)
    final finalPreImage = Hex.concat([
      Hex.fromBytes(userOpHashInner),
      AbiEncoder.encodeAddress(entryPoint),
      AbiEncoder.encodeUint256(chainId),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(finalPreImage)));
  }

  String _packUserOp(UserOperationV07 userOp) {
    // Pack initCode
    final initCode = userOp.factory != null
        ? Hex.concat([
            userOp.factory!.hex,
            Hex.strip0x(userOp.factoryData ?? '0x'),
          ])
        : '0x';
    final initCodeHash = keccak256(Hex.decode(initCode));

    // Pack callData
    final callDataHash = keccak256(Hex.decode(userOp.callData));

    // Pack accountGasLimits (v0.7 packing)
    final accountGasLimits = Hex.concat([
      Hex.fromBigInt(userOp.verificationGasLimit, byteLength: 16),
      Hex.fromBigInt(userOp.callGasLimit, byteLength: 16),
    ]);

    // Pack gasFees
    final gasFees = Hex.concat([
      Hex.fromBigInt(userOp.maxPriorityFeePerGas, byteLength: 16),
      Hex.fromBigInt(userOp.maxFeePerGas, byteLength: 16),
    ]);

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

/// Creates a Kernel smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createKernelSmartAccount(
///   owner: owner,
///   chainId: BigInt.from(11155111),
///   version: KernelVersion.v0_3_1,
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Kernel account: $address');
/// ```
KernelSmartAccount createKernelSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  KernelVersion version = KernelVersion.v0_3_1,
  BigInt? index,
  KernelAddresses? customAddresses,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    KernelSmartAccount(
      KernelSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        version: version,
        index: index,
        customAddresses: customAddresses,
        publicClient: publicClient,
        address: address,
      ),
    );
