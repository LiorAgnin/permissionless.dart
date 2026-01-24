import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';

/// Abstract interface for ERC-4337 smart accounts.
///
/// Implement this interface to enable use with [SmartAccountClient].
/// The library provides [SafeSmartAccount] as a built-in implementation.
///
/// Example custom implementation:
/// ```dart
/// class MyCustomAccount implements SmartAccount {
///   @override
///   Future<EthereumAddress> getAddress() async => ...;
///
///   // ... implement other methods
/// }
/// ```
abstract class SmartAccount {
  /// Creates a [SmartAccount].
  ///
  /// Implementations provide account-specific logic for address computation,
  /// call encoding, and UserOperation signing.
  const SmartAccount();

  /// Gets the deterministic address of this account.
  ///
  /// For CREATE2-based accounts, this can be computed before deployment.
  Future<EthereumAddress> getAddress();

  /// Gets the init code for deploying this account.
  ///
  /// Returns '0x' if the account is already deployed or doesn't need
  /// deployment data.
  Future<String> getInitCode();

  /// Gets the factory address and data for UserOperation v0.7.
  ///
  /// Returns null if the account is already deployed.
  Future<({EthereumAddress factory, String factoryData})?> getFactoryData();

  /// Encodes a single call for execution by this account.
  String encodeCall(Call call);

  /// Encodes multiple calls for batch execution.
  ///
  /// Implementations typically use MultiSend or similar patterns.
  String encodeCalls(List<Call> calls);

  /// Gets a stub signature for gas estimation.
  ///
  /// This should return a signature with the correct format but
  /// placeholder values, used by bundlers for gas estimation.
  String getStubSignature();

  /// Signs a UserOperation with this account's owner(s).
  ///
  /// Returns the signature to include in the UserOperation.
  Future<String> signUserOperation(UserOperationV07 userOp);

  /// Signs a personal message (EIP-191).
  ///
  /// The message is hashed using the Ethereum personal message format:
  /// `keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)`
  ///
  /// Returns the signature as a hex string.
  ///
  /// Example:
  /// ```dart
  /// final signature = await account.signMessage('Hello, World!');
  /// ```
  Future<String> signMessage(String message);

  /// Signs EIP-712 typed data.
  ///
  /// The typed data is hashed using the EIP-712 format:
  /// `keccak256("\x19\x01" + domainSeparator + hashStruct(message))`
  ///
  /// Returns the signature as a hex string.
  ///
  /// Example:
  /// ```dart
  /// final typedData = TypedData(
  ///   domain: TypedDataDomain(name: 'My App', version: '1'),
  ///   types: {'Message': [TypedDataField(name: 'content', type: 'string')]},
  ///   primaryType: 'Message',
  ///   message: {'content': 'Hello'},
  /// );
  /// final signature = await account.signTypedData(typedData);
  /// ```
  Future<String> signTypedData(TypedData typedData);

  /// The chain ID this account is configured for.
  BigInt get chainId;

  /// The EntryPoint address this account uses.
  EthereumAddress get entryPoint;

  /// The nonce key for parallel transaction support.
  ///
  /// Defaults to 0 for sequential transactions.
  BigInt get nonceKey;

  /// Whether this account uses WebAuthn/Passkey authentication.
  ///
  /// WebAuthn accounts require P256 signature verification which costs
  /// approximately 800k gas on-chain without the RIP-7212 precompile.
  /// This flag enables automatic gas adjustments in SmartAccountClient.
  ///
  /// Override to return true in account implementations that use
  /// WebAuthn owners (passkeys).
  bool get isWebAuthn => false;
}

/// Abstract interface for ERC-4337 v0.6 smart accounts.
///
/// This interface is for accounts that use EntryPoint v0.6.
/// For v0.7 accounts, use [SmartAccount] instead.
abstract class SmartAccountV06 implements SmartAccount {
  /// Creates a [SmartAccountV06].
  ///
  /// Implementations provide v0.6-specific UserOperation signing.
  const SmartAccountV06();

  /// Signs a UserOperation v0.6 with this account's owner(s).
  ///
  /// Returns the signature to include in the UserOperation.
  Future<String> signUserOperationV06(UserOperationV06 userOp);
}

/// Marker interface for EIP-7702 enabled smart accounts.
///
/// EIP-7702 accounts use code delegation from an EOA to a smart contract,
/// allowing EOAs to function as smart accounts without deploying a
/// separate contract.
///
/// Key characteristics:
/// - Account address equals the owner's EOA address
/// - No factory deployment needed (`getFactoryData()` returns null)
/// - Requires EIP-7702 authorization to be included in transactions
/// - Uses EntryPoint v0.8
///
/// Example:
/// ```dart
/// if (account is Eip7702SmartAccount) {
///   final auth = await account.getAuthorization(nonce: eoaNonce);
///   // Include auth in bundler request
/// }
/// ```
abstract class Eip7702SmartAccount implements SmartAccount {
  /// Creates an [Eip7702SmartAccount].
  ///
  /// Implementations provide EIP-7702 code delegation logic, where the
  /// account address equals the owner's EOA address.
  const Eip7702SmartAccount();

  /// The smart contract address that code is delegated to.
  ///
  /// This is the implementation contract that the EOA will execute code from
  /// when the EIP-7702 authorization is active.
  EthereumAddress get accountLogicAddress;

  /// Whether this account uses EIP-7702 code delegation.
  ///
  /// Always returns true for Eip7702SmartAccount implementations.
  bool get isEip7702 => true;

  /// Creates an EIP-7702 authorization for this account.
  ///
  /// The authorization must be included in the transaction that submits
  /// the UserOperation to enable the EOA to execute smart account code.
  ///
  /// [nonce] should be the EOA's current transaction nonce.
  ///
  /// Example:
  /// ```dart
  /// final nonce = await publicClient.getTransactionCount(ownerAddress);
  /// final auth = await account.getAuthorization(nonce: nonce);
  /// ```
  Future<Eip7702Authorization> getAuthorization({required BigInt nonce});
}
