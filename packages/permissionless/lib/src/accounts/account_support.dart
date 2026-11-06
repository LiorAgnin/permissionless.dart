import '../clients/public/public_client.dart';
import '../types/address.dart';

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
