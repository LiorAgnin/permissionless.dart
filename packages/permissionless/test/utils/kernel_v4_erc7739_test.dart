import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../helpers/kernel_v4_vectors.dart';

/// Hardhat account #0 — the root/fallback signer of every fixture account.
/// Fixed offline unit-test key, never used on live networks.
const String _rootPrivateKey =
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

/// Hardhat account #1 — the validator/permission module owner in the
/// fixture scenarios, deliberately distinct from the root.
const String _modulePrivateKey =
    '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

/// Kernel v4 ERC-1271 / ERC-7739 helpers (ticket 08), pinned to signature
/// bytes the pinned Kernel v4.0 contracts accepted via `isValidSignature`
/// (`tool/kernel_v4_vectors` — every fixture case asserts acceptance, and
/// the negatives rejection, on-EVM before the vector is written).
void main() {
  final vectors = loadKernelV4Vectors();
  final chainId = BigInt.from(vectors['chainId'] as int);
  final erc1271 = vectors['erc1271'] as Map<String, dynamic>;

  final root = PrivateKeyOwner(_rootPrivateKey);
  final moduleOwner = PrivateKeyOwner(_modulePrivateKey);

  group('getKernelV4PersonalSignDigest', () {
    test('wraps the EIP-191 hash under the account domain (root case)', () {
      final c = erc1271['personalSignRoot'] as Map<String, dynamic>;
      expect(hashMessage(c['message'] as String), equals(c['hash']));
      expect(
        getKernelV4PersonalSignDigest(
          accountAddress: EthereumAddress.fromHex(c['sender'] as String),
          chainId: chainId,
          hash: c['hash'] as String,
        ),
        equals(c['digest']),
      );
    });

    test('binds the digest to the account address (validator case)', () {
      final c = erc1271['personalSignValidator'] as Map<String, dynamic>;
      expect(
        getKernelV4PersonalSignDigest(
          accountAddress: EthereumAddress.fromHex(c['sender'] as String),
          chainId: chainId,
          hash: c['hash'] as String,
        ),
        equals(c['digest']),
      );
    });
  });

  group('getKernelV4TypedDataSignWrap', () {
    final c = erc1271['typedDataSignRoot'] as Map<String, dynamic>;
    final typedData = kernelV4MailTypedDataFromCase(c);
    final sender = EthereumAddress.fromHex(c['sender'] as String);

    test('the rebuilt typed data reproduces the app-side pieces', () {
      // The 1271 input hash is the app's own hashTypedData — the wrap must
      // reconstruct it from the same domain separator and contents hash the
      // on-chain check recomputes.
      expect(hashTypedData(typedData), equals(c['hash']));
      expect(
        computeDomainSeparator(typedData.domain),
        equals(c['appDomainSeparator']),
      );
      expect(
        hashStruct(typedData.primaryType, typedData.message, typedData.types),
        equals(c['contents']),
      );
      expect(
        encodeTypedDataType(typedData.primaryType, typedData.types),
        equals(c['contentsType']),
      );
    });

    test('chain-specific digest matches the contract-accepted digest', () {
      final wrap = getKernelV4TypedDataSignWrap(
        accountAddress: sender,
        chainId: chainId,
        typedData: typedData,
      );
      expect(wrap.digest, equals(c['digest']));
    });

    test('replayable digest drops the chainId from the TypedDataSign struct',
        () {
      final replayable =
          erc1271['typedDataSignReplayable'] as Map<String, dynamic>;
      final wrap = getKernelV4TypedDataSignWrap(
        accountAddress: sender,
        chainId: chainId,
        typedData: typedData,
        replayable: true,
      );
      expect(wrap.digest, equals(replayable['digest']));
      expect(wrap.digest, isNot(equals(c['digest'])));
    });

    test('the extension carries appDomainSep, contents, type, uint16 length',
        () {
      final wrap = getKernelV4TypedDataSignWrap(
        accountAddress: sender,
        chainId: chainId,
        typedData: typedData,
      );
      final contentsType = c['contentsType'] as String;
      // The fixture signature is `[2B prefix][65B sig][extension]` — the
      // extension is everything after the inner signature.
      final signature = c['signature'] as String;
      final extension = '0x${Hex.strip0x(signature).substring((2 + 65) * 2)}';
      expect(wrap.extension, equals(extension));
      expect(
        Hex.byteLength(wrap.extension),
        equals(32 + 32 + contentsType.length + 2),
      );
    });

    test('rejects a primary type the on-chain parser would corrupt', () {
      TypedData withPrimaryType(String name) => TypedData(
            domain: typedData.domain,
            types: {
              name: [const TypedDataField(name: 'x', type: 'uint256')],
            },
            primaryType: name,
            message: {'x': BigInt.one},
          );
      // ERC-7739 rejects contents names starting with `[a-z(]` or containing
      // `, )\x00` — a Dart-side throw beats a silently-corrupted digest.
      expect(
        () => getKernelV4TypedDataSignWrap(
          accountAddress: sender,
          chainId: chainId,
          typedData: withPrimaryType('mail'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('encodeKernelV4Erc1271Signature framing', () {
    test('root: [0x00 0x00] then the raw signature', () async {
      final c = erc1271['personalSignRoot'] as Map<String, dynamic>;
      final inner = await root.signRawHash(c['digest'] as String);
      expect(
        encodeKernelV4Erc1271Signature(
          validation: const KernelV4Validation.root(),
          signature: inner,
        ),
        equals(c['signature']),
      );
    });

    test('root typed-data: prefix, signature, then the extension', () async {
      final c = erc1271['typedDataSignRoot'] as Map<String, dynamic>;
      final wrap = getKernelV4TypedDataSignWrap(
        accountAddress: EthereumAddress.fromHex(c['sender'] as String),
        chainId: chainId,
        typedData: kernelV4MailTypedDataFromCase(c),
      );
      final inner = await root.signRawHash(wrap.digest);
      expect(
        encodeKernelV4Erc1271Signature(
          validation: const KernelV4Validation.root(),
          signature: inner,
          extension: wrap.extension,
        ),
        equals(c['signature']),
      );
    });

    test('validator: [0x00 0x01 | 20-byte module] then the raw signature',
        () async {
      final c = erc1271['personalSignValidator'] as Map<String, dynamic>;
      final inner = await moduleOwner.signRawHash(c['digest'] as String);
      expect(
        encodeKernelV4Erc1271Signature(
          validation: KernelV4Validation.validator(
            EthereumAddress.fromHex(c['validator'] as String),
          ),
          signature: inner,
        ),
        equals(c['signature']),
      );
    });

    test('permission: [0x00 0x02 | 4-byte id] then the signature list',
        () async {
      final c = erc1271['personalSignPermission'] as Map<String, dynamic>;
      final validation = KernelV4Validation.permission(
        c['permissionId'] as String,
        policySignatures: [c['policyData'] as String],
      );
      final inner = validation
          .wrapSignature(await moduleOwner.signRawHash(c['digest'] as String));
      expect(
        encodeKernelV4Erc1271Signature(
          validation: validation,
          signature: inner,
        ),
        equals(c['signature']),
      );
    });

    test('enable mode: [0x08 | vType | vId] then the EnableModeSignature blob',
        () async {
      final c = erc1271['enableMode'] as Map<String, dynamic>;
      final packages = kernelV4PackagesFromCase(c);
      final sender = EthereumAddress.fromHex(c['sender'] as String);
      final installDigest = getKernelV4InstallPackagesDigest(
        accountAddress: sender,
        installNonce: BigInt.zero,
        packages: packages,
        chainId: chainId,
      );
      expect(installDigest, equals(c['chainSpecificInstallDigest']));
      final blob = encodeKernelV4EnableModeSignature(
        installNonce: BigInt.zero,
        packages: packages,
        enableSignature: await root.signRawHash(installDigest),
        userOpSignature: await moduleOwner.signRawHash(c['digest'] as String),
      );
      expect(
        encodeKernelV4Erc1271Signature(
          validation: KernelV4Validation.validator(
            EthereumAddress.fromHex(c['validator'] as String),
          ),
          signature: blob,
          vMode: KernelV4ValidationMode.enable,
        ),
        equals(c['signature']),
      );
    });

    test('replayable enable mode signs the sans-chainId install digest',
        () async {
      final c = erc1271['enableMode'] as Map<String, dynamic>;
      final packages = kernelV4PackagesFromCase(c);
      final sender = EthereumAddress.fromHex(c['sender'] as String);
      final installDigest = getKernelV4InstallPackagesDigest(
        accountAddress: sender,
        installNonce: BigInt.zero,
        packages: packages,
        replayable: true,
      );
      expect(installDigest, equals(c['sansChainIdInstallDigest']));
      final blob = encodeKernelV4EnableModeSignature(
        installNonce: BigInt.zero,
        packages: packages,
        enableSignature: await root.signRawHash(installDigest),
        userOpSignature: await moduleOwner.signRawHash(c['digest'] as String),
      );
      expect(
        encodeKernelV4Erc1271Signature(
          validation: KernelV4Validation.validator(
            EthereumAddress.fromHex(c['validator'] as String),
          ),
          signature: blob,
          vMode: KernelV4ValidationMode.enable |
              KernelV4ValidationMode.replayableEnable,
        ),
        equals(c['replayableSignature']),
      );
    });

    test('enable mode with root validation is rejected before the chain', () {
      // Kernel forbids the ROOT vType in enable-mode 1271
      // (`InvalidValidationType`) — the encoder throws instead of producing
      // a signature the contract would revert on.
      expect(
        () => encodeKernelV4Erc1271Signature(
          validation: const KernelV4Validation.root(),
          signature: '0x00',
          vMode: KernelV4ValidationMode.enable,
        ),
        throwsArgumentError,
      );
    });
  });
}
