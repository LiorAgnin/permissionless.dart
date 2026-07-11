import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Byte-for-byte ERC-1271 `signMessage` / `signTypedData` parity fixtures
/// generated with viem (permissionless.js reference) for fixed inputs:
///
/// - privateKey: `0x59c6…690d` → owner `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
/// - message: `"hello"`
/// - account: `0x4444…4444`
/// - chainId: `11155111` (Sepolia)
///
/// See docs/parity-audit ticket 008 and per-account reports.
void main() {
  const privateKey =
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';
  const ownerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
  const message = 'hello';
  final accountAddress = EthereumAddress.fromHex(
    '0x4444444444444444444444444444444444444444',
  );
  final chainId = BigInt.from(11155111);

  late PrivateKeyOwner owner;

  setUp(() {
    owner = PrivateKeyOwner(privateKey);
    expect(
      owner.address.hex.toLowerCase(),
      equals(ownerAddress.toLowerCase()),
    );
  });

  final sampleTypedData = TypedData(
    domain: TypedDataDomain(
      name: 'Mail',
      version: '1',
      chainId: chainId,
      verifyingContract: accountAddress,
    ),
    types: {
      'Mail': [const TypedDataField(name: 'contents', type: 'string')],
    },
    primaryType: 'Mail',
    message: {'contents': 'Hello'},
  );

  group('Trust (Barz) EIP-712 wrapper', () {
    // JS: signer.signTypedData(BarzMessage) — no EIP-191 over the digest
    const jsSignMessage =
        '0x461b0fe38f4c33023993a07c4f39f9957295250657ad5d9332c8cab134e276344d5c0308b8971abf79cb4ea4980c581ad1b44f4a862ff2be9854a57ac3db7f841c';

    test('signMessage matches permissionless.js', () async {
      final account = createTrustSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessage.toLowerCase()));
    });
  });

  group('LightAccountMessage EIP-712 wrapper', () {
    const jsSignMessage =
        '0x4bc537d2ee07a5e334d4a85c51f76deb1f47b36172364ab347c4d89f06d471756bc1bfd451ec046414f3a01b2db8b390a9b6a2fb1992bb8d5ba002ff80558e1a1b';
    const jsSignMessageV2 =
        '0x004bc537d2ee07a5e334d4a85c51f76deb1f47b36172364ab347c4d89f06d471756bc1bfd451ec046414f3a01b2db8b390a9b6a2fb1992bb8d5ba002ff80558e1a1b';

    test('signMessage (v1.1.0) matches permissionless.js', () async {
      final account = createLightSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
        version: LightAccountVersion.v110,
        entryPointVersion: EntryPointVersion.v06,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessage.toLowerCase()));
    });

    test('signMessage (v2.0.0) prepends 0x00 type byte', () async {
      final account = createLightSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
        version: LightAccountVersion.v200,
        entryPointVersion: EntryPointVersion.v07,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessageV2.toLowerCase()));
    });
  });

  group('Thirdweb AccountMessage EIP-712 wrapper', () {
    const jsSignMessage =
        '0x3f788acda7d9ff8066f7a1074f94cbf739095a3989086cfeb507e00078e41c69297b4298d9fe66047064bab7955264eb2881e566b4c07e0d7c468c7254d452081b';

    test('signMessage matches permissionless.js', () async {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessage.toLowerCase()));
    });
  });

  group('Etherspot (single EIP-191 + validator prefix)', () {
    // encodePacked(address, bytes) = validator ‖ signature
    const jsSignMessage =
        '0x0740Ed7c11b9da33d9C80Bd76b826e4E90CC190676930d64d2e5eb4b3f4572ce806eda50e1e2329d51d9ca5a713a9befcb9d20883e3d4885c3c5eaf775fc8c9fcf4882a28b582b427bc0270565f3294d935549221b';
    const jsSignTypedData =
        '0x0740Ed7c11b9da33d9C80Bd76b826e4E90CC190681eab6b0e9d1ead7dd997bc09eee29631dbbe6cc3a2de04944cae34a4fcba39e66264aced59ae68dbc0c19b9629d10adcb64f89f0af2f4fade7f38ebba79126c1c';

    test('signMessage matches permissionless.js (no double prefix)', () async {
      final account = createEtherspotSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessage.toLowerCase()));
    });

    test('signTypedData matches permissionless.js', () async {
      final account = createEtherspotSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
      );
      final sig = await account.signTypedData(sampleTypedData);
      expect(sig.toLowerCase(), equals(jsSignTypedData.toLowerCase()));
    });
  });

  group('Biconomy (single EIP-191 + module encode)', () {
    // ABI encode (bytes signature, address module) with body from
    // localOwner.signMessage({ message: "hello" })
    const jsEncoded =
        '0x00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000001c5b32f37f5bea87bdd5374eb2ac54ea8e000000000000000000000000000000000000000000000000000000000000004176930d64d2e5eb4b3f4572ce806eda50e1e2329d51d9ca5a713a9befcb9d20883e3d4885c3c5eaf775fc8c9fcf4882a28b582b427bc0270565f3294d935549221b00000000000000000000000000000000000000000000000000000000000000';

    test('signMessage matches permissionless.js (no double prefix)', () async {
      // ignore: deprecated_member_use_from_same_package
      final account = createBiconomySmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsEncoded.toLowerCase()));
    });
  });

  group('Kernel wrapMessageHash + root-validator prefix', () {
    // wrapMessageHash(hashMessage("hello")) then personal_sign raw digest,
    // then 0x01 ‖ ecdsaValidator for v0.3.1
    const jsSignMessageV031 =
        '0x01845ADb2C711129d4f3966735eD98a9F09fC4cE57cc0db94238eec02857c6ed9b7b63da573700091511fa606a132c9e817aecb32b56d14b7db6df7cb7101411368a81c7863c54ba025e27a57ecf734722bb6dcccd1c';
    const jsSignTypedDataV031 =
        '0x01845ADb2C711129d4f3966735eD98a9F09fC4cE57482c8a6d24395d2fd86a593003a056d83eb0132d622c3dc5fd56aecc9f38590f0c012b369e907ba35596e428cc398224346a41304f0fc233e118c5978e0784661c';
    // v0.2.4: wrap without Kernel(bytes32) struct step, no validator prefix
    const jsSignMessageV024 =
        '0xa87069aaabd6cad2f39667debf72d986198f450789762541dfd83106b91ffa2f0ae095a1ef7a49156ccfa238cbdfb1c00a47152a7faaeeb29ab97a5afd6e19081c';

    test('signMessage v0.3.1 matches permissionless.js', () async {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
        version: KernelVersion.v0_3_1,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessageV031.toLowerCase()));
    });

    test('signTypedData v0.3.1 matches permissionless.js', () async {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
        version: KernelVersion.v0_3_1,
      );
      final sig = await account.signTypedData(sampleTypedData);
      expect(sig.toLowerCase(), equals(jsSignTypedDataV031.toLowerCase()));
    });

    test('signMessage v0.2.4 matches permissionless.js', () async {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
        version: KernelVersion.v0_2_4,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessageV024.toLowerCase()));
    });
  });

  group('Safe SafeMessage wrapper + eth_sign V adjustment', () {
    // SafeMessage domain {chainId, verifyingContract: safe}, eth_sign of
    // digest, then adjustV(+4) → v ∈ {31, 32}
    const jsSignMessage =
        '0x21ba7cf79d39dddbad7a2a7344b7ded678b6de8e69d25e6579575928cd820264782f0e4a4f45c242b76d86fd54331fd4152ab4431325330425cd0c8e5d1b82e220';
    const jsSignTypedData =
        '0x84d641b18edbc498e1b5b1a6fd90248baf65695e6bd4329400177ba621a33ec0695a0315d03ab8d307564eabce30172903b21fc325104450ee35f4fd96b2cdb71c';

    test('signMessage matches permissionless.js (eth_sign +4 V)', () async {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: accountAddress,
      );
      final sig = await account.signMessage(message);
      expect(sig.toLowerCase(), equals(jsSignMessage.toLowerCase()));
      // V should be 0x20 (32) or 0x1f (31) after +4 eth_sign adjustment
      final v = int.parse(sig.substring(sig.length - 2), radix: 16);
      expect(v == 31 || v == 32, isTrue);
    });

    test('signTypedData matches permissionless.js (v 27/28)', () async {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: accountAddress,
      );
      final sig = await account.signTypedData(sampleTypedData);
      expect(sig.toLowerCase(), equals(jsSignTypedData.toLowerCase()));
      final v = int.parse(sig.substring(sig.length - 2), radix: 16);
      expect(v == 27 || v == 28, isTrue);
    });
  });
}
