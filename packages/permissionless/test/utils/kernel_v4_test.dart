import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../helpers/kernel_v4_vectors.dart';

void main() {
  final vectors = loadKernelV4Vectors();
  final addressCases =
      (vectors['addressCases'] as List<dynamic>).cast<Map<String, dynamic>>();
  final canonical = vectors['canonical'] as Map<String, dynamic>;
  final canonicalFactory =
      EthereumAddress.fromHex(canonical['factory'] as String);
  final canonicalImplementation =
      EthereumAddress.fromHex(canonical['kernelImmutableECDSA'] as String);
  final localFactory =
      EthereumAddress.fromHex(vectors['localFactory'] as String);
  final localImplementation =
      EthereumAddress.fromHex(vectors['localKernelImmutableECDSA'] as String);

  group('KernelV4Addresses.predicted', () {
    test('matches the release v0.4.0 CREATE2 predictions', () {
      final predicted = KernelV4Addresses.predicted;
      expect(
        predicted.staker.hex.toLowerCase(),
        equals((canonical['staker'] as String).toLowerCase()),
      );
      expect(
        predicted.kernelUUPS.hex.toLowerCase(),
        equals((canonical['kernelUUPS'] as String).toLowerCase()),
      );
      expect(
        predicted.kernelImmutableECDSA.hex.toLowerCase(),
        equals((canonical['kernelImmutableECDSA'] as String).toLowerCase()),
      );
      expect(
        predicted.factory.hex.toLowerCase(),
        equals((canonical['factory'] as String).toLowerCase()),
      );
      expect(predicted.ecdsaValidator, isNull);
      expect(predicted.webAuthnValidator, isNull);
    });
  });

  group('computeKernelV4Salt', () {
    for (final c in addressCases) {
      test('matches the factory salt for case ${c['name']}', () {
        final salt = computeKernelV4Salt(
          packages: kernelV4PackagesFromCase(c),
          nonce: BigInt.parse(c['nonce'] as String),
        );
        expect(salt, equals(c['salt']));
      });
    }
  });

  group('kernelV4CloneInitCode', () {
    for (final c in addressCases) {
      test('matches Solady initCodeERC1967 for case ${c['name']}', () {
        final signer = EthereumAddress.fromHex(c['signer'] as String);
        final initCode = kernelV4CloneInitCode(
          implementation: canonicalImplementation,
          immutableArgs: signer.hex,
        );
        expect(initCode, equals(c['canonicalInitCode']));
        expect(
          kernelV4CloneInitCodeHash(
            implementation: canonicalImplementation,
            immutableArgs: signer.hex,
          ),
          equals(c['canonicalInitCodeHash']),
        );
      });
    }
  });

  group('computeKernelV4EcdsaAddress', () {
    for (final c in addressCases) {
      test('matches canonical prediction for case ${c['name']}', () {
        final address = computeKernelV4EcdsaAddress(
          signer: EthereumAddress.fromHex(c['signer'] as String),
          packages: kernelV4PackagesFromCase(c),
          nonce: BigInt.parse(c['nonce'] as String),
          factory: canonicalFactory,
          implementation: canonicalImplementation,
        );
        expect(
          address.hex.toLowerCase(),
          equals((c['canonicalAddress'] as String).toLowerCase()),
        );
      });

      test('matches factory.getECDSAAddress for case ${c['name']}', () {
        final address = computeKernelV4EcdsaAddress(
          signer: EthereumAddress.fromHex(c['signer'] as String),
          packages: kernelV4PackagesFromCase(c),
          nonce: BigInt.parse(c['nonce'] as String),
          factory: localFactory,
          implementation: localImplementation,
        );
        expect(
          address.hex.toLowerCase(),
          equals((c['localAddress'] as String).toLowerCase()),
        );
      });
    }
  });

  group('encodeKernelV4DeployEcdsaCalldata', () {
    for (final c in addressCases) {
      test('byte-matches abi.encodeCall for case ${c['name']}', () {
        final calldata = encodeKernelV4DeployEcdsaCalldata(
          signer: EthereumAddress.fromHex(c['signer'] as String),
          packages: kernelV4PackagesFromCase(c),
          nonce: BigInt.parse(c['nonce'] as String),
        );
        expect(calldata, equals(c['deployEcdsaCalldata']));
      });
    }
  });

  group('encodeKernelV4DeployWithFactoryCalldata', () {
    for (final c in addressCases) {
      test('byte-matches abi.encodeCall for case ${c['name']}', () {
        final calldata = encodeKernelV4DeployWithFactoryCalldata(
          factory: canonicalFactory,
          createData: c['deployEcdsaCalldata'] as String,
        );
        expect(calldata, equals(c['deployWithFactoryCalldata']));
      });
    }
  });

  group('computeKernelV4UupsAddress', () {
    final canonicalUups =
        EthereumAddress.fromHex(canonical['kernelUUPS'] as String);
    final localUups =
        EthereumAddress.fromHex(vectors['localKernelUUPS'] as String);

    for (final c in addressCases) {
      test('matches canonical prediction for case ${c['name']}', () {
        final address = computeKernelV4UupsAddress(
          packages: kernelV4PackagesFromCase(c),
          nonce: BigInt.parse(c['nonce'] as String),
          factory: canonicalFactory,
          implementation: canonicalUups,
        );
        expect(
          address.hex.toLowerCase(),
          equals((c['canonicalUupsAddress'] as String).toLowerCase()),
        );
      });

      test('matches factory.getAddress for case ${c['name']}', () {
        final address = computeKernelV4UupsAddress(
          packages: kernelV4PackagesFromCase(c),
          nonce: BigInt.parse(c['nonce'] as String),
          factory: localFactory,
          implementation: localUups,
        );
        expect(
          address.hex.toLowerCase(),
          equals((c['localUupsAddress'] as String).toLowerCase()),
        );
      });
    }

    test('the signer is absent from the UUPS identity', () {
      // Same packages and nonce, different signers → same UUPS address
      // (the fixture's emptyNonce0 and otherSigner cases agree on this).
      final emptyNonce0 = addressCases.firstWhere(
        (c) => c['name'] == 'emptyNonce0',
      );
      final otherSigner = addressCases.firstWhere(
        (c) => c['name'] == 'otherSigner',
      );
      expect(
        emptyNonce0['canonicalUupsAddress'],
        equals(otherSigner['canonicalUupsAddress']),
      );
    });
  });

  group('encodeKernelV4DeployCalldata', () {
    for (final c in addressCases) {
      test('byte-matches abi.encodeCall for case ${c['name']}', () {
        final calldata = encodeKernelV4DeployCalldata(
          packages: kernelV4PackagesFromCase(c),
          nonce: BigInt.parse(c['nonce'] as String),
        );
        expect(calldata, equals(c['deployUupsCalldata']));
      });

      test('staker wrap byte-matches for case ${c['name']}', () {
        final calldata = encodeKernelV4DeployWithFactoryCalldata(
          factory: canonicalFactory,
          createData: c['deployUupsCalldata'] as String,
        );
        expect(calldata, equals(c['deployUupsWithFactoryCalldata']));
      });
    }
  });

  group('encodeKernelV4NonceKey', () {
    test('root standard mode with zero key is zero', () {
      expect(encodeKernelV4NonceKey(), equals(BigInt.zero));
    });

    test('root standard mode passes the 2-byte key through', () {
      expect(
        encodeKernelV4NonceKey(nonceKey: BigInt.from(0x1234)),
        equals(BigInt.from(0x1234)),
      );
    });

    test('packs vMode, vType, vId, and key into 24 bytes', () {
      final validator =
          EthereumAddress.fromHex('0x845ADb2C711129d4f3966735eD98a9F09fC4cE57');
      final key = encodeKernelV4NonceKey(
        vMode: KernelV4ValidationMode.enable,
        vType: KernelV4ValidationType.validator,
        vId: validator.hex,
        nonceKey: BigInt.from(0xBEEF),
      );
      expect(
        Hex.fromBigInt(key, byteLength: 24),
        equals(
          '0x0801845adb2c711129d4f3966735ed98a9f09fc4ce57beef',
        ),
      );
    });

    test('rejects keys above two bytes', () {
      expect(
        () => encodeKernelV4NonceKey(nonceKey: BigInt.from(0x10000)),
        throwsArgumentError,
      );
    });

    test('rejects vIds longer than twenty bytes', () {
      expect(
        () => encodeKernelV4NonceKey(
          vType: KernelV4ValidationType.validator,
          vId: '0x${'11' * 21}',
        ),
        throwsArgumentError,
      );
    });
  });

  group('KernelV4Install', () {
    test('rejects a non-positive module type', () {
      expect(
        () => KernelV4Install(
          moduleType: BigInt.zero,
          module: EthereumAddress.fromHex(
            '0x00000000000000000000000000000000DeaDBeef',
          ),
          moduleData: '0x',
        ),
        throwsArgumentError,
      );
    });
  });
}
