import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Kernel ERC-1271 helpers (`wrapMessageHash`, `signKernelMessage`,
/// `signKernelTypedData`) against permissionless.js.
///
/// Fixtures match [erc1271_signing_parity_test.dart] Kernel group:
/// privateKey `0x59c6…690d`, message `"hello"`, account `0x4444…4444`,
/// chainId Sepolia. Helper signatures are unprefixed; the v0.3.1 / v0.2.4
/// account signatures (with their prefixes) are pinned in
/// erc1271_signing_parity_test.dart.
///
/// Vectors marked "permissionless.js" come from permissionless.js 0.5.2 (source
/// at a536891) `accounts/kernel/utils/{wrapMessageHash,signMessage}` and
/// `toKernelSmartAccount` run with viem 2.21.55.
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
  // permissionless.js: wrapMessageHash({hash: hashMessage("hello"), address,
  // version, chainId: 11155111})
  const jsWrapV031 =
      '0x334fbef0c7788841791867268be4c9377686802e228eaa91b414a98750c4cf5c';
  const jsWrapV024 =
      '0x4b37882e4d4b8968ea4f29338f3419aed445bfccd2c986f22f82d3081d06cffb';
  // permissionless.js: signMessage util, version 0.2.1
  // (owner.signMessage("hello")); toKernelSmartAccount v0.2.1 (deployed) signMessage returns it unprefixed.
  const jsSignMessageV021 =
      '0x76930d64d2e5eb4b3f4572ce806eda50e1e2329d51d9ca5a713a9befcb9d2088'
      '3e3d4885c3c5eaf775fc8c9fcf4882a28b582b427bc0270565f3294d935549221b';
  // permissionless.js: signMessage util with eip7702: true, version 0.3.3,
  // address = owner; toKernelSmartAccount({eip7702: true}).signMessage
  // prepends the 0x00 root identifier.
  const jsSignMessage7702V033 =
      '0xd11aefdbfb763565b9f2755eba2916ab6901c9c99d70694981e2768f3b1c12f0'
      '274ddb6b44395caaf308f6af655f59ac6b616f08b30d54749fe1dda5334800f61c';
  const jsSignMessageV024 =
      '0xa87069aaabd6cad2f39667debf72d986198f450789762541dfd83106b91ffa2f0ae095a1ef7a49156ccfa238cbdfb1c00a47152a7faaeeb29ab97a5afd6e19081c';

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
    test('v0.3.1 and v0.2.4 digests match permissionless.js', () {
      final hash = hashMessage(message);
      expect(
        wrapMessageHash(
          hash: hash,
          address: accountAddress,
          version: KernelVersion.v0_3_1,
          chainId: chainId,
        ),
        equals(jsWrapV031),
      );
      expect(
        wrapMessageHash(
          hash: hash,
          address: accountAddress,
          version: KernelVersion.v0_2_4,
          chainId: chainId,
        ),
        equals(jsWrapV024),
      );
    });
  });

  group('signKernelMessage / signKernelTypedData', () {
    test('v0.3.1 signKernelMessage matches permissionless.js', () async {
      final helper = await signKernelMessage(
        owner: owner,
        message: message,
        address: accountAddress,
        version: KernelVersion.v0_3_1,
        chainId: chainId,
      );

      expect(
        helper.toLowerCase(),
        equals(jsHelperSignMessageV031.toLowerCase()),
      );
    });

    test('v0.3.1 signKernelTypedData matches permissionless.js', () async {
      final helper = await signKernelTypedData(
        owner: owner,
        typedData: sampleTypedData,
        address: accountAddress,
        version: KernelVersion.v0_3_1,
        chainId: chainId,
      );

      expect(
        helper.toLowerCase(),
        equals(jsHelperSignTypedDataV031.toLowerCase()),
      );
    });

    test('v0.2.4 signKernelMessage matches permissionless.js', () async {
      final helper = await signKernelMessage(
        owner: owner,
        message: message,
        address: accountAddress,
        version: KernelVersion.v0_2_4,
        chainId: chainId,
      );

      expect(helper.toLowerCase(), equals(jsSignMessageV024.toLowerCase()));
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
      final accountSig =
          await kernelAccount(KernelVersion.v0_2_1).signMessage(message);

      expect(helper, equals(jsSignMessageV021));
      expect(accountSig, equals(jsSignMessageV021));
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
      expect(helper, equals(jsSignMessage7702V033));

      final account = createEip7702KernelSmartAccount(
        owner: PrivateKeyEip7702KernelOwner(privateKey),
        chainId: chainId,
      );
      expect(
        await account.signMessage(message),
        equals('0x00${jsSignMessage7702V033.substring(2)}'),
      );
    });
  });
}
