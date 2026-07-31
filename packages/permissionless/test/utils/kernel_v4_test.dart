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

    final nonceKeyCases =
        (vectors['nonceKeys'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final c in nonceKeyCases) {
      test('matches the contract-side key packing for case ${c['name']}', () {
        final key = encodeKernelV4NonceKey(
          vMode: c['vMode'] as int,
          vType: c['vType'] as int,
          vId: c['vId'] as String,
          nonceKey: BigInt.from(c['nonceKey'] as int),
        );
        expect(key, equals(BigInt.parse(c['key'] as String)));
      });
    }
  });

  group('decodeKernelV4Nonce', () {
    final nonceKeyCases =
        (vectors['nonceKeys'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final c in nonceKeyCases) {
      test('unpacks the fixture nonce for case ${c['name']}', () {
        final decoded = decodeKernelV4Nonce(BigInt.parse(c['nonce'] as String));
        expect(decoded.vMode, equals(c['vMode']));
        expect(decoded.vType, equals(c['vType']));
        expect(decoded.vId, equals(c['vId']));
        expect(decoded.nonceKey, equals(BigInt.from(c['nonceKey'] as int)));
        expect(decoded.sequence, equals(BigInt.from(c['sequence'] as int)));
      });
    }

    test('roundtrips an encoded key with a sequence', () {
      final validator =
          EthereumAddress.fromHex('0x845ADb2C711129d4f3966735eD98a9F09fC4cE57');
      final key = encodeKernelV4NonceKey(
        vMode: KernelV4ValidationMode.replayableUserOpHash,
        vType: KernelV4ValidationType.validator,
        vId: validator.hex,
        nonceKey: BigInt.from(0xBEEF),
      );
      final decoded = decodeKernelV4Nonce((key << 64) | BigInt.from(12345));
      expect(
        decoded.vMode,
        equals(KernelV4ValidationMode.replayableUserOpHash),
      );
      expect(decoded.vType, equals(KernelV4ValidationType.validator));
      expect(decoded.vId, equals(validator.hex.toLowerCase()));
      expect(decoded.nonceKey, equals(BigInt.from(0xBEEF)));
      expect(decoded.sequence, equals(BigInt.from(12345)));
    });

    test('left-aligns a short permission id into the vId field', () {
      final key = encodeKernelV4NonceKey(
        vType: KernelV4ValidationType.permission,
        vId: '0xdeadbeef',
      );
      final decoded = decodeKernelV4Nonce(key << 64);
      expect(decoded.vId, equals('0xdeadbeef00000000000000000000000000000000'));
    });

    test('rejects a negative nonce', () {
      expect(
        () => decodeKernelV4Nonce(BigInt.from(-1)),
        throwsArgumentError,
      );
    });

    test('rejects a nonce above 32 bytes', () {
      expect(
        () => decodeKernelV4Nonce(BigInt.two.pow(256)),
        throwsArgumentError,
      );
    });
  });

  group('encodeKernelV4PermissionSignature', () {
    final permissionCase = vectors['permissionUserOp'] as Map<String, dynamic>;

    test('byte-matches abi.encode(bytes[]) for the fixture stub list', () {
      // The fixture stub is [policy proof, library dummy ECDSA signature].
      expect(
        encodeKernelV4PermissionSignature(
          policySignatures: [permissionCase['policyData'] as String],
          signerSignature: kernelDummyEcdsaSignature,
        ),
        equals(permissionCase['stubSignature']),
      );
    });

    test('encodes an empty policy list as a one-element array', () {
      // abi.encode(bytes[]) with a single 3-byte entry.
      expect(
        encodeKernelV4PermissionSignature(
          policySignatures: const [],
          signerSignature: '0xc0ffee',
        ),
        equals(
          '0x'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000003'
          'c0ffee0000000000000000000000000000000000000000000000000000000000',
        ),
      );
    });
  });

  group('KernelV4Validation', () {
    final permissionCase = vectors['permissionUserOp'] as Map<String, dynamic>;

    test('root routes to vType 0x00 with no vId and the ECDSA stub', () {
      const validation = KernelV4Validation.root();
      expect(validation.vType, equals(KernelV4ValidationType.root));
      expect(validation.vId, equals('0x'));
      expect(validation.stubSignature, equals(kernelDummyEcdsaSignature));
      expect(validation.wrapSignature('0x1234'), equals('0x1234'));
    });

    test('validator routes to vType 0x01 with the module address as vId', () {
      final validator =
          EthereumAddress.fromHex('0x845ADb2C711129d4f3966735eD98a9F09fC4cE57');
      final validation = KernelV4Validation.validator(validator);
      expect(validation.vType, equals(KernelV4ValidationType.validator));
      expect(validation.vId, equals(validator.hex));
      expect(validation.stubSignature, equals(kernelDummyEcdsaSignature));
      expect(validation.wrapSignature('0x1234'), equals('0x1234'));
    });

    test('validator accepts a custom stub for non-ECDSA modules', () {
      final validation = KernelV4Validation.validator(
        EthereumAddress.fromHex('0x845ADb2C711129d4f3966735eD98a9F09fC4cE57'),
        stubSignature: '0xdeadbeef',
      );
      expect(validation.stubSignature, equals('0xdeadbeef'));
    });

    test('permission routes to vType 0x02 and frames the signature list', () {
      final validation = KernelV4Validation.permission(
        permissionCase['permissionId'] as String,
        policySignatures: [permissionCase['policyData'] as String],
      );
      expect(validation.vType, equals(KernelV4ValidationType.permission));
      expect(validation.vId, equals(permissionCase['permissionId']));
      expect(
        validation.stubSignature,
        equals(permissionCase['stubSignature']),
      );
      expect(
        validation.wrapSignature(kernelDummyEcdsaSignature),
        equals(permissionCase['stubSignature']),
      );
    });

    test('permission rejects an id that is not exactly four bytes', () {
      expect(
        () => KernelV4Validation.permission('0xdeadbe'),
        throwsArgumentError,
      );
      expect(
        () => KernelV4Validation.permission('0xdeadbeef01'),
        throwsArgumentError,
      );
    });

    test('permission nonce key left-aligns the id into the vId field', () {
      final validation = KernelV4Validation.permission(
        permissionCase['permissionId'] as String,
      );
      final key = encodeKernelV4NonceKey(
        vType: validation.vType,
        vId: validation.vId,
        nonceKey: BigInt.from(permissionCase['nonceKey'] as int),
      );
      expect(
        (key << 64).toString(),
        equals(permissionCase['nonce']),
      );
    });
  });

  group('getKernelV4ChainAgnosticUserOpHash', () {
    final r = vectors['replayableUserOp'] as Map<String, dynamic>;
    final entryPoint = EthereumAddress.fromHex(vectors['entryPoint'] as String);
    final chainId = BigInt.from(vectors['chainId'] as int);
    final userOp = kernelV4UserOpFromCase(r);

    test('the standard v0.9 hash still matches the EntryPoint', () {
      expect(
        getUserOperationHash(
          userOperation: userOp,
          entryPointAddress: entryPoint,
          entryPointVersion: EntryPointVersion.v09,
          chainId: chainId,
        ),
        equals(r['standardUserOpHash']),
      );
    });

    test('matches the pinned Lib4337 chain-agnostic digest', () {
      final hash = getKernelV4ChainAgnosticUserOpHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
      );
      expect(hash, equals(r['chainAgnosticUserOpHash']));
      expect(hash, isNot(equals(r['standardUserOpHash'])));
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
