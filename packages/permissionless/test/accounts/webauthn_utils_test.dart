import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

const _testPrivateKey =
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

class _TestWebAuthnOwner extends WebAuthnAccountOwner {
  _TestWebAuthnOwner();

  @override
  BigInt get x => BigInt.one;

  @override
  BigInt get y => BigInt.two;

  @override
  Uint8List get credentialId => Uint8List(1);

  @override
  Future<P256SignatureData> signP256(String hash) =>
      throw UnsupportedError('test double');
}

/// An ECDSA owner that reports the WebAuthn type string without being a
/// [WebAuthnAccountOwner], so it has no P256 key to hand to an account.
class _WebAuthnTypedEcdsaOwner implements AccountOwner {
  _WebAuthnTypedEcdsaOwner(this._inner);

  final PrivateKeyOwner _inner;

  @override
  String get type => OwnerType.webAuthn;

  @override
  EthereumAddress get address => _inner.address;

  @override
  Future<String> signPersonalMessage(String hash) =>
      _inner.signPersonalMessage(hash);

  @override
  Future<String> signRawHash(String hash) => _inner.signRawHash(hash);

  @override
  Future<String> signTypedData(TypedData typedData) =>
      _inner.signTypedData(typedData);
}

void main() {
  group('isWebAuthnAccount', () {
    test('is true for a WebAuthnAccountOwner', () {
      expect(isWebAuthnAccount(_TestWebAuthnOwner()), isTrue);
    });

    test('is false for ECDSA owners, null and non-owners', () {
      expect(isWebAuthnAccount(PrivateKeyOwner(_testPrivateKey)), isFalse);
      expect(isWebAuthnAccount(null), isFalse);
      expect(isWebAuthnAccount('webAuthn'), isFalse);
    });

    test('is false for an owner that only reports the WebAuthn type', () {
      final owner = _WebAuthnTypedEcdsaOwner(PrivateKeyOwner(_testPrivateKey));
      expect(isWebAuthnAccount(owner), isFalse);
    });
  });

  test('Kernel treats an owner that only reports the WebAuthn type as ECDSA',
      () async {
    final mockAddress =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
    KernelSmartAccount kernel(AccountOwner owner) => createKernelSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          version: KernelVersion.v0_3_1,
          address: mockAddress,
        );
    final ecdsaOwner = PrivateKeyOwner(_testPrivateKey);
    final account = kernel(_WebAuthnTypedEcdsaOwner(ecdsaOwner));

    expect(
      (await account.getFactoryData())!.factoryData,
      (await kernel(ecdsaOwner).getFactoryData())!.factoryData,
    );
    expect(account.isWebAuthn, isFalse);
    expect(account.getStubSignature(), kernelDummyEcdsaSignature);
  });
}
