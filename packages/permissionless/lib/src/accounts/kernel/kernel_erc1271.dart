import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../utils/message_hash.dart';
import '../account_owner.dart';
import 'constants.dart';

/// Kernel EIP-712 wrap of a message or typed-data hash.
///
/// v0.2.x uses [hash] as the EIP-712 struct hash. v0.3.x first hashes
/// `Kernel(bytes32 hash)` with [hash], then applies `0x1901 ‖ domainSeparator
/// ‖ structHash`. Domain is `{name: Kernel, version, chainId,
/// verifyingContract: address}`.
///
/// Returns a 32-byte digest. Does not sign and does not add a validator prefix.
String wrapMessageHash({
  required String hash,
  required EthereumAddress address,
  required KernelVersion version,
  required BigInt chainId,
}) {
  final domain = TypedDataDomain(
    name: 'Kernel',
    version: version.value,
    chainId: chainId,
    verifyingContract: address,
  );
  final domainSep = computeDomainSeparator(domain);

  final String structHash;
  if (version.isV2) {
    structHash = hash;
  } else {
    final typeHash = keccak256(
      Uint8List.fromList('Kernel(bytes32 hash)'.codeUnits),
    );
    structHash = Hex.fromBytes(
      keccak256(
        Hex.decode(
          Hex.concat([
            Hex.fromBytes(typeHash),
            hash,
          ]),
        ),
      ),
    );
  }

  return Hex.fromBytes(
    keccak256(
      Hex.decode(
        Hex.concat([
          '0x1901',
          Hex.strip0x(domainSep),
          Hex.strip0x(structHash),
        ]),
      ),
    ),
  );
}

/// Unprefixed Kernel ERC-1271 signature of a personal message.
///
/// - Kernel 0.2.1 / 0.2.2: [owner] signs `hashMessage(message)` directly.
/// - [eip7702] true: [owner] signs Kernel-domain typed data `{hash}`.
/// - otherwise: [wrapMessageHash] then [AccountOwner.signPersonalMessage].
///
/// Does not prepend `0x01‖validator` or the EIP-7702 `0x00` identifier.
Future<String> signKernelMessage({
  required AccountOwner owner,
  required String message,
  required EthereumAddress address,
  required KernelVersion version,
  required BigInt chainId,
  bool eip7702 = false,
}) async {
  if (eip7702) {
    return owner.signTypedData(
      _kernelWrapperTypedData(
        hash: hashMessage(message),
        address: address,
        version: version,
        chainId: chainId,
      ),
    );
  }
  if (version.skipsKernelMessageWrap) {
    return owner.signRawHash(hashMessage(message));
  }
  final wrappedDigest = wrapMessageHash(
    hash: hashMessage(message),
    address: address,
    version: version,
    chainId: chainId,
  );
  return owner.signPersonalMessage(wrappedDigest);
}

/// Unprefixed Kernel ERC-1271 signature of EIP-712 typed data.
///
/// - Kernel 0.2.1 / 0.2.2: [owner] signs [typedData] directly.
/// - [eip7702] true: [owner] signs Kernel-domain typed data `{hash}`.
/// - otherwise: [wrapMessageHash] then [AccountOwner.signPersonalMessage].
///
/// Does not prepend `0x01‖validator` or the EIP-7702 `0x00` identifier.
Future<String> signKernelTypedData({
  required AccountOwner owner,
  required TypedData typedData,
  required EthereumAddress address,
  required KernelVersion version,
  required BigInt chainId,
  bool eip7702 = false,
}) async {
  if (version.skipsKernelMessageWrap && !eip7702) {
    return owner.signTypedData(typedData);
  }
  final typedHash = hashTypedData(typedData);
  if (eip7702) {
    return owner.signTypedData(
      _kernelWrapperTypedData(
        hash: typedHash,
        address: address,
        version: version,
        chainId: chainId,
      ),
    );
  }
  final wrappedDigest = wrapMessageHash(
    hash: typedHash,
    address: address,
    version: version,
    chainId: chainId,
  );
  return owner.signPersonalMessage(wrappedDigest);
}

TypedData _kernelWrapperTypedData({
  required String hash,
  required EthereumAddress address,
  required KernelVersion version,
  required BigInt chainId,
}) =>
    TypedData(
      domain: TypedDataDomain(
        name: 'Kernel',
        version: version.value,
        chainId: chainId,
        verifyingContract: address,
      ),
      types: {
        'EIP712Domain': [
          const TypedDataField(name: 'name', type: 'string'),
          const TypedDataField(name: 'version', type: 'string'),
          const TypedDataField(name: 'chainId', type: 'uint256'),
          const TypedDataField(name: 'verifyingContract', type: 'address'),
        ],
        'Kernel': [
          const TypedDataField(name: 'hash', type: 'bytes32'),
        ],
      },
      primaryType: 'Kernel',
      message: {
        'hash': hash,
      },
    );
