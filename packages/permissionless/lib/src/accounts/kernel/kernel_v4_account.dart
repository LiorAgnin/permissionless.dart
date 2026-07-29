import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/erc7579.dart';
import '../../utils/kernel_v4/kernel_v4.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import 'constants.dart';

/// Shared behavior of the factory-deployed Kernel v4 accounts
/// (`KernelUUPS` and `KernelImmutableECDSA`).
///
/// Both variants share the KernelFactory / CREATE2 deployment path, ERC-7579
/// execute encoding, and the root signing scheme (raw 65-byte `r‖s‖v` over
/// the EntryPoint v0.9 userOpHash — routing lives in the nonce, not the
/// signature). They differ only in where the account's identity lives:
/// packages[0] root install (UUPS) vs proxy immutable args (ImmutableECDSA)
/// — which is exactly the [getAddress] / [getFactoryData] surface subclasses
/// implement.
///
/// Not exported: this is an implementation detail of the two public account
/// types, per the ticket 07 code-shape decision.
abstract class KernelV4AccountBase implements SmartAccount {
  /// The account owner used for root signing.
  AccountOwner get owner;

  /// The Kernel version (always a v4 version; enforced by the configs).
  KernelVersion get version;

  /// Optional EntryPoint address override for forked or pre-release
  /// EntryPoint v0.9 deployments.
  EthereumAddress? get entryPointOverride;

  /// Optional custom 2-byte parallel nonce key.
  BigInt? get customNonceKey;

  /// The EntryPoint version this account targets — always v0.9 for Kernel v4.
  EntryPointVersion get entryPointVersion => version.entryPointVersion;

  @override
  EthereumAddress get entryPoint =>
      entryPointOverride ?? EntryPointAddresses.v09;

  @override
  bool get isWebAuthn => false;

  @override
  BigInt get nonceKey => encodeKernelV4NonceKey(nonceKey: customNonceKey);

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
  String encodeCall(Call call) => encode7579Execute(call);

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

  @override
  List<Call> decodeCalls(String callData) => decode7579Calls(callData).calls;

  @override
  String getStubSignature() => kernelDummyEcdsaSignature;

  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = getUserOperationHash(
      userOperation: userOp,
      entryPointAddress: entryPoint,
      entryPointVersion: entryPointVersion,
      chainId: chainId,
    );
    // The root validation path recovers the signer over the raw EIP-712
    // userOpHash digest (no EIP-191 personal-message prefix), and the
    // root/fallback signature carries no mode or validator prefix.
    return owner.signRawHash(userOpHash);
  }

  @override
  Future<String> sign(String hash) => throw UnsupportedError(
        'Kernel v4 ERC-1271 signing uses ERC-7739 nested EIP-712 and is not '
        'implemented yet',
      );

  @override
  Future<String> signMessage(String message) => throw UnsupportedError(
        'Kernel v4 ERC-1271 message signing uses ERC-7739 nested EIP-712 and '
        'is not implemented yet',
      );

  @override
  Future<String> signTypedData(TypedData typedData) => throw UnsupportedError(
        'Kernel v4 ERC-1271 typed-data signing uses ERC-7739 nested EIP-712 '
        'and is not implemented yet',
      );
}
