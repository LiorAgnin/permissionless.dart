import '../types/address.dart';
import '../types/typed_data.dart';

/// The replay-safe ERC-1271 wrapper LightAccount, Thirdweb Account and Barz
/// verify in `isValidSignature`: EIP-712 typed data `primaryType(bytes
/// message)` over the domain `{name, version, chainId, verifyingContract}`,
/// where [message] is the hash being signed (`hashMessage` / `hashTypedData`).
TypedData wrappedMessageTypedData({
  required String domainName,
  required String domainVersion,
  required BigInt chainId,
  required EthereumAddress verifyingContract,
  required String primaryType,
  required String message,
}) =>
    TypedData(
      domain: TypedDataDomain(
        name: domainName,
        version: domainVersion,
        chainId: chainId,
        verifyingContract: verifyingContract,
      ),
      types: {
        primaryType: [const TypedDataField(name: 'message', type: 'bytes')],
      },
      primaryType: primaryType,
      message: {'message': message},
    );
