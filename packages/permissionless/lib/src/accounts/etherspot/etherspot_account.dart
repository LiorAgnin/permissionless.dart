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
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../account_support.dart';
import '../erc7579_calls.dart';
import 'constants.dart';

/// Configuration for creating an Etherspot smart account.
class EtherspotSmartAccountConfig {
  /// Creates a configuration for an Etherspot modular smart account.
  ///
  /// - [owner]: The account owner who controls the account
  /// - [chainId]: Chain ID for the network
  /// - [index]: Salt for deterministic address generation (defaults to 0)
  /// - [customAddresses]: Optional custom contract addresses
  /// - [nonceKey]: User nonce key (2-byte suffix in the 24-byte encoding)
  /// - [entryPointAddress]: Override the canonical EntryPoint v0.7 address
  /// - [publicClient]: For RPC-based address computation (recommended)
  /// - [address]: Pre-computed address (alternative to publicClient)
  EtherspotSmartAccountConfig({
    required this.owner,
    required this.chainId,
    BigInt? index,
    this.customAddresses,
    this.nonceKey,
    this.entryPointAddress,
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

  /// Optional user nonce key (encoded as a 2-byte suffix).
  final BigInt? nonceKey;

  /// Optional EntryPoint address override.
  final EthereumAddress? entryPointAddress;

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
  /// Creates custom contract addresses for Etherspot deployment.
  ///
  /// All fields are optional; defaults are used for any not provided.
  const EtherspotCustomAddresses({
    this.factory,
    this.bootstrap,
    this.ecdsaValidator,
  });

  /// Custom factory address for account deployment.
  final EthereumAddress? factory;

  /// Custom bootstrap contract address for initialization.
  final EthereumAddress? bootstrap;

  /// Custom ECDSA validator module address.
  final EthereumAddress? ecdsaValidator;
}

/// Etherspot ModularEtherspotWallet smart account implementation.
///
/// This implements the ERC-4337 smart account interface for Etherspot's
/// modular wallet. It uses ERC-7579 for call encoding and EntryPoint v0.7.
class EtherspotSmartAccount implements SmartAccount {
  /// Creates an Etherspot smart account from the given configuration.
  ///
  /// Prefer using [createEtherspotSmartAccount] factory function instead
  /// of calling this constructor directly.
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
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ?? EntryPointAddresses.v07;

  /// permissionless.js `getNonceKeyWithEncoding`: validator (20) ‖
  /// mode DEFAULT (1) ‖ type ROOT (1) ‖ nonce key (2).
  @override
  BigInt get nonceKey => Hex.toBigInt(
        Hex.concat([
          ecdsaValidator.hex,
          '0x00',
          '0x00',
          Hex.fromBigInt(_config.nonceKey ?? BigInt.zero, byteLength: 2),
        ]),
      );

  @override
  bool get isWebAuthn => false;

  @override
  Future<EthereumAddress> getAddress() async =>
      _cachedAddress ??= await resolveCounterfactualAddress(
        accountName: 'Etherspot',
        address: _config.address,
        publicClient: _config.publicClient,
        entryPoint: entryPoint,
        initCode: getInitCode,
      );

  @override
  Future<String> getInitCode() async {
    final factoryData = await getFactoryData();
    return packUserOperationInitCode(
      factory: factoryData?.factory,
      factoryData: factoryData?.factoryData,
    );
  }

  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async => (
            factory: factory,
            factoryData: AbiEncoder.encodeFunctionData(
              etherspotCreateAccountSignature,
              [Hex.fromBigInt(index, byteLength: 32), _encodeInitCode()],
            ),
          );

  /// `abi.encode(owner, bootstrap, initMSA(...))`.
  String _encodeInitCode() => AbiEncoder.encodeParameters(
        ['address', 'address', 'bytes'],
        [owner.address, bootstrap, _encodeInitMSA()],
      );

  /// `initMSA(validators, executors, hook, fallbacks)` with
  /// `BootstrapConfig = (address module, bytes data)`. Like permissionless.js,
  /// installs the ECDSA validator and zero-address executor, hook and
  /// fallback, each with `onInstall(0x)`.
  String _encodeInitMSA() {
    final onInstall =
        AbiEncoder.encodeFunctionData(etherspotOnInstallSignature, ['0x']);
    return AbiEncoder.encodeFunctionData(
      etherspotInitMsaSignature,
      [
        [
          [ecdsaValidator, onInstall],
        ],
        [
          [zeroAddress, onInstall],
        ],
        [zeroAddress, onInstall],
        [
          [zeroAddress, onInstall],
        ],
      ],
    );
  }

  @override
  String encodeCall(Call call) => encode7579Execute(call);

  @override
  String encodeCalls(List<Call> calls) => encodeErc7579AccountCalls(calls);

  @override
  List<Call> decodeCalls(String callData) => decode7579Calls(callData).calls;

  @override
  Future<String> sign(String hash) => signMessage(hash);

  @override
  String getStubSignature() => etherspotDummyEcdsaSignature;

  /// Signs the v0.7 userOpHash with EIP-191. Unlike [signMessage] /
  /// [signTypedData], the signature carries no validator prefix.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) =>
      owner.signPersonalMessage(
        getUserOperationHash(
          userOperation: userOp,
          entryPointAddress: entryPoint,
          entryPointVersion: EntryPointVersion.v07,
          chainId: chainId,
        ),
      );

  /// Signs a personal message (EIP-191).
  ///
  /// Returns signature with validator prefix.
  @override
  Future<String> signMessage(String message) async {
    // hashMessage already applies the EIP-191 prefix; sign that digest raw
    // (matches viem localOwner.signMessage — one prefix only).
    final signature = await owner.signRawHash(hashMessage(message));
    return Hex.concat([ecdsaValidator.hex, signature]);
  }

  /// Signs EIP-712 typed data.
  ///
  /// Returns signature with validator prefix.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final signature = await owner.signTypedData(typedData);
    return Hex.concat([ecdsaValidator.hex, signature]);
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
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
  EthereumAddress? address,
  PublicClient? publicClient,
}) =>
    EtherspotSmartAccount(
      EtherspotSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        index: index,
        customAddresses: customAddresses,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        address: address,
        publicClient: publicClient,
      ),
    );
