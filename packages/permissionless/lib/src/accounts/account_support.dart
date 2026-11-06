import '../clients/public/public_client.dart';
import '../types/address.dart';
import '../types/user_operation.dart';

/// 65-byte ECDSA-shaped dummy signature accepted by bundler simulation
/// (permissionless.js `getDummySignature` for ECDSA owners).
const String ecdsaStubSignature =
    '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

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
