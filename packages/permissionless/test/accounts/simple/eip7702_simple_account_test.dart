import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';
import 'package:web3dart/web3dart.dart' as crypto;

/// Recovers the signer of [signature] over the raw 32-byte [digest]
/// (Solidity `ECDSA.recover(digest, signature)`).
EthereumAddress _recover(String digest, String signature) {
  final sig = Hex.decode(signature);
  final publicKey = crypto.ecRecover(
    Hex.decode(digest),
    crypto.MsgSignature(
      crypto.bytesToUnsignedInt(sig.sublist(0, 32)),
      crypto.bytesToUnsignedInt(sig.sublist(32, 64)),
      sig[64],
    ),
  );
  return EthereumAddress(crypto.publicKeyToAddress(publicKey));
}

void main() {
  // Hardhat account #0 — do not use in production
  const privateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  group('Eip7702SimpleSmartAccount ERC-1271 signing', () {
    final owner = PrivateKeyEip7702Owner(privateKey);
    final account = createEip7702SimpleSmartAccount(
      owner: owner,
      chainId: BigInt.one,
    );

    // Simple7702Account.isValidSignature(hash, sig) checks
    // ECDSA.recover(hash, sig) == address(this) with no extra prefix, and the
    // verifier passes hash = hashMessage(message) (EIP-191).
    test('signMessage recovers to the EOA over hashMessage(message)', () async {
      const message = 'hello';
      final signature = await account.signMessage(message);
      expect(
        _recover(hashMessage(message), signature),
        equals(owner.address),
      );
    });

    test('signTypedData recovers to the EOA over hashTypedData', () async {
      final typedData = TypedData(
        domain: TypedDataDomain(
          name: 'Mail',
          version: '1',
          chainId: BigInt.one,
          verifyingContract: EthereumAddress.fromHex(
            '0x2222222222222222222222222222222222222222',
          ),
        ),
        types: {
          'Mail': [const TypedDataField(name: 'contents', type: 'string')],
        },
        primaryType: 'Mail',
        message: {'contents': 'Hello'},
      );
      final signature = await account.signTypedData(typedData);
      expect(
        _recover(hashTypedData(typedData), signature),
        equals(owner.address),
      );
    });
  });

  group('PrivateKeyEip7702Owner', () {
    final owner = PrivateKeyEip7702Owner(privateKey);
    final reference = PrivateKeyOwner(privateKey);
    const hash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';

    test('signHash is the EIP-191 personal sign of the hash', () async {
      expect(
        await owner.signHash(hash),
        equals(await reference.signPersonalMessage(hash)),
      );
    });

    test('signatures carry v in {27, 28}', () async {
      for (var i = 0; i < 16; i++) {
        final digest = Hex.fromBigInt(BigInt.from(i + 1), byteLength: 32);
        final typedData = TypedData(
          domain: TypedDataDomain(name: 'T', version: '1', chainId: BigInt.one),
          types: {
            'M': [const TypedDataField(name: 'b', type: 'bytes')],
          },
          primaryType: 'M',
          message: {'b': digest},
        );
        final signature = Hex.decode(await owner.signTypedData(typedData));
        expect(signature, hasLength(65));
        expect(signature[64], anyOf(27, 28));
      }
    });
  });
}
