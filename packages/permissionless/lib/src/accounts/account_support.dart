import '../clients/public/public_client.dart';
import '../types/address.dart';
import '../types/eip7702.dart';
import '../types/user_operation.dart';

/// 65-byte ECDSA-shaped dummy signature accepted by bundler simulation
/// (permissionless.js `getDummySignature` for ECDSA owners).
const String ecdsaStubSignature =
    '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

/// The v0.6 `initCode` (`factory ‖ factoryData`) for an account's
/// [factoryData], or `0x` when it has no factory.
Future<String> initCodeFromFactory(
  Future<({EthereumAddress factory, String factoryData})?> factoryData,
) async {
  final data = await factoryData;
  return packUserOperationInitCode(
    factory: data?.factory,
    factoryData: data?.factoryData,
  );
}

/// The counterfactual address of a factory-deployed account.
///
/// Uses [address] when the caller supplied it; otherwise asks the
/// EntryPoint via `getSenderAddress` with the account's [initCode].
Future<EthereumAddress> resolveCounterfactualAddress({
  required String accountName,
  required EthereumAddress? address,
  required PublicClient? publicClient,
  required EthereumAddress entryPoint,
  required Future<String> Function() initCode,
}) async {
  if (address != null) return address;
  if (publicClient == null) {
    throw StateError(
      '$accountName account address cannot be computed without a client. '
      'Either provide `address` or `publicClient` when creating the account.',
    );
  }
  return publicClient.getSenderAddress(
    initCode: await initCode(),
    entryPoint: entryPoint,
  );
}

/// Throws [UnsupportedError] when [userOperation] is not the layout an
/// account on [entryPointVersion] signs: [UserOperationV06] for v0.6,
/// [UserOperationV07] for v0.7 and v0.8.
void checkUserOperationLayout({
  required String accountName,
  required EntryPointVersion entryPointVersion,
  required UserOperation userOperation,
}) {
  switch ((entryPointVersion, userOperation)) {
    case (EntryPointVersion.v06, UserOperationV06()):
    case (EntryPointVersion.v07 || EntryPointVersion.v08, UserOperationV07()):
      return;
    case (EntryPointVersion.v06, _):
      throw UnsupportedError(
        '$accountName account configured for EntryPoint v0.6. '
        'Use signUserOperationV06 instead.',
      );
    case _:
      throw UnsupportedError(
        'signUserOperationV06 requires EntryPoint v0.6. '
        'This account is configured for ${entryPointVersion.name}.',
      );
  }
}

/// Throws [StateError] when the EIP-7702 account at [address] has no code
/// yet: before its delegation is on chain the EOA can't run ERC-1271
/// `isValidSignature`, so a message signature would not verify.
///
/// Without a [publicClient] the check is skipped and signing proceeds
/// unchecked, so offline signers keep working; such a signature verifies
/// only once the delegation is active.
Future<void> ensureEip7702Delegated({
  required String accountName,
  required PublicClient? publicClient,
  required Future<EthereumAddress> Function() address,
}) async {
  if (publicClient == null) return;
  if (!await publicClient.isDeployed(await address())) {
    throw StateError(
      '$accountName is not EIP-1271 compliant before delegation. '
      'Submit a UserOperation with the EIP-7702 authorization first.',
    );
  }
}
