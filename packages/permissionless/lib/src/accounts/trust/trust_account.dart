import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../../utils/message_hash.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../account_support.dart';
import '../standard_execute.dart';
import '../wrapped_message.dart';
import 'constants.dart';

/// Configuration for creating a Trust smart account.
class TrustSmartAccountConfig {
  /// Creates a configuration for a Trust (Barz) smart account.
  ///
  /// Trust uses a diamond-based architecture and only supports EntryPoint v0.6.
  ///
  /// - [owner]: The account owner who controls the account
  /// - [chainId]: Chain ID for the network
  /// - [index]: Salt for deterministic address generation (defaults to 0)
  /// - [customVerificationFacetAddress]: Custom verification facet address
  /// - [nonceKey]: Custom nonce key for parallel transaction support
  /// - [entryPointAddress]: Override the canonical EntryPoint v0.6 address
  /// - [publicClient]: For RPC-based address computation (recommended)
  /// - [address]: Pre-computed address (alternative to publicClient)
  TrustSmartAccountConfig({
    required this.owner,
    required this.chainId,
    BigInt? index,
    this.customFactoryAddress,
    this.customVerificationFacetAddress,
    this.nonceKey,
    this.entryPointAddress,
    this.publicClient,
    this.address,
  }) : index = index ?? BigInt.zero;

  /// The owner of this Trust account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Salt/index for deterministic address generation.
  final BigInt index;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom verification facet address.
  final EthereumAddress? customVerificationFacetAddress;

  /// Optional custom nonce key.
  final BigInt? nonceKey;

  /// Optional EntryPoint address override (defaults to v0.6 canonical).
  final EthereumAddress? entryPointAddress;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthereumAddress? address;
}

/// A Trust (Barz) smart account implementation for ERC-4337 v0.6.
///
/// Trust Wallet's smart account uses a diamond-based architecture with
/// verification facets. This implementation only supports EntryPoint v0.6.
///
/// Example:
/// ```dart
/// final account = createTrustSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Trust account: $address');
/// ```
class TrustSmartAccount implements SmartAccountV06, EntryPointVersioned {
  /// Creates a Trust smart account from the given configuration.
  ///
  /// Prefer using [createTrustSmartAccount] factory function instead
  /// of calling this constructor directly.
  TrustSmartAccount(this._config)
      : _factoryAddress =
            _config.customFactoryAddress ?? TrustAddresses.factory,
        _verificationFacetAddress = _config.customVerificationFacetAddress ??
            TrustAddresses.secp256k1VerificationFacet;

  final TrustSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  final EthereumAddress _verificationFacetAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The index/salt used for address derivation.
  BigInt get index => _config.index;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint version (always v0.6 for Trust).
  @override
  EntryPointVersion get entryPointVersion => EntryPointVersion.v06;

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

  /// Gets the deterministic address of this Trust account.
  ///
  /// Uses the configured `address`, otherwise asks the EntryPoint via
  /// [PublicClient.getSenderAddress].
  @override
  Future<EthereumAddress> getAddress() async =>
      _cachedAddress ??= await resolveCounterfactualAddress(
        accountName: 'Trust',
        address: _config.address,
        publicClient: _config.publicClient,
        entryPoint: entryPoint,
        initCode: getInitCode,
      );

  /// Gets the init code for deploying this Trust account.
  @override
  Future<String> getInitCode() async => packUserOperationInitCode(
        factory: _factoryAddress,
        factoryData: _createAccountData(),
      );

  /// Gets the factory address and data for UserOperation v0.7.
  ///
  /// Note: Trust only supports v0.6, so this returns v0.6-compatible format.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async =>
          (factory: _factoryAddress, factoryData: _createAccountData());

  /// `createAccount(address _verificationFacet, bytes _owner, uint256 _salt)`.
  ///
  /// `_owner` is the 20-byte owner address (not the public key the Barz docs
  /// describe), matching permissionless.js.
  String _createAccountData() => AbiEncoder.encodeFunctionData(
        'createAccount(address,bytes,uint256)',
        [_verificationFacetAddress, _config.owner.address.hex, _config.index],
      );

  /// Encodes a single call as `execute(address,uint256,bytes)`.
  @override
  String encodeCall(Call call) => encodeExecute(call);

  /// Encodes multiple calls as `executeBatch(address[],uint256[],bytes[])`.
  @override
  String encodeCalls(List<Call> calls) =>
      encodeExecuteCalls(calls, ExecuteBatchAbi.addressesValuesAndBytes);

  @override
  List<Call> decodeCalls(String callData) =>
      decodeExecuteCalls(callData, ExecuteBatchAbi.addressesValuesAndBytes);

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() => ecdsaStubSignature;

  /// Signs a UserOperation v0.7.
  ///
  /// Note: Trust only supports v0.6. Use signUserOperationV06 instead.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async =>
      throw UnsupportedError(
        'Trust Smart Account only supports EntryPoint v0.6. '
        'Use signUserOperationV06 instead.',
      );

  /// Signs a UserOperation v0.6.
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) async =>
      _config.owner.signPersonalMessage(
        getUserOperationHash(
          userOperation: userOp,
          entryPointAddress: entryPoint,
          entryPointVersion: entryPointVersion,
          chainId: _config.chainId,
        ),
      );

  /// Signs a personal message (EIP-191) with Barz wrapper.
  @override
  Future<String> signMessage(String message) =>
      _signWithBarzWrapper(hashMessage(message));

  /// Signs EIP-712 typed data with Barz wrapper.
  @override
  Future<String> signTypedData(TypedData typedData) =>
      _signWithBarzWrapper(hashTypedData(typedData));

  /// Signs [hashedMessage] through the BarzMessage EIP-712 wrapper.
  Future<String> _signWithBarzWrapper(String hashedMessage) async =>
      // Sign the Barz EIP-712 digest raw (no EIP-191 prefix). Matches
      // permissionless.js which uses signer.signTypedData on the wrapper.
      _config.owner.signTypedData(
        wrappedMessageTypedData(
          domainName: 'Barz',
          domainVersion: 'v0.2.0',
          chainId: _config.chainId,
          verifyingContract: await getAddress(),
          primaryType: 'BarzMessage',
          message: hashedMessage,
        ),
      );
}

/// Creates a Trust (Barz) smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Trust accounts only support EntryPoint v0.6.
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createTrustSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Trust account: $address');
/// ```
TrustSmartAccount createTrustSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  BigInt? index,
  EthereumAddress? customFactoryAddress,
  EthereumAddress? customVerificationFacetAddress,
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    TrustSmartAccount(
      TrustSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        index: index,
        customFactoryAddress: customFactoryAddress,
        customVerificationFacetAddress: customVerificationFacetAddress,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );
