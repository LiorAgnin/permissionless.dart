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
import '../../utils/multisend.dart';
import '../account_owner.dart';
import 'constants.dart';

/// Safe proxy creation code for CREATE2 address calculation.
/// This is the standard Safe proxy bytecode used by SafeProxyFactory.
const String _proxyCreationCode =
    '0x608060405234801561001057600080fd5b506040516101e63803806101e68339818101604052602081101561003357600080fd5b8101908080519060200190929190505050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614156100ca576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260228152602001806101c46022913960400191505060405180910390fd5b806000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505060ab806101196000396000f3fe608060405273ffffffffffffffffffffffffffffffffffffffff600054167fa619486e0000000000000000000000000000000000000000000000000000000060003514156050578060005260206000f35b3660008037600080366000845af43d6000803e60008114156070573d6000fd5b3d6000f3fea264697066735822122003d1488ee65e08fa41e58e888a9865554c535f2c77126a82cb4c0f917f31441364736f6c63430007060033496e76616c69642073696e676c65746f6e20616464726573732070726f7669646564';

/// Configuration parameters for creating a Safe smart account.
class SafeSmartAccountConfig {
  SafeSmartAccountConfig({
    required this.owners,
    BigInt? threshold,
    this.version = SafeVersion.v1_4_1,
    this.entryPointVersion = EntryPointVersion.v07,
    BigInt? saltNonce,
    required this.chainId,
    this.customAddresses,
    this.publicClient,
    this.address,
    // ERC-7579 parameters
    this.erc7579LaunchpadAddress,
    this.validators = const [],
    this.executors = const [],
    this.fallbacks = const [],
    this.hooks = const [],
    this.attesters = const [],
    this.attestersThreshold = 0,
  })  : threshold = threshold ?? BigInt.one,
        saltNonce = saltNonce ?? BigInt.zero {
    if (owners.isEmpty) {
      throw ArgumentError('At least one owner is required');
    }
    if (this.threshold > BigInt.from(owners.length)) {
      throw ArgumentError('Threshold cannot be greater than number of owners');
    }
    if (this.threshold <= BigInt.zero) {
      throw ArgumentError('Threshold must be positive');
    }
  }

  /// The owner(s) of the Safe account.
  final List<AccountOwner> owners;

  /// The number of signatures required (threshold). Defaults to 1.
  final BigInt threshold;

  /// The Safe version to use.
  final SafeVersion version;

  /// The EntryPoint version to use.
  final EntryPointVersion entryPointVersion;

  /// Optional salt for deterministic address generation.
  final BigInt saltNonce;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Optional custom contract addresses.
  final SafeAddresses? customAddresses;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthAddress? address;

  // ============================================================================
  // ERC-7579 Configuration
  // ============================================================================

  /// The ERC-7579 launchpad address for deploying modular Safe accounts.
  ///
  /// When provided, the Safe switches to ERC-7579 mode which:
  /// - Uses `encode7579Calls` instead of `executeUserOp` for call encoding
  /// - Enables module management (install/uninstall validators, executors, etc.)
  /// - Uses the launchpad for initial deployment with module configuration
  ///
  /// Use [Safe7579Addresses.erc7579LaunchpadAddress] for the default address.
  final EthAddress? erc7579LaunchpadAddress;

  /// Validator modules to install during deployment (ERC-7579 mode only).
  ///
  /// Validators verify signatures and authorize user operations.
  final List<Safe7579ModuleInit> validators;

  /// Executor modules to install during deployment (ERC-7579 mode only).
  ///
  /// Executors can call the account's execute function.
  final List<Safe7579ModuleInit> executors;

  /// Fallback handler modules to install during deployment (ERC-7579 mode only).
  ///
  /// Fallback handlers respond to calls the account doesn't recognize.
  final List<Safe7579ModuleInit> fallbacks;

  /// Hook modules to install during deployment (ERC-7579 mode only).
  ///
  /// Hooks run before and/or after executions.
  final List<Safe7579ModuleInit> hooks;

  /// Attester addresses for module verification (ERC-7579 mode only).
  ///
  /// Attesters verify that modules are safe to install. Only modules
  /// approved by the required number of attesters can be installed.
  ///
  /// Use [Safe7579Addresses.rhinestoneAttester] for Rhinestone attestation.
  final List<EthAddress> attesters;

  /// Minimum number of attester approvals required (ERC-7579 mode only).
  ///
  /// A module must be approved by at least this many attesters to be installed.
  final int attestersThreshold;

  /// Whether ERC-7579 mode is enabled.
  bool get isErc7579Enabled => erc7579LaunchpadAddress != null;
}

/// A Safe smart account implementation for ERC-4337.
class SafeSmartAccount implements SmartAccount {
  SafeSmartAccount(this._config) : _addresses = _resolveAddresses(_config);

  final SafeSmartAccountConfig _config;
  final SafeAddresses _addresses;
  EthAddress? _cachedAddress;

  static SafeAddresses _resolveAddresses(SafeSmartAccountConfig config) {
    if (config.customAddresses != null) {
      return config.customAddresses!;
    }
    final addresses = SafeVersionAddresses.getAddresses(
      config.version,
      config.entryPointVersion,
    );
    if (addresses == null) {
      throw ArgumentError(
        'Safe version ${config.version.value} does not support '
        'EntryPoint version ${config.entryPointVersion.value}',
      );
    }
    return addresses;
  }

  /// The Safe version being used.
  SafeVersion get version => _config.version;

  /// The EntryPoint version being used.
  EntryPointVersion get entryPointVersion => _config.entryPointVersion;

  /// The owners of this Safe.
  List<AccountOwner> get owners => _config.owners;

  /// The signature threshold.
  BigInt get threshold => _config.threshold;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address for this account.
  @override
  EthAddress get entryPoint =>
      EntryPointAddresses.fromVersion(entryPointVersion);

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => BigInt.zero;

  /// Whether ERC-7579 mode is enabled.
  bool get isErc7579Enabled => _config.isErc7579Enabled;

  /// The Safe 4337 module address.
  ///
  /// In ERC-7579 mode, this returns the Safe7579 module address.
  /// Otherwise, it returns the standard Safe 4337 module.
  EthAddress get _safe4337ModuleAddress => isErc7579Enabled
      ? Safe7579Addresses.safe7579ModuleAddress
      : _addresses.safe4337ModuleAddress;

  /// Gets the deterministic address of this Safe account.
  ///
  /// The address is computed locally using the CREATE2 formula, which means
  /// it can be known before the account is actually deployed and works even
  /// for accounts that are already deployed.
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

    // Option 2: Compute address locally using CREATE2 formula
    // This is the same approach as permissionless.js and works regardless
    // of whether the account is deployed or not.
    _cachedAddress = _computeCreate2Address();
    return _cachedAddress!;
  }

  /// Computes the Safe account address using the CREATE2 formula.
  ///
  /// address = keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))[12:]
  ///
  /// Where:
  /// - factory = safeProxyFactoryAddress
  /// - salt = keccak256(keccak256(initializer) ++ saltNonce)
  /// - bytecode = proxyCreationCode ++ abi.encode(singleton)
  ///
  /// In ERC-7579 mode, the singleton is the launchpad address (not the Safe singleton).
  EthAddress _computeCreate2Address() {
    final salt = _computeSalt();

    // In 7579 mode, the proxy points to the launchpad which handles setup
    // before transferring to the actual Safe singleton
    final singletonAddress = isErc7579Enabled
        ? _config.erc7579LaunchpadAddress!
        : _addresses.safeSingletonAddress;

    // deploymentCode = proxyCreationCode ++ uint256(singletonAddress)
    // This matches permissionless.js: encodePacked(["bytes", "uint256"], [proxyCreationCode, singleton])
    final deploymentCode = Hex.concat([
      _proxyCreationCode,
      AbiEncoder.encodeUint256(Hex.toBigInt(singletonAddress.hex)),
    ]);

    // CREATE2 address = keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))[12:]
    final bytecodeHash = keccak256(Hex.decode(deploymentCode));

    final preImage = Hex.concat([
      '0xff',
      Hex.strip0x(_addresses.safeProxyFactoryAddress.hex),
      Hex.strip0x(salt),
      Hex.fromBytes(bytecodeHash),
    ]);

    final addressHash = keccak256(Hex.decode(preImage));
    // Take last 20 bytes (40 hex chars) of the hash
    final addressHex = '0x${Hex.fromBytes(addressHash).substring(26)}';

    return EthAddress(addressHex);
  }

  /// Computes the salt for CREATE2 address derivation.
  String _computeSalt() {
    // Salt = keccak256(keccak256(initializer) ++ saltNonce)
    final initializer = _getInitializer();
    final initializerHash = keccak256(Hex.decode(initializer));

    final saltPreImage = Hex.concat([
      Hex.fromBytes(initializerHash),
      Hex.fromBigInt(_config.saltNonce, byteLength: 32),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(saltPreImage)));
  }

  /// Gets the initializer calldata for Safe setup.
  ///
  /// In standard mode:
  /// The Safe's setup() function performs a **delegatecall** to the `to` address
  /// with `data`. For permissionless.js compatibility, we wrap the enableModules
  /// call through MultiSend. This ensures the initializer produces the same
  /// salt hash as permissionless.js, resulting in identical CREATE2 addresses.
  ///
  /// In ERC-7579 mode:
  /// Uses the launchpad's preValidationSetup function with the hash of the
  /// initSafe7579 call data. The actual setup happens during the first UserOp.
  String _getInitializer() {
    if (isErc7579Enabled) {
      return _get7579Initializer();
    }
    return _getStandardInitializer();
  }

  /// Gets the standard (non-7579) initializer.
  String _getStandardInitializer() {
    final ownerAddresses = _config.owners.map((o) => o.address).toList();

    // Encode enableModules call for the Safe 4337 module
    final enableModulesData =
        encodeEnableModules([_addresses.safe4337ModuleAddress]);

    // Wrap enableModules through MultiSend with DelegateCall operation.
    // This matches permissionless.js behavior exactly:
    // 1. Create a MultiSend internal transaction to safeModuleSetupAddress
    // 2. Use operation=1 (DelegateCall) so enableModules runs in Safe's context
    // 3. Pass multiSendAddress as `to` and multiSend calldata as `data`
    final multiSendCallData = encodeMultiSendWithOperations([
      MultiSendCall(
        to: _addresses.safeModuleSetupAddress,
        value: BigInt.zero,
        data: enableModulesData,
        operation: OperationType.delegateCall, // DelegateCall for module setup
      ),
    ]);

    return encodeSafeSetup(
      owners: ownerAddresses,
      threshold: _config.threshold,
      to: _addresses.multiSendAddress, // MultiSend contract
      data: multiSendCallData, // Wrapped enableModules call
      fallbackHandler: _addresses.safe4337ModuleAddress,
      paymentToken: EthAddress.zero,
      payment: BigInt.zero,
      paymentReceiver: EthAddress.zero,
    );
  }

  /// Gets the ERC-7579 launchpad initializer.
  ///
  /// The launchpad uses a two-phase initialization:
  /// 1. preValidationSetup: Called with hash of full InitData struct
  /// 2. setupSafe: Called during first UserOp with full init data
  String _get7579Initializer() {
    // Compute initHash from the FULL InitData struct, not just initSafe7579
    final initHash = _computeInitHash();

    // preValidationSetup(initHash, to, preInit)
    // - initHash: keccak256 of the full InitData struct
    // - to: zeroAddress (no pre-init callback needed)
    // - preInit: empty for standard setup
    return encodePreValidationSetup(
      initHash: initHash,
      to: EthAddress.zero, // Must be zeroAddress per permissionless.js
      preInit: '0x',
    );
  }

  /// Computes the initHash for the Safe7579 launchpad.
  ///
  /// The initHash is keccak256 of the ABI-encoded InitData struct:
  /// - address singleton
  /// - address[] owners
  /// - uint256 threshold
  /// - address setupTo
  /// - bytes setupData (the initSafe7579 call)
  /// - address safe7579
  /// - (address, bytes)[] validators
  String _computeInitHash() {
    final ownerAddresses = _config.owners.map((o) => o.address).toList();
    final initSafe7579Data = _encodeInitSafe7579();

    // Convert validators to tuple format
    final validators =
        _config.validators.map((m) => (m.module, m.initData)).toList();

    // Encode the full InitData struct
    return _encodeInitDataAndHash(
      singleton: _addresses.safeSingletonAddress,
      owners: ownerAddresses,
      threshold: _config.threshold,
      setupTo: _config.erc7579LaunchpadAddress!,
      setupData: initSafe7579Data,
      safe7579: Safe7579Addresses.safe7579ModuleAddress,
      validators: validators,
    );
  }

  /// ABI-encodes the InitData struct and returns its keccak256 hash.
  String _encodeInitDataAndHash({
    required EthAddress singleton,
    required List<EthAddress> owners,
    required BigInt threshold,
    required EthAddress setupTo,
    required String setupData,
    required EthAddress safe7579,
    required List<(EthAddress, String)> validators,
  }) {
    // Static part has 7 slots (7 * 32 = 224 bytes):
    // singleton, owners_offset, threshold, setupTo, setupData_offset, safe7579, validators_offset
    const staticSize = 7 * 32;

    // Encode owners array: length + addresses
    final ownersEncoded = _encodeAddressArrayForStruct(owners);
    const ownersOffset = staticSize;

    // Encode setupData bytes
    final setupDataEncoded = AbiEncoder.encodeBytes(setupData);
    final setupDataOffset = ownersOffset + Hex.byteLength(ownersEncoded);

    // Encode validators array
    final validatorsEncoded = _encodeModuleInitArrayForStruct(validators);
    final validatorsOffset = setupDataOffset + Hex.byteLength(setupDataEncoded);

    final encoded = Hex.concat([
      // Static parts
      AbiEncoder.encodeAddress(singleton),
      AbiEncoder.encodeUint256(BigInt.from(ownersOffset)),
      AbiEncoder.encodeUint256(threshold),
      AbiEncoder.encodeAddress(setupTo),
      AbiEncoder.encodeUint256(BigInt.from(setupDataOffset)),
      AbiEncoder.encodeAddress(safe7579),
      AbiEncoder.encodeUint256(BigInt.from(validatorsOffset)),
      // Dynamic parts
      Hex.strip0x(ownersEncoded),
      Hex.strip0x(setupDataEncoded),
      Hex.strip0x(validatorsEncoded),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(encoded)));
  }

  /// Encodes an array of addresses for struct encoding.
  String _encodeAddressArrayForStruct(List<EthAddress> addresses) {
    final parts = <String>[
      AbiEncoder.encodeUint256(BigInt.from(addresses.length)),
      ...addresses.map((a) => Hex.strip0x(AbiEncoder.encodeAddress(a))),
    ];
    return Hex.concat(parts);
  }

  /// Encodes a ModuleInit array for struct encoding.
  String _encodeModuleInitArrayForStruct(List<(EthAddress, String)> modules) {
    if (modules.isEmpty) {
      return AbiEncoder.encodeUint256(BigInt.zero);
    }

    final length = AbiEncoder.encodeUint256(BigInt.from(modules.length));
    final structOffsets = <String>[];
    final structData = <String>[];

    var currentOffset = modules.length * 32;

    for (final (module, initData) in modules) {
      structOffsets.add(AbiEncoder.encodeUint256(BigInt.from(currentOffset)));

      final initDataEncoded = AbiEncoder.encodeBytes(initData);
      const bytesOffset = 2 * 32;

      final structEncoded = Hex.concat([
        AbiEncoder.encodeAddress(module),
        AbiEncoder.encodeUint256(BigInt.from(bytesOffset)),
        Hex.strip0x(initDataEncoded),
      ]);

      structData.add(structEncoded);
      currentOffset += Hex.byteLength(structEncoded);
    }

    return Hex.concat([
      length,
      ...structOffsets.map(Hex.strip0x),
      ...structData.map(Hex.strip0x),
    ]);
  }

  /// Encodes the initSafe7579 call for the launchpad.
  ///
  /// Note: Validators are not included in initSafe7579 - they're passed
  /// through setupSafe during the first UserOp execution.
  String _encodeInitSafe7579() {
    // Convert module configs to tuple format
    final executors =
        _config.executors.map((m) => (m.module, m.initData)).toList();
    final fallbacks =
        _config.fallbacks.map((m) => (m.module, m.initData)).toList();
    final hooks = _config.hooks.map((m) => (m.module, m.initData)).toList();

    return encodeInitSafe7579(
      safe7579: Safe7579Addresses.safe7579ModuleAddress,
      executors: executors,
      fallbacks: fallbacks,
      hooks: hooks,
      attesters: _config.attesters,
      threshold: _config.attestersThreshold,
    );
  }

  /// Gets the init code for deploying this Safe account.
  ///
  /// This is used in the UserOperation when the account doesn't exist yet.
  @override
  Future<String> getInitCode() async {
    final initializer = _getInitializer();

    // In 7579 mode, the proxy points to the launchpad
    final singletonAddress = isErc7579Enabled
        ? _config.erc7579LaunchpadAddress!
        : _addresses.safeSingletonAddress;

    final factoryData = encodeCreateProxyWithNonce(
      singleton: singletonAddress,
      initializer: initializer,
      saltNonce: _config.saltNonce,
    );

    // InitCode = factory address (20 bytes) + factory calldata
    return Hex.concat([
      _addresses.safeProxyFactoryAddress.hex,
      Hex.strip0x(factoryData),
    ]);
  }

  /// Gets the factory address and data for UserOperation v0.7.
  @override
  Future<({EthAddress factory, String factoryData})?> getFactoryData() async {
    final initializer = _getInitializer();

    // In 7579 mode, the proxy points to the launchpad
    final singletonAddress = isErc7579Enabled
        ? _config.erc7579LaunchpadAddress!
        : _addresses.safeSingletonAddress;

    final data = encodeCreateProxyWithNonce(
      singleton: singletonAddress,
      initializer: initializer,
      saltNonce: _config.saltNonce,
    );

    return (factory: _addresses.safeProxyFactoryAddress, factoryData: data);
  }

  /// Encodes a single call for execution.
  ///
  /// In ERC-7579 mode, uses the standard execute(mode, calldata) format.
  /// In standard mode, uses executeUserOpWithErrorString.
  @override
  String encodeCall(Call call) {
    if (isErc7579Enabled) {
      return encode7579Execute(call);
    }
    return encodeExecuteUserOp(
      to: call.to,
      value: call.value,
      data: call.data,
      operation: OperationType.call.value,
    );
  }

  /// Encodes multiple calls for batch execution.
  ///
  /// In ERC-7579 mode, uses the standard execute(mode, calldata) format with batch encoding.
  /// In standard mode, uses MultiSend via DelegateCall.
  ///
  /// **Important for ERC-7579 deployment:** When deploying a Safe with ERC-7579 for the
  /// first time, use [encodeCallsForDeployment] instead. The launchpad requires
  /// the first UserOp to call `setupSafe()` with the full InitData.
  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }

    // ERC-7579 mode uses standard 7579 batch encoding
    if (isErc7579Enabled) {
      return encode7579ExecuteBatch(calls);
    }

    // Standard mode: single call optimization
    if (calls.length == 1) {
      return encodeCall(calls.first);
    }

    // Standard mode: use MultiSend via DelegateCall
    final multiSendData = encodeMultiSend(calls);

    return encodeExecuteUserOp(
      to: _addresses.multiSendAddress,
      value: BigInt.zero,
      data: multiSendData,
      operation: OperationType.delegateCall.value,
    );
  }

  /// Encodes calls for the first UserOperation during ERC-7579 Safe deployment.
  ///
  /// In ERC-7579 mode, the first UserOp must call `setupSafe()` on the launchpad
  /// with the full InitData struct. The user's calls are embedded in the `callData`
  /// field of InitData.
  ///
  /// This is only needed when:
  /// - ERC-7579 mode is enabled
  /// - The Safe is not yet deployed (first UserOp)
  ///
  /// For subsequent UserOps after deployment, use [encodeCalls] instead.
  String encodeCallsForDeployment(List<Call> calls) {
    if (!isErc7579Enabled) {
      // Standard mode doesn't need special deployment encoding
      return encodeCalls(calls);
    }

    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }

    // Encode the user's calls using ERC-7579 format
    final userCallData = encode7579ExecuteBatch(calls);

    // Build the full InitData for setupSafe
    return _encodeSetupSafe(userCallData);
  }

  /// Encodes the setupSafe call for first-time ERC-7579 deployment.
  String _encodeSetupSafe(String userCallData) {
    final ownerAddresses = _config.owners.map((o) => o.address).toList();
    final initSafe7579Data = _encodeInitSafe7579();

    // Convert validators to tuple format
    final validators =
        _config.validators.map((m) => (m.module, m.initData)).toList();

    final initData = Safe7579InitData(
      singleton: _addresses.safeSingletonAddress,
      owners: ownerAddresses,
      threshold: _config.threshold,
      setupTo: _config.erc7579LaunchpadAddress!,
      setupData: initSafe7579Data,
      safe7579: Safe7579Addresses.safe7579ModuleAddress,
      validators: validators,
      callData: userCallData,
    );

    return encodeSetupSafe(initData);
  }

  /// Gets a stub signature for gas estimation.
  ///
  /// This returns a signature that has the correct format but
  /// with dummy data. Used by bundlers to estimate gas.
  @override
  String getStubSignature() {
    // validAfter (6 bytes) + validUntil (6 bytes) + signature (65 bytes per owner)
    final validAfter = Hex.fromBigInt(BigInt.zero, byteLength: 6);
    final validUntil = Hex.fromBigInt(BigInt.zero, byteLength: 6);

    // Stub signature for each owner (sorted by address)
    final sortedOwners = List<AccountOwner>.from(_config.owners)
      ..sort((a, b) => a.address.compareTo(b.address));

    final signatures = <String>[];
    for (final owner in sortedOwners) {
      // Format: address (32 bytes padded) + dummy signature (32 bytes) + v (1 byte)
      // Using static signature format (v = 1 or similar indicator)
      final r = Hex.fromBigInt(Hex.toBigInt(owner.address.hex), byteLength: 32);
      const s = Hex.zero32; // dummy s value
      final v = Hex.fromBigInt(BigInt.from(1), byteLength: 1);
      signatures.add(Hex.concat([r, s, v]));
    }

    return Hex.concat([validAfter, validUntil, ...signatures]);
  }

  /// Signs a UserOperation.
  ///
  /// For EntryPoint v0.7, creates an EIP-712 signature over the SafeOp.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    // Use the sender from the UserOp rather than computing locally
    // This ensures the signature matches the actual account address
    final accountAddress = userOp.sender;

    // Compute SafeOp hash for EIP-712 signing
    final safeOpHash = _computeSafeOpHash(userOp, accountAddress);

    // Sign with each owner (sorted by address for consistency)
    final sortedOwners = List<AccountOwner>.from(_config.owners)
      ..sort((a, b) => a.address.compareTo(b.address));

    final signatures = <String>[];
    for (final owner in sortedOwners) {
      // Safe signs the raw EIP-712 hash directly (no personal message prefix)
      final sig = await owner.signRawHash(safeOpHash);
      signatures.add(Hex.strip0x(sig));
    }

    // Prepend validity period (validAfter, validUntil)
    final validAfter = Hex.fromBigInt(BigInt.zero, byteLength: 6);
    final validUntil = Hex.fromBigInt(BigInt.zero, byteLength: 6);

    return Hex.concat([validAfter, validUntil, ...signatures]);
  }

  /// Signs a personal message (EIP-191).
  ///
  /// The message is hashed and signed by all owners (sorted by address).
  /// Returns a combined signature suitable for EIP-1271 verification.
  @override
  Future<String> signMessage(String message) async {
    final messageHash = hashMessage(message);
    return _signHash(messageHash);
  }

  /// Signs EIP-712 typed data.
  ///
  /// The typed data is hashed and signed by all owners (sorted by address).
  /// Returns a combined signature suitable for EIP-1271 verification.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final hash = hashTypedData(typedData);
    return _signHash(hash);
  }

  /// Signs a hash with all owners and returns the combined signature.
  Future<String> _signHash(String hash) async {
    // Sign with each owner (sorted by address for consistency)
    final sortedOwners = List<AccountOwner>.from(_config.owners)
      ..sort((a, b) => a.address.compareTo(b.address));

    final signatures = <String>[];
    for (final owner in sortedOwners) {
      // Safe signs the raw hash directly (no personal message prefix)
      final sig = await owner.signRawHash(hash);
      signatures.add(Hex.strip0x(sig));
    }

    return Hex.concat(signatures);
  }

  /// Computes the SafeOp hash for EIP-712 signing.
  String _computeSafeOpHash(
    UserOperationV07 userOp,
    EthAddress accountAddress,
  ) {
    // IMPORTANT: Domain separator uses the Safe4337Module address as verifyingContract
    // (not the Safe account address!) because Safe's fallback uses 'call' not 'delegatecall',
    // so 'this' in the module's domainSeparator() refers to the module's address.
    final domainSeparator = _computeDomainSeparator();

    // SafeOp struct hash
    final safeOpStructHash = _computeSafeOpStructHash(userOp, accountAddress);

    // EIP-712 hash: keccak256("\x19\x01" ++ domainSeparator ++ structHash)
    final preImage = Hex.concat([
      '0x1901',
      Hex.strip0x(domainSeparator),
      Hex.strip0x(safeOpStructHash),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(preImage)));
  }

  /// Computes the EIP-712 domain separator.
  ///
  /// IMPORTANT: The verifyingContract is the Safe4337Module address, NOT the Safe account.
  /// This is because Safe's fallback handler uses 'call' (not 'delegatecall'),
  /// so when the module's domainSeparator() function runs, 'this' refers to the module.
  ///
  /// In ERC-7579 mode, this uses the Safe7579 module address instead.
  String _computeDomainSeparator() {
    // Domain type hash: keccak256("EIP712Domain(uint256 chainId,address verifyingContract)")
    const domainTypeString =
        'EIP712Domain(uint256 chainId,address verifyingContract)';
    final domainTypeHash =
        keccak256(Uint8List.fromList(domainTypeString.codeUnits));

    final encoded = Hex.concat([
      Hex.fromBytes(domainTypeHash),
      AbiEncoder.encodeUint256(_config.chainId),
      AbiEncoder.encodeAddress(
        _safe4337ModuleAddress,
      ), // Use module address (7579 or standard)
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(encoded)));
  }

  /// Computes the SafeOp struct hash for EIP-712.
  String _computeSafeOpStructHash(
    UserOperationV07 userOp,
    EthAddress accountAddress,
  ) {
    // SafeOp type hash for v0.7
    const safeOpTypeString =
        'SafeOp(address safe,uint256 nonce,bytes initCode,bytes callData,uint128 verificationGasLimit,uint128 callGasLimit,uint256 preVerificationGas,uint128 maxPriorityFeePerGas,uint128 maxFeePerGas,bytes paymasterAndData,uint48 validAfter,uint48 validUntil,address entryPoint)';

    final safeOpTypeHash =
        keccak256(Uint8List.fromList(safeOpTypeString.codeUnits));

    // Compute initCode hash
    var initCode = '0x';
    if (userOp.factory != null && userOp.factoryData != null) {
      initCode =
          Hex.concat([userOp.factory!.hex, Hex.strip0x(userOp.factoryData!)]);
    }
    final initCodeHash = keccak256(Hex.decode(initCode));

    // Compute callData hash
    final callDataHash = keccak256(Hex.decode(userOp.callData));

    // Compute paymasterAndData
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

    final encoded = Hex.concat([
      Hex.fromBytes(safeOpTypeHash),
      AbiEncoder.encodeAddress(accountAddress),
      AbiEncoder.encodeUint256(userOp.nonce),
      Hex.fromBytes(initCodeHash),
      Hex.fromBytes(callDataHash),
      AbiEncoder.encodeUint128(userOp.verificationGasLimit),
      AbiEncoder.encodeUint128(userOp.callGasLimit),
      AbiEncoder.encodeUint256(userOp.preVerificationGas),
      AbiEncoder.encodeUint128(userOp.maxPriorityFeePerGas),
      AbiEncoder.encodeUint128(userOp.maxFeePerGas),
      Hex.fromBytes(paymasterAndDataHash),
      AbiEncoder.encodeUint48(0), // validAfter
      AbiEncoder.encodeUint48(0), // validUntil
      AbiEncoder.encodeAddress(EntryPointAddresses.v07),
    ]);

    return Hex.fromBytes(keccak256(Hex.decode(encoded)));
  }
}

/// Creates a Safe smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// ## Standard Mode (default)
///
/// ```dart
/// final account = createSafeSmartAccount(
///   owners: [PrivateKeyOwner('0x...')],
///   chainId: BigInt.from(1),
/// );
/// ```
///
/// ## ERC-7579 Mode
///
/// To enable ERC-7579 module management, provide [erc7579LaunchpadAddress]:
///
/// ```dart
/// final account = createSafeSmartAccount(
///   owners: [PrivateKeyOwner('0x...')],
///   chainId: BigInt.from(1),
///   // Enable ERC-7579 mode
///   erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
///   // Configure attesters (required for module installation)
///   attesters: [Safe7579Addresses.rhinestoneAttester],
///   attestersThreshold: 1,
/// );
/// ```
///
/// With ERC-7579 enabled, you can install modules during deployment:
///
/// ```dart
/// final account = createSafeSmartAccount(
///   owners: [PrivateKeyOwner('0x...')],
///   chainId: BigInt.from(1),
///   erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
///   validators: [
///     Safe7579ModuleInit(module: sessionKeyValidatorAddress, initData: '0x...'),
///   ],
///   executors: [
///     Safe7579ModuleInit(module: automationModuleAddress),
///   ],
///   attesters: [Safe7579Addresses.rhinestoneAttester],
///   attestersThreshold: 1,
/// );
/// ```
SafeSmartAccount createSafeSmartAccount({
  required List<AccountOwner> owners,
  BigInt? threshold,
  SafeVersion version = SafeVersion.v1_4_1,
  EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  BigInt? saltNonce,
  required BigInt chainId,
  SafeAddresses? customAddresses,
  PublicClient? publicClient,
  EthAddress? address,
  // ERC-7579 parameters
  EthAddress? erc7579LaunchpadAddress,
  List<Safe7579ModuleInit> validators = const [],
  List<Safe7579ModuleInit> executors = const [],
  List<Safe7579ModuleInit> fallbacks = const [],
  List<Safe7579ModuleInit> hooks = const [],
  List<EthAddress> attesters = const [],
  int attestersThreshold = 0,
}) =>
    SafeSmartAccount(
      SafeSmartAccountConfig(
        owners: owners,
        threshold: threshold,
        version: version,
        entryPointVersion: entryPointVersion,
        saltNonce: saltNonce,
        chainId: chainId,
        customAddresses: customAddresses,
        publicClient: publicClient,
        address: address,
        erc7579LaunchpadAddress: erc7579LaunchpadAddress,
        validators: validators,
        executors: executors,
        fallbacks: fallbacks,
        hooks: hooks,
        attesters: attesters,
        attestersThreshold: attestersThreshold,
      ),
    );
