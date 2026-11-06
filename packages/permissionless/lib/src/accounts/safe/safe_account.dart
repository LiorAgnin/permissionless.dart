import 'dart:typed_data';

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
import '../../utils/packed_user_operation.dart' as packing;
import '../account_owner.dart';
import '../account_support.dart';
import '../webauthn_owner.dart';
import 'constants.dart';
import 'multisend.dart';
import 'safe_encoding.dart';
import 'safe_webauthn.dart';

/// `SafeProxyFactory.proxyCreationCode()` per Safe version, used for the
/// CREATE2 address when no public client is configured or the call fails.
///
/// Read from the canonical factories (v1.4.1 0x4e1D…ec67, v1.5.0 0x14F2…5e7b)
/// on Ethereum, Sepolia and Base; the two versions' proxies differ.
const Map<SafeVersion, String> _proxyCreationCodes = {
  SafeVersion.v1_4_1:
      '0x608060405234801561001057600080fd5b506040516101e63803806101e68339'
          '818101604052602081101561003357600080fd5b810190808051906020019092'
          '9190505050600073ffffffffffffffffffffffffffffffffffffffff168173ff'
          'ffffffffffffffffffffffffffffffffffffff1614156100ca576040517f08c3'
          '79a0000000000000000000000000000000000000000000000000000000008152'
          '6004018080602001828103825260228152602001806101c46022913960400191'
          '505060405180910390fd5b806000806101000a81548173ffffffffffffffffff'
          'ffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffff'
          'ffffffffff1602179055505060ab806101196000396000f3fe608060405273ff'
          'ffffffffffffffffffffffffffffffffffffff600054167fa619486e00000000'
          '0000000000000000000000000000000000000000000000006000351415605057'
          '8060005260206000f35b3660008037600080366000845af43d6000803e600081'
          '14156070573d6000fd5b3d6000f3fea264697066735822122003d1488ee65e08'
          'fa41e58e888a9865554c535f2c77126a82cb4c0f917f31441364736f6c634300'
          '07060033496e76616c69642073696e676c65746f6e2061646472657373207072'
          '6f7669646564',
  SafeVersion.v1_5_0:
      '0x608060405234801561001057600080fd5b506040516101b63803806101b68339'
          '818101604052602081101561003357600080fd5b810190808051906020019092'
          '9190505050600073ffffffffffffffffffffffffffffffffffffffff168173ff'
          'ffffffffffffffffffffffffffffffffffffff1614156100ca576040517f08c3'
          '79a0000000000000000000000000000000000000000000000000000000008152'
          '6004018080602001828103825260228152602001806101946022913960400191'
          '505060405180910390fd5b806000806101000a81548173ffffffffffffffffff'
          'ffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffff'
          'ffffffffff16021790555050607b806101196000396000f3fe60806040526000'
          '5463a619486e60003560e01c14156024578060601b606c5260206060f35b3660'
          '008037600080366000845af43d6000803e806040573d6000fd5b3d6000f3fea2'
          '646970667358221220e61834ebd2d8cd909d362bf67c47ef58fd665df38e6dd0'
          '36ce65611101d072e964736f6c63430007060033496e76616c69642073696e67'
          '6c65746f6e20616464726573732070726f7669646564',
};

/// Configuration parameters for creating a Safe smart account.
class SafeSmartAccountConfig {
  /// Creates a configuration for a Safe smart account.
  ///
  /// - [owners]: The owner(s) of the Safe (at least one required)
  /// - [threshold]: Number of signatures required (defaults to
  ///   `owners.length`, matching permissionless.js)
  /// - [version]: Safe version to use (defaults to v1.4.1)
  /// - [entryPointVersion]: EntryPoint version (defaults to v0.7)
  /// - [saltNonce]: Salt for deterministic address generation
  /// - [chainId]: Chain ID for signature domain
  ///
  /// Throws [ArgumentError] if no owners provided, threshold is invalid, or
  /// more than one owner is a [WebAuthnAccountOwner].
  SafeSmartAccountConfig({
    required this.owners,
    BigInt? threshold,
    this.version = SafeVersion.v1_4_1,
    this.entryPointVersion = EntryPointVersion.v07,
    BigInt? saltNonce,
    required this.chainId,
    this.customAddresses,
    this.nonceKey,
    this.entryPointAddress,
    this.publicClient,
    this.address,
    this.erc7579LaunchpadAddress,
    this.validators = const [],
    this.executors = const [],
    this.fallbacks = const [],
    this.hooks = const [],
    this.attesters = const [],
    this.attestersThreshold = 0,
    this.useMultiSendForSetup = true,
  })  : threshold = threshold ?? BigInt.from(owners.length),
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
    // Every WebAuthn owner is listed as the shared signer's address, which
    // Safe setup rejects as a duplicate owner (GS203/GS204), and the shared
    // signer stores one P-256 key per Safe. permissionless.js accepts such a
    // config and derives an address that can never be deployed.
    if (owners.whereType<WebAuthnAccountOwner>().length > 1) {
      throw ArgumentError(
        'A Safe supports at most one WebAuthn owner: '
        'SafeWebAuthnSharedSigner holds a single P-256 key per Safe',
      );
    }
  }

  /// The owner(s) of the Safe account.
  final List<AccountOwner> owners;

  /// The number of signatures required (threshold).
  ///
  /// Defaults to [owners.length] (all owners must sign), matching
  /// permissionless.js `toSafeSmartAccount`.
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

  /// Optional custom nonce key for parallel transaction support.
  final BigInt? nonceKey;

  /// Optional EntryPoint address override.
  final EthereumAddress? entryPointAddress;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthereumAddress? address;

  /// The ERC-7579 launchpad address for deploying modular Safe accounts.
  ///
  /// When provided, the Safe switches to ERC-7579 mode which:
  /// - Uses `encode7579Calls` instead of `executeUserOp` for call encoding
  /// - Enables module management (install/uninstall validators, executors, etc.)
  /// - Uses the launchpad for initial deployment with module configuration
  ///
  /// Use [Safe7579Addresses.erc7579LaunchpadAddress] for the default address.
  final EthereumAddress? erc7579LaunchpadAddress;

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
  final List<EthereumAddress> attesters;

  /// Minimum number of attester approvals required (ERC-7579 mode only).
  ///
  /// A module must be approved by at least this many attesters to be installed.
  final int attestersThreshold;

  /// Whether Safe setup is routed through MultiSend.
  ///
  /// When `true` (default), the Safe's `setup()` always delegatecalls MultiSend,
  /// even for a single setup transaction. When `false` AND there is exactly one
  /// setup transaction (e.g. just `enableModules`), `setup()` is called directly
  /// with the single call's `to`/`data` instead of wrapping through MultiSend.
  ///
  /// Set to `false` to produce CREATE2 addresses compatible with
  /// Safe Protocol Kit / relay-kit address derivation.
  ///
  /// This flag has no effect in ERC-7579 mode or when any WebAuthn owner is
  /// present (both force additional setup calls).
  final bool useMultiSendForSetup;

  /// Whether ERC-7579 mode is enabled.
  bool get isErc7579Enabled => erc7579LaunchpadAddress != null;
}

/// A Safe smart account implementation for ERC-4337.
class SafeSmartAccount
    implements
        SmartAccount,
        SmartAccountV06,
        DeploymentCallsEncoder,
        EntryPointVersioned {
  /// Creates a Safe smart account from the given configuration.
  ///
  /// Prefer using [createSafeSmartAccount] factory function instead
  /// of calling this constructor directly.
  SafeSmartAccount(this._config) : _addresses = _resolveAddresses(_config);

  final SafeSmartAccountConfig _config;
  final SafeAddresses _addresses;
  EthereumAddress? _cachedAddress;
  String? _cachedProxyCreationCode;

  /// Signatures carry no validity window (permissionless.js default
  /// `validAfter = validUntil = 0`).
  static const int _validAfter = 0;
  static const int _validUntil = 0;

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
  @override
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
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(entryPointVersion);

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

  @override
  bool get isWebAuthn => _hasWebAuthnOwner;

  /// Whether ERC-7579 mode is enabled.
  bool get isErc7579Enabled => _config.isErc7579Enabled;

  bool get _hasWebAuthnOwner =>
      _config.owners.any((owner) => owner is WebAuthnAccountOwner);

  /// The address that signs for [owner] in the Safe owner list.
  ///
  /// WebAuthn owners sign through the shared signer contract, so they appear
  /// as its address.
  EthereumAddress _signerAddress(AccountOwner owner) {
    if (owner is! WebAuthnAccountOwner) return owner.address;
    final sharedSigner = _addresses.webAuthnSharedSignerAddress;
    if (sharedSigner == null) {
      throw StateError(
        'WebAuthn owners require webAuthnSharedSignerAddress. '
        'WebAuthn is only supported on Safe v1.4.1/v1.5.0 with EntryPoint v0.7.',
      );
    }
    return sharedSigner;
  }

  /// Owners paired with their signer address, in the ascending signer order
  /// Safe's `checkSignatures` requires.
  List<(AccountOwner, EthereumAddress)> get _ownersBySigner => [
        for (final owner in _config.owners) (owner, _signerAddress(owner)),
      ]..sort((a, b) => a.$2.compareTo(b.$2));

  /// The module that validates UserOperations and is the SafeOp EIP-712
  /// verifying contract: the Safe7579 adapter in ERC-7579 mode, otherwise
  /// the Safe 4337 module.
  EthereumAddress get _safe4337ModuleAddress => isErc7579Enabled
      ? Safe7579Addresses.safe7579ModuleAddress
      : _addresses.safe4337ModuleAddress;

  /// The implementation the proxy is created with. In ERC-7579 mode that is
  /// the launchpad, which installs the Safe singleton during the first
  /// UserOperation.
  EthereumAddress get _proxySingleton =>
      _config.erc7579LaunchpadAddress ?? _addresses.safeSingletonAddress;

  /// Gets the deterministic address of this Safe account.
  ///
  /// The address is computed locally using the CREATE2 formula, which means
  /// it can be known before the account is actually deployed and works even
  /// for accounts that are already deployed.
  @override
  Future<EthereumAddress> getAddress() async => _cachedAddress ??=
      _config.address ?? _computeCreate2Address(await _getProxyCreationCode());

  /// Resolves proxy creation code for CREATE2 derivation.
  ///
  /// When a [SafeSmartAccountConfig.publicClient] is configured, reads
  /// `proxyCreationCode()` from the configured SafeProxyFactory (matching
  /// permissionless.js). Falls back to the canonical code for the configured
  /// [SafeVersion] when no client is available or the RPC call fails.
  Future<String> _getProxyCreationCode() async {
    if (_cachedProxyCreationCode != null) {
      return _cachedProxyCreationCode!;
    }

    final client = _config.publicClient;
    if (client != null) {
      try {
        final result = await client.call(
          Call(
            to: _addresses.safeProxyFactoryAddress,
            data: SafeSelectors.proxyCreationCode,
          ),
        );
        final code = _decodeReturnedBytes(result);
        if (code.length > 2) {
          return _cachedProxyCreationCode = code;
        }
      } catch (_) {
        // Fall back to the canonical code below.
      }
    }

    return _cachedProxyCreationCode = _proxyCreationCodes[_config.version]!;
  }

  /// Decodes a single ABI-encoded `bytes` return value from `eth_call`.
  static String _decodeReturnedBytes(String data) {
    final raw = Hex.decode(data);
    if (raw.length < 64) {
      throw ArgumentError('proxyCreationCode return data too short');
    }
    final offset = Hex.toBigInt(Hex.fromBytes(raw.sublist(0, 32))).toInt();
    if (offset + 32 > raw.length) {
      throw ArgumentError('proxyCreationCode return data offset out of range');
    }
    final length =
        Hex.toBigInt(Hex.fromBytes(raw.sublist(offset, offset + 32))).toInt();
    final start = offset + 32;
    final end = start + length;
    if (end > raw.length) {
      throw ArgumentError('proxyCreationCode return data truncated');
    }
    return Hex.fromBytes(raw.sublist(start, end));
  }

  /// Computes the Safe account address using the CREATE2 formula
  /// (permissionless.js `getAccountAddress`):
  ///
  /// - salt = keccak256(keccak256(initializer) ++ saltNonce)
  /// - bytecode = proxyCreationCode ++ uint256(singleton)
  /// - address = keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))[12:]
  EthereumAddress _computeCreate2Address(String proxyCreationCode) {
    final initializerHash = keccak256(Hex.decode(_getInitializer()));
    final salt = keccak256(
      Hex.decode(
        Hex.concat([
          Hex.fromBytes(initializerHash),
          Hex.fromBigInt(_config.saltNonce, byteLength: 32),
        ]),
      ),
    );
    final bytecodeHash = keccak256(
      Hex.decode(
        Hex.concat([
          proxyCreationCode,
          AbiEncoder.encodeAddress(_proxySingleton),
        ]),
      ),
    );
    final addressHash = keccak256(
      Hex.decode(
        Hex.concat([
          '0xff',
          _addresses.safeProxyFactoryAddress.hex,
          Hex.fromBytes(salt),
          Hex.fromBytes(bytecodeHash),
        ]),
      ),
    );
    return EthereumAddress(addressHash.sublist(12));
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
  /// launchpad InitData. The actual setup happens during the first UserOp.
  String _getInitializer() => isErc7579Enabled
      ? encodePreValidationSetup(
          initHash: safe7579InitHash(_safe7579InitData()),
          to: zeroAddress,
          preInit: '0x',
        )
      : _getStandardInitializer();

  String _getStandardInitializer() {
    final ownerAddresses = _config.owners.map(_signerAddress).toList();

    final setupCalls = <MultiSendCall>[
      MultiSendCall(
        to: _addresses.safeModuleSetupAddress,
        value: BigInt.zero,
        data: encodeEnableModules([_addresses.safe4337ModuleAddress]),
        operation: OperationType.delegateCall,
      ),
    ];

    // The WebAuthn owner's key is stored in the Safe's storage by
    // delegatecalling the shared signer's configure().
    final webAuthnOwner =
        _config.owners.whereType<WebAuthnAccountOwner>().firstOrNull;
    if (webAuthnOwner != null) {
      final p256Verifier = _addresses.safeP256VerifierAddress;
      if (p256Verifier == null) {
        throw StateError(
          'WebAuthn owners require safeP256VerifierAddress.',
        );
      }
      setupCalls.add(
        MultiSendCall(
          to: _signerAddress(webAuthnOwner),
          value: BigInt.zero,
          data: encodeWebAuthnSignerConfigure(
            x: webAuthnOwner.x,
            y: webAuthnOwner.y,
            p256VerifierAddress: p256Verifier.hex,
          ),
          operation: OperationType.delegateCall,
        ),
      );
    }

    // A single setup call may skip MultiSend (permissionless.js@0.3.5
    // `useMultiSendForSetup: false`), producing the CREATE2 address Safe
    // Protocol Kit / relay-kit derive.
    final callSetupDirectly =
        !_config.useMultiSendForSetup && setupCalls.length == 1;

    return encodeSafeSetup(
      owners: ownerAddresses,
      threshold: _config.threshold,
      to: callSetupDirectly
          ? setupCalls.single.to
          : _addresses.multiSendAddress,
      data: callSetupDirectly
          ? setupCalls.single.data
          : encodeMultiSendWithOperations(setupCalls),
      fallbackHandler: _addresses.safe4337ModuleAddress,
      paymentToken: zeroAddress,
      payment: BigInt.zero,
      paymentReceiver: zeroAddress,
    );
  }

  /// The launchpad InitData. Its hash goes into the initializer; the full
  /// struct, with the first UserOperation's [callData], into `setupSafe`.
  ///
  /// Validators are installed by `setupSafe`, the other modules by the
  /// `initSafe7579` setup call.
  Safe7579InitData _safe7579InitData({String callData = '0x'}) =>
      Safe7579InitData(
        singleton: _addresses.safeSingletonAddress,
        owners: _config.owners.map(_signerAddress).toList(),
        threshold: _config.threshold,
        setupTo: _config.erc7579LaunchpadAddress!,
        setupData: encodeInitSafe7579(
          safe7579: Safe7579Addresses.safe7579ModuleAddress,
          executors: _moduleInits(_config.executors),
          fallbacks: _moduleInits(_config.fallbacks),
          hooks: _moduleInits(_config.hooks),
          attesters: _config.attesters,
          threshold: _config.attestersThreshold,
        ),
        safe7579: Safe7579Addresses.safe7579ModuleAddress,
        validators: _moduleInits(_config.validators),
        callData: callData,
      );

  static List<(EthereumAddress, String)> _moduleInits(
    List<Safe7579ModuleInit> modules,
  ) =>
      [for (final m in modules) (m.module, m.initData)];

  /// Gets the init code for deploying this Safe account.
  ///
  /// This is used in the UserOperation when the account doesn't exist yet.
  @override
  Future<String> getInitCode() async {
    final (:factory, :factoryData) = (await getFactoryData())!;
    return Hex.concat([factory.hex, factoryData]);
  }

  /// Gets the factory address and data for UserOperation v0.7.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async => (
            factory: _addresses.safeProxyFactoryAddress,
            factoryData: encodeCreateProxyWithNonce(
              singleton: _proxySingleton,
              initializer: _getInitializer(),
              saltNonce: _config.saltNonce,
            ),
          );

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
  /// In standard mode, batches route through MultiSendCallOnly via DelegateCall
  /// (permissionless.js parity — call-only, no inner delegatecalls accepted).
  ///
  /// **Important for ERC-7579 deployment:** When deploying a Safe with ERC-7579 for the
  /// first time, use [encodeCallsForDeployment] instead. The launchpad requires
  /// the first UserOp to call `setupSafe()` with the full InitData.
  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }

    // Call vs batchcall mode by length (permissionless.js parity):
    // encode7579ExecuteBatch always emits batch mode.
    if (isErc7579Enabled) {
      return calls.length == 1
          ? encode7579Execute(calls.single)
          : encode7579ExecuteBatch(calls);
    }

    if (calls.length == 1) {
      return encodeCall(calls.single);
    }

    return encodeExecuteUserOp(
      to: _addresses.multiSendCallOnlyAddress,
      value: BigInt.zero,
      data: encodeMultiSend(calls),
      operation: OperationType.delegateCall.value,
    );
  }

  @override
  List<Call> decodeCalls(String callData) {
    // Same order and fall-through as permissionless.js decodeCalls; a
    // malformed setupSafe or 7579 payload ends in the executeUserOp error.
    try {
      return decodeSafeSetupSafe(callData);
    } catch (_) {}

    try {
      return decode7579Calls(callData).calls;
    } catch (_) {}

    return decodeSafeExecuteUserOp(
      callData,
      multiSendAddresses: {
        _addresses.multiSendAddress,
        _addresses.multiSendCallOnlyAddress,
      },
    );
  }

  @override
  Future<String> sign(String hash) => signMessage(hash);

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
  @override
  String encodeCallsForDeployment(List<Call> calls) {
    if (!isErc7579Enabled) {
      return encodeCalls(calls);
    }
    return encodeSetupSafe(_safe7579InitData(callData: encodeCalls(calls)));
  }

  /// Gets a stub signature for gas estimation.
  ///
  /// This returns a signature that has the correct format but
  /// with dummy data. Used by bundlers to estimate gas.
  @override
  String getStubSignature() => _withValidityWindow(
        _concatSignatures([
          for (final (owner, signer) in _ownersBySigner)
            if (owner is WebAuthnAccountOwner)
              (
                signer: signer,
                data: getDummySafeWebAuthnSignature(),
                isDynamic: true,
              )
            // Exercises the ecrecover path of checkSignatures (v = 0x1c),
            // not the approved-hash branch.
            else
              (signer: signer, data: ecdsaStubSignature, isDynamic: false),
        ]),
      );

  /// Signs a UserOperation for EntryPoint v0.7.
  ///
  /// Creates an EIP-712 signature over the v0.7 SafeOp typehash for
  /// `userOp.sender`. For v0.6 accounts, use [signUserOperationV06] instead.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    if (_config.entryPointVersion == EntryPointVersion.v06) {
      throw UnsupportedError(
        'Safe account configured for EntryPoint v0.6. '
        'Use signUserOperationV06 instead.',
      );
    }
    return _signSafeOpHash(_safeOpHashV07(userOp));
  }

  /// Signs a UserOperation for EntryPoint v0.6.
  ///
  /// Creates an EIP-712 signature over the v0.6 SafeOp typehash
  /// (uint256 gas fields, callGasLimit before verificationGasLimit),
  /// matching permissionless.js `EIP712_SAFE_OPERATION_TYPE_V06`.
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) async {
    if (_config.entryPointVersion != EntryPointVersion.v06) {
      throw UnsupportedError(
        'signUserOperationV06 requires EntryPoint v0.6. '
        'This account is configured for ${_config.entryPointVersion.name}.',
      );
    }
    return _signSafeOpHash(_safeOpHashV06(userOp));
  }

  /// Signs a SafeOp hash with all owners and packs validAfter/validUntil.
  ///
  /// ECDSA owners sign the raw EIP-712 hash.
  Future<String> _signSafeOpHash(String safeOpHash) async =>
      _withValidityWindow(
        await _signWithOwners(
          safeOpHash,
          (owner) => owner.signRawHash(safeOpHash),
        ),
      );

  /// Prefixes [signatures] with uint48 validAfter ‖ uint48 validUntil.
  static String _withValidityWindow(String signatures) => Hex.concat([
        Hex.fromBigInt(BigInt.from(_validAfter), byteLength: 6),
        Hex.fromBigInt(BigInt.from(_validUntil), byteLength: 6),
        signatures,
      ]);

  /// Signs [hash] with every owner in signer order and concatenates the
  /// Safe signatures. WebAuthn owners sign [hash] with P256; ECDSA owners
  /// sign via [ecdsaSign].
  Future<String> _signWithOwners(
    String hash,
    Future<String> Function(AccountOwner owner) ecdsaSign,
  ) async {
    final signatures = <_SignatureEntry>[];
    for (final (owner, signer) in _ownersBySigner) {
      if (owner is WebAuthnAccountOwner) {
        final p256 = await owner.signP256(hash);
        signatures.add(
          (
            signer: signer,
            data: encodeSafeWebAuthnSignature(p256),
            isDynamic: true,
          ),
        );
      } else {
        signatures.add(
          (signer: signer, data: await ecdsaSign(owner), isDynamic: false),
        );
      }
    }
    return _concatSignatures(signatures);
  }

  /// Signs a personal message (EIP-191) via SafeMessage EIP-712 wrapper.
  ///
  /// Matches permissionless.js: wrap as `SafeMessage(bytes)`, each ECDSA
  /// owner eth_signs the digest (v adjusted +4 → 31/32), then concatenate.
  /// In ERC-7579 mode the result is prefixed with 20 zero bytes.
  @override
  Future<String> signMessage(String message) async {
    _assertCanSignMessage();
    final accountAddress = await getAddress();
    final safeMessage =
        _buildSafeMessageTypedData(hashMessage(message), accountAddress);
    final safeMessageHash = hashTypedData(safeMessage);
    return _signSafeMessage(
      safeMessageHash: safeMessageHash,
      safeMessageTypedData: safeMessage,
      ethSign: true,
    );
  }

  /// Signs EIP-712 typed data via SafeMessage EIP-712 wrapper.
  ///
  /// Matches permissionless.js: wrap as `SafeMessage(bytes)` over the
  /// typed-data hash; ECDSA owners sign the SafeMessage typed data
  /// (v stays 27/28). In ERC-7579 mode the result is prefixed with 20 zero bytes.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    _assertCanSignMessage();
    final accountAddress = await getAddress();
    final safeMessage =
        _buildSafeMessageTypedData(hashTypedData(typedData), accountAddress);
    final safeMessageHash = hashTypedData(safeMessage);
    return _signSafeMessage(
      safeMessageHash: safeMessageHash,
      safeMessageTypedData: safeMessage,
      ethSign: false,
    );
  }

  /// permissionless.js checks the 7579 / v1.5.0 incompatibility only in
  /// signMessage/signTypedData, not when deploying or signing UserOperations.
  ///
  /// Its other guard there (fewer local owners than the threshold) cannot
  /// fail here: every owner signs locally and the config rejects a threshold
  /// above the owner count.
  void _assertCanSignMessage() {
    if (isErc7579Enabled && _config.version == SafeVersion.v1_5_0) {
      throw StateError('Safe 7579 & version 1.5.0 are not compatible');
    }
  }

  /// Builds the SafeMessage EIP-712 typed data for [innerHash].
  ///
  /// [accountAddress] is the Safe account (not the 4337 module).
  TypedData _buildSafeMessageTypedData(
    String innerHash,
    EthereumAddress accountAddress,
  ) =>
      TypedData(
        domain: TypedDataDomain(
          chainId: _config.chainId,
          verifyingContract: accountAddress,
        ),
        types: {
          'SafeMessage': [
            const TypedDataField(name: 'message', type: 'bytes'),
          ],
        },
        primaryType: 'SafeMessage',
        message: {'message': innerHash},
      );

  /// Signs a SafeMessage hash with all owners and concatenates signatures.
  ///
  /// When [ethSign] is true (signMessage path), ECDSA owners use personal_sign
  /// and V is adjusted +4. When false (signTypedData path), they sign the
  /// SafeMessage typed data directly and V stays 27/28.
  Future<String> _signSafeMessage({
    required String safeMessageHash,
    required TypedData safeMessageTypedData,
    required bool ethSign,
  }) async {
    final signatureBytes = await _signWithOwners(
      safeMessageHash,
      (owner) async => _adjustVInSignature(
        ethSign
            ? await owner.signPersonalMessage(safeMessageHash)
            : await owner.signTypedData(safeMessageTypedData),
        ethSign: ethSign,
      ),
    );

    // ERC-7579 mode prefixes with zero address (permissionless.js)
    if (isErc7579Enabled) {
      return Hex.concat([Hex.fromBytes(Uint8List(20)), signatureBytes]);
    }

    return signatureBytes;
  }

  /// Adjusts the V byte of a 65-byte ECDSA signature for Safe.
  ///
  /// - eth_sign: normalize to 27/28 then add 4 → 31/32
  /// - eth_signTypedData: normalize to 27/28 only
  String _adjustVInSignature(String signature, {required bool ethSign}) {
    final hex = Hex.strip0x(signature);
    if (hex.length != 130) {
      throw ArgumentError(
        'Expected 65-byte ECDSA signature, got ${hex.length ~/ 2} bytes',
      );
    }
    var v = int.parse(hex.substring(128, 130), radix: 16);
    if (v != 0 && v != 1 && v != 27 && v != 28) {
      throw ArgumentError('Invalid signature V value: $v');
    }
    if (v < 27) {
      v += 27;
    }
    if (ethSign) {
      v += 4;
    }
    return '0x${hex.substring(0, 128)}${v.toRadixString(16).padLeft(2, '0')}';
  }

  /// The SafeOp EIP-712 hash for EntryPoint v0.7.
  String _safeOpHashV07(UserOperationV07 userOp) {
    final paymasterAndData = packing.getPaymasterAndData(userOp);
    // hashTypedData does not range-check uintN; packing the gas fields
    // rejects values outside the module's uint128 fields.
    packing.getAccountGasLimits(userOp);
    packing.getGasFees(userOp);
    return hashTypedData(
      _safeOpTypedData(_safeOpFieldsV07, {
        'safe': userOp.sender,
        'nonce': userOp.nonce,
        'initCode': packing.getInitCode(userOp),
        'callData': userOp.callData,
        'verificationGasLimit': userOp.verificationGasLimit,
        'callGasLimit': userOp.callGasLimit,
        'preVerificationGas': userOp.preVerificationGas,
        'maxPriorityFeePerGas': userOp.maxPriorityFeePerGas,
        'maxFeePerGas': userOp.maxFeePerGas,
        'paymasterAndData': paymasterAndData,
      }),
    );
  }

  /// The SafeOp EIP-712 hash for EntryPoint v0.6.
  String _safeOpHashV06(UserOperationV06 userOp) => hashTypedData(
        _safeOpTypedData(_safeOpFieldsV06, {
          'safe': userOp.sender,
          'nonce': userOp.nonce,
          'initCode': userOp.initCode,
          'callData': userOp.callData,
          'callGasLimit': userOp.callGasLimit,
          'verificationGasLimit': userOp.verificationGasLimit,
          'preVerificationGas': userOp.preVerificationGas,
          'maxFeePerGas': userOp.maxFeePerGas,
          'maxPriorityFeePerGas': userOp.maxPriorityFeePerGas,
          'paymasterAndData': userOp.paymasterAndData,
        }),
      );

  /// SafeOp typed data over [fields] with the validity window and
  /// EntryPoint filled in.
  ///
  /// The verifying contract is the 4337 module, not the Safe: the Safe's
  /// fallback handler reaches the module with `call`, so the module's
  /// `domainSeparator()` runs with `this` = module.
  TypedData _safeOpTypedData(
    List<TypedDataField> fields,
    Map<String, Object> message,
  ) =>
      TypedData(
        domain: TypedDataDomain(
          chainId: _config.chainId,
          verifyingContract: _safe4337ModuleAddress,
        ),
        types: {'SafeOp': fields},
        primaryType: 'SafeOp',
        message: {
          ...message,
          'validAfter': _validAfter,
          'validUntil': _validUntil,
          'entryPoint': entryPoint,
        },
      );
}

/// permissionless.js `EIP712_SAFE_OPERATION_TYPE_V07`: uint128 gas fields,
/// verificationGasLimit before callGasLimit.
const _safeOpFieldsV07 = [
  TypedDataField(name: 'safe', type: 'address'),
  TypedDataField(name: 'nonce', type: 'uint256'),
  TypedDataField(name: 'initCode', type: 'bytes'),
  TypedDataField(name: 'callData', type: 'bytes'),
  TypedDataField(name: 'verificationGasLimit', type: 'uint128'),
  TypedDataField(name: 'callGasLimit', type: 'uint128'),
  TypedDataField(name: 'preVerificationGas', type: 'uint256'),
  TypedDataField(name: 'maxPriorityFeePerGas', type: 'uint128'),
  TypedDataField(name: 'maxFeePerGas', type: 'uint128'),
  TypedDataField(name: 'paymasterAndData', type: 'bytes'),
  TypedDataField(name: 'validAfter', type: 'uint48'),
  TypedDataField(name: 'validUntil', type: 'uint48'),
  TypedDataField(name: 'entryPoint', type: 'address'),
];

/// permissionless.js `EIP712_SAFE_OPERATION_TYPE_V06`: uint256 gas fields,
/// callGasLimit before verificationGasLimit and maxFeePerGas before
/// maxPriorityFeePerGas.
const _safeOpFieldsV06 = [
  TypedDataField(name: 'safe', type: 'address'),
  TypedDataField(name: 'nonce', type: 'uint256'),
  TypedDataField(name: 'initCode', type: 'bytes'),
  TypedDataField(name: 'callData', type: 'bytes'),
  TypedDataField(name: 'callGasLimit', type: 'uint256'),
  TypedDataField(name: 'verificationGasLimit', type: 'uint256'),
  TypedDataField(name: 'preVerificationGas', type: 'uint256'),
  TypedDataField(name: 'maxFeePerGas', type: 'uint256'),
  TypedDataField(name: 'maxPriorityFeePerGas', type: 'uint256'),
  TypedDataField(name: 'paymasterAndData', type: 'bytes'),
  TypedDataField(name: 'validAfter', type: 'uint48'),
  TypedDataField(name: 'validUntil', type: 'uint48'),
  TypedDataField(name: 'entryPoint', type: 'address'),
];

/// One owner's signature for Safe `checkSignatures`. [isDynamic] marks a
/// contract (EIP-1271) signature, e.g. from the WebAuthn shared signer.
typedef _SignatureEntry = ({
  EthereumAddress signer,
  String data,
  bool isDynamic,
});

/// Concatenates Safe signatures in ascending signer order.
///
/// ECDSA signatures (65 bytes) are appended as they are. A contract
/// signature takes a 65-byte static slot
/// {signer(32)}{offset of its dynamic part(32)}{signature type 0x00(1)}
/// and appends {length(32)}{data} after all static slots.
String _concatSignatures(List<_SignatureEntry> signatures) {
  final sorted = [...signatures]..sort((a, b) => a.signer.compareTo(b.signer));
  final dynamicStart = sorted.length * 65;
  final statics = <String>[];
  final dynamics = <String>[];
  var dynamicLength = 0;

  for (final sig in sorted) {
    if (!sig.isDynamic) {
      statics.add(sig.data);
      continue;
    }
    final dataLength = Hex.byteLength(sig.data);
    statics.addAll([
      AbiEncoder.encodeAddress(sig.signer),
      Hex.fromBigInt(BigInt.from(dynamicStart + dynamicLength), byteLength: 32),
      '0x00',
    ]);
    dynamics.addAll([
      Hex.fromBigInt(BigInt.from(dataLength), byteLength: 32),
      sig.data,
    ]);
    dynamicLength += 32 + dataLength;
  }

  return Hex.concat([...statics, ...dynamics]);
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
///
/// ## Safe Protocol Kit compatibility
///
/// To produce a CREATE2 address that matches Safe Protocol Kit / relay-kit
/// derivation, set `useMultiSendForSetup: false`. This only affects the
/// counterfactual address when there is exactly one setup transaction
/// (the default configuration with no WebAuthn owners and no ERC-7579 modules).
///
/// ```dart
/// final account = createSafeSmartAccount(
///   owners: [PrivateKeyOwner('0x...')],
///   chainId: BigInt.from(1),
///   useMultiSendForSetup: false,
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
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
  EthereumAddress? erc7579LaunchpadAddress,
  List<Safe7579ModuleInit> validators = const [],
  List<Safe7579ModuleInit> executors = const [],
  List<Safe7579ModuleInit> fallbacks = const [],
  List<Safe7579ModuleInit> hooks = const [],
  List<EthereumAddress> attesters = const [],
  int attestersThreshold = 0,
  bool useMultiSendForSetup = true,
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
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
        erc7579LaunchpadAddress: erc7579LaunchpadAddress,
        validators: validators,
        executors: executors,
        fallbacks: fallbacks,
        hooks: hooks,
        attesters: attesters,
        attestersThreshold: attestersThreshold,
        useMultiSendForSetup: useMultiSendForSetup,
      ),
    );
