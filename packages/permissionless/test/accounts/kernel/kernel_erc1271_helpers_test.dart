import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Kernel ERC-1271 helper vs account-method prefix relationship.
///
/// Fixtures match [erc1271_signing_parity_test.dart] Kernel group:
/// privateKey `0x59c6…690d`, message `"hello"`, account `0x4444…4444`,
/// chainId Sepolia. Helper signatures are unprefixed; v0.3.x account
/// signatures prepend `0x01‖validator`.
void main() {
  const privateKey =
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';
  const message = 'hello';
  final accountAddress = EthereumAddress.fromHex(
    '0x4444444444444444444444444444444444444444',
  );
  final chainId = BigInt.from(11155111);

  // v0.3.1 account signMessage from permissionless.js, with 21-byte prefix
  // `0x01 ‖ 845ADb2C711129d4f3966735eD98a9F09fC4cE57` stripped.
  const jsHelperSignMessageV031 =
      '0xcc0db94238eec02857c6ed9b7b63da573700091511fa606a132c9e817aecb32b56d14b7db6df7cb7101411368a81c7863c54ba025e27a57ecf734722bb6dcccd1c';
  const jsHelperSignTypedDataV031 =
      '0x482c8a6d24395d2fd86a593003a056d83eb0132d622c3dc5fd56aecc9f38590f0c012b369e907ba35596e428cc398224346a41304f0fc233e118c5978e0784661c';
  const jsSignMessageV024 =
      '0xa87069aaabd6cad2f39667debf72d986198f450789762541dfd83106b91ffa2f0ae095a1ef7a49156ccfa238cbdfb1c00a47152a7faaeeb29ab97a5afd6e19081c';

  const v031PrefixLength = 21;

  late PrivateKeyOwner owner;

  setUp(() {
    owner = PrivateKeyOwner(privateKey);
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

  KernelSmartAccount kernelAccount(KernelVersion version) =>
      createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: accountAddress,
        version: version,
      );

  group('wrapMessageHash', () {
    test('returns a 32-byte digest for v0.3.1 and v0.2.4', () {
      final hash = hashMessage(message);
      final v3 = wrapMessageHash(
        hash: hash,
        address: accountAddress,
        version: KernelVersion.v0_3_1,
        chainId: chainId,
      );
      final v2 = wrapMessageHash(
        hash: hash,
        address: accountAddress,
        version: KernelVersion.v0_2_4,
        chainId: chainId,
      );
      expect(Hex.byteLength(v3), equals(32));
      expect(Hex.byteLength(v2), equals(32));
      expect(v3.toLowerCase(), isNot(equals(v2.toLowerCase())));
    });
  });

  group('signKernelMessage / signKernelTypedData vs account', () {
    test('v0.3.1 helper is the account signMessage without the 21-byte prefix',
        () async {
      final helper = await signKernelMessage(
        owner: owner,
        message: message,
        address: accountAddress,
        version: KernelVersion.v0_3_1,
        chainId: chainId,
      );
      final accountSig =
          await kernelAccount(KernelVersion.v0_3_1).signMessage(message);

      expect(
        helper.toLowerCase(),
        equals(jsHelperSignMessageV031.toLowerCase()),
      );
      expect(
        Hex.byteLength(accountSig) - Hex.byteLength(helper),
        equals(v031PrefixLength),
      );
      expect(
        Hex.slice(accountSig, v031PrefixLength).toLowerCase(),
        equals(helper.toLowerCase()),
      );
      expect(
        Hex.slice(accountSig, 0, v031PrefixLength).toLowerCase(),
        equals('0x01845adb2c711129d4f3966735ed98a9f09fc4ce57'),
      );
    });

    test(
        'v0.3.1 helper is the account signTypedData without the 21-byte prefix',
        () async {
      final helper = await signKernelTypedData(
        owner: owner,
        typedData: sampleTypedData,
        address: accountAddress,
        version: KernelVersion.v0_3_1,
        chainId: chainId,
      );
      final accountSig = await kernelAccount(KernelVersion.v0_3_1)
          .signTypedData(sampleTypedData);

      expect(
        helper.toLowerCase(),
        equals(jsHelperSignTypedDataV031.toLowerCase()),
      );
      expect(
        Hex.byteLength(accountSig) - Hex.byteLength(helper),
        equals(v031PrefixLength),
      );
      expect(
        Hex.slice(accountSig, v031PrefixLength).toLowerCase(),
        equals(helper.toLowerCase()),
      );
    });

    test('v0.2.4 helper equals account signMessage (no prefix)', () async {
      final helper = await signKernelMessage(
        owner: owner,
        message: message,
        address: accountAddress,
        version: KernelVersion.v0_2_4,
        chainId: chainId,
      );
      final accountSig =
          await kernelAccount(KernelVersion.v0_2_4).signMessage(message);

      expect(helper.toLowerCase(), equals(jsSignMessageV024.toLowerCase()));
      expect(helper.toLowerCase(), equals(accountSig.toLowerCase()));
    });

    test('v0.2.1 skips Kernel wrap (owner signs hashMessage directly)',
        () async {
      final helper = await signKernelMessage(
        owner: owner,
        message: message,
        address: accountAddress,
        version: KernelVersion.v0_2_1,
        chainId: chainId,
      );
      final direct = await owner.signRawHash(hashMessage(message));
      final accountSig =
          await kernelAccount(KernelVersion.v0_2_1).signMessage(message);

      expect(helper.toLowerCase(), equals(direct.toLowerCase()));
      expect(helper.toLowerCase(), equals(accountSig.toLowerCase()));
    });

    test('eip7702 helper is Kernel-domain typed data, account prefixes 0x00',
        () async {
      final helper = await signKernelMessage(
        owner: owner,
        message: message,
        address: owner.address,
        version: KernelVersion.v0_3_3,
        chainId: chainId,
        eip7702: true,
      );
      final kernelTypedData = TypedData(
        domain: TypedDataDomain(
          name: 'Kernel',
          version: KernelVersion.v0_3_3.value,
          chainId: chainId,
          verifyingContract: owner.address,
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
        message: {'hash': hashMessage(message)},
      );
      final direct = await owner.signTypedData(kernelTypedData);
      expect(helper.toLowerCase(), equals(direct.toLowerCase()));

      final account = createEip7702KernelSmartAccount(
        owner: PrivateKeyEip7702KernelOwner(privateKey),
        chainId: chainId,
      );
      final accountSig = await account.signMessage(message);
      expect(Hex.slice(accountSig, 0, 1), equals('0x00'));
      expect(
        Hex.slice(accountSig, 1).toLowerCase(),
        equals(helper.toLowerCase()),
      );
    });
  });
}
