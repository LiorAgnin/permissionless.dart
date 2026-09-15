import 'dart:convert';
import 'dart:io';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Vectors generated from the pinned EntryPoint v0.9 Solidity contracts.
/// See `tool/entry_point_v09_vectors/` to regenerate.
Map<String, dynamic> _loadVectors() {
  final file = File('test/fixtures/entry_point_v09_vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BigInt? _bigIntOrNull(Object? value) =>
    value == null ? null : BigInt.from(value as int);

/// Rebuilds the unpacked UserOperation described by a fixture case.
UserOperationV07 _userOpFromCase(Map<String, dynamic> c) => UserOperationV07(
      sender: EthereumAddress.fromHex(c['sender'] as String),
      nonce: BigInt.from(c['nonce'] as int),
      factory: c['factory'] == null
          ? null
          : EthereumAddress.fromHex(c['factory'] as String),
      factoryData: c['factoryData'] as String?,
      callData: c['callData'] as String,
      callGasLimit: BigInt.from(c['callGasLimit'] as int),
      verificationGasLimit: BigInt.from(c['verificationGasLimit'] as int),
      preVerificationGas: BigInt.from(c['preVerificationGas'] as int),
      maxFeePerGas: BigInt.from(c['maxFeePerGas'] as int),
      maxPriorityFeePerGas: BigInt.from(c['maxPriorityFeePerGas'] as int),
      paymaster: c['paymaster'] == null
          ? null
          : EthereumAddress.fromHex(c['paymaster'] as String),
      paymasterVerificationGasLimit:
          _bigIntOrNull(c['paymasterVerificationGasLimit']),
      paymasterPostOpGasLimit: _bigIntOrNull(c['paymasterPostOpGasLimit']),
      paymasterData: c['paymasterData'] as String?,
      paymasterSignature: c['paymasterSignature'] as String?,
    );

void main() {
  final vectors = _loadVectors();
  final cases =
      (vectors['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
  final lookalikes = (vectors['suffixLookalikes'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final chainId = BigInt.from(vectors['chainId'] as int);
  final entryPointV09 =
      EthereumAddress.fromHex(vectors['entryPoint'] as String);

  Map<String, dynamic> caseNamed(String name) =>
      cases.firstWhere((c) => c['name'] == name);

  group('EntryPointVersion.v09', () {
    test('carries the 0.9 version string', () {
      expect(EntryPointVersion.v09.value, equals('0.9'));
    });

    test('maps to the canonical EntryPoint v0.9 address', () {
      expect(
        EntryPointAddresses.v09.hex.toLowerCase(),
        equals('0x433709009b8330fda32311df1c2afa402ed8d009'),
      );
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v09),
        equals(EntryPointAddresses.v09),
      );
    });

    test('matches the address the fixture oracle was generated against', () {
      expect(EntryPointAddresses.v09, equals(entryPointV09));
    });
  });

  group('paymaster signature framing', () {
    test('magic constant matches keccak("PaymasterSignature")[:8]', () {
      expect(
        paymasterSignatureMagic,
        equals(vectors['paymasterSignatureMagic']),
      );
    });

    test('suffix is signature ‖ uint16(length) ‖ magic', () {
      expect(
        encodePaymasterSignatureSuffix('0xaabbcc').toLowerCase(),
        equals('0xaabbcc000322e325a297439656'),
      );
    });

    test('empty signature is rejected rather than silently dropped', () {
      // The contract emits no suffix at all for a zero-length signature...
      expect(vectors['emptyPaymasterSignatureSuffix'], equals('0x'));
      // ...which means '0x' cannot express "a suffix is present". Silently
      // returning no suffix here would produce a userOpHash that disagrees
      // with the one the EntryPoint computes, so this is an error instead.
      expect(
        () => encodePaymasterSignatureSuffix('0x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a signature longer than uint16 can describe', () {
      final tooLong = '0x${'ab' * 65536}';
      expect(
        () => encodePaymasterSignatureSuffix(tooLong),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the stub is a non-empty, ECDSA-shaped 65 bytes', () {
      expect(Hex.byteLength(paymasterSignatureStub), equals(65));
    });

    // paymasterData that resembles a signature suffix must not be mistaken for
    // one. These are plain paymasterData with no paymasterSignature set.
    for (final raw in lookalikes) {
      final name = raw['name'] as String;
      final paymasterAndData = raw['paymasterAndData'] as String;

      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          cases.first['sender'] as String,
        ),
        nonce: BigInt.one,
        callData: '0xabcdef',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
        paymaster: EthereumAddress.fromHex(raw['paymaster'] as String),
        paymasterVerificationGasLimit:
            BigInt.from(raw['paymasterVerificationGasLimit'] as int),
        paymasterPostOpGasLimit:
            BigInt.from(raw['paymasterPostOpGasLimit'] as int),
        paymasterData: raw['paymasterData'] as String,
      );

      test('$name: packs to the expected blob', () {
        expect(
          getPaymasterAndData(userOp).toLowerCase(),
          equals(paymasterAndData.toLowerCase()),
        );
      });

      test('$name: signature length matches the contract', () {
        expect(
          getPaymasterSignatureLength(paymasterAndData),
          equals(raw['paymasterSignatureLength'] as int),
        );
      });

      test('$name: extracted signature matches the contract', () {
        expect(
          getPaymasterSignature(paymasterAndData).toLowerCase(),
          equals((raw['paymasterSignature'] as String).toLowerCase()),
        );
      });

      test('$name: signed paymaster data matches the contract', () {
        expect(
          getSignedPaymasterData(paymasterAndData).toLowerCase(),
          equals((raw['signedPaymasterData'] as String).toLowerCase()),
        );
      });

      test('$name: userOpHash matches the contract', () {
        expect(
          getUserOperationHash(
            userOperation: userOp,
            entryPointAddress: entryPointV09,
            entryPointVersion: EntryPointVersion.v09,
            chainId: chainId,
          ).toLowerCase(),
          equals((raw['expectedUserOpHash'] as String).toLowerCase()),
        );
      });
    }

    test('splice appends a suffix to already-packed paymasterAndData', () {
      final withoutSig =
          caseNamed('paymaster')['expectedPaymasterAndData'] as String;
      final expected =
          caseNamed('paymasterSig65')['expectedPaymasterAndData'] as String;
      final sig = caseNamed('paymasterSig65')['paymasterSignature'] as String;

      expect(
        splicePaymasterSignature(withoutSig, sig).toLowerCase(),
        equals(expected.toLowerCase()),
      );
    });

    test('splice refuses to stack a second suffix', () {
      final withSig =
          caseNamed('paymasterSig65')['expectedPaymasterAndData'] as String;
      expect(
        () => splicePaymasterSignature(withSig, '0xaabbcc'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('EntryPoint v0.9 packing and hashing (Solidity oracle)', () {
    for (final c in cases) {
      final name = c['name'] as String;
      final userOp = _userOpFromCase(c);
      final delegate = c['delegate'] == null
          ? null
          : EthereumAddress.fromHex(c['delegate'] as String);

      test('$name: packs paymasterAndData', () {
        expect(
          getPaymasterAndData(userOp).toLowerCase(),
          equals((c['expectedPaymasterAndData'] as String).toLowerCase()),
        );
      });

      test('$name: packs the hashed initCode', () {
        expect(
          getInitCode(userOp, delegationAddress: delegate).toLowerCase(),
          equals((c['expectedHashedInitCode'] as String).toLowerCase()),
        );
      });

      test('$name: userOpHash matches the contract', () {
        expect(
          getUserOperationHash(
            userOperation: userOp,
            entryPointAddress: entryPointV09,
            entryPointVersion: EntryPointVersion.v09,
            chainId: chainId,
            delegationAddress: delegate,
          ).toLowerCase(),
          equals((c['expectedUserOpHash'] as String).toLowerCase()),
        );
      });
    }
  });

  group('paymaster signature is excluded from the userOpHash', () {
    String hashOf(Map<String, dynamic> c) => getUserOperationHash(
          userOperation: _userOpFromCase(c),
          entryPointAddress: entryPointV09,
          entryPointVersion: EntryPointVersion.v09,
          chainId: chainId,
        ).toLowerCase();

    test('a 65-byte and a 3-byte signature produce the same hash', () {
      expect(
        hashOf(caseNamed('paymasterSig65')),
        equals(hashOf(caseNamed('paymasterSig3'))),
      );
    });

    test('the stub produces the same hash as the real signature', () {
      final real = caseNamed('paymasterSig65');
      final withStub = Map<String, dynamic>.of(real)
        ..['paymasterSignature'] = paymasterSignatureStub;
      expect(hashOf(withStub), equals(hashOf(real)));
    });

    test('but declaring a signature at all does change the hash', () {
      // The magic is folded into the digest whenever a suffix will exist, so a
      // signer must know that a paymaster signature is coming.
      expect(
        hashOf(caseNamed('paymasterSig65')),
        isNot(equals(hashOf(caseNamed('paymaster')))),
      );
    });
  });

  group('v0.6 / v0.7 / v0.8 hashes are unchanged', () {
    // Canonical fixture UserOperation shared with the account test suites.
    // Goldens produced by viem 2.44.4 `getUserOperationHash`.
    final sender =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    final userOpV07 = UserOperationV07(
      sender: sender,
      nonce: BigInt.one,
      callData: '0xabcdef',
      callGasLimit: BigInt.from(100000),
      verificationGasLimit: BigInt.from(200000),
      preVerificationGas: BigInt.from(50000),
      maxFeePerGas: BigInt.from(1000000000),
      maxPriorityFeePerGas: BigInt.from(100000000),
    );

    final userOpV06 = UserOperationV06(
      sender: sender,
      nonce: BigInt.one,
      callData: '0xabcdef',
      callGasLimit: BigInt.from(100000),
      verificationGasLimit: BigInt.from(200000),
      preVerificationGas: BigInt.from(50000),
      maxFeePerGas: BigInt.from(1000000000),
      maxPriorityFeePerGas: BigInt.from(100000000),
    );

    test('v0.6 matches the viem golden', () {
      expect(
        getUserOperationHash(
          userOperation: userOpV06,
          entryPointAddress: EntryPointAddresses.v06,
          entryPointVersion: EntryPointVersion.v06,
          chainId: BigInt.one,
        ).toLowerCase(),
        equals(
          '0xffdc34895415c07d47943f885c27e96cf6da1584195865a99a943da1842e0aa4',
        ),
      );
    });

    test('v0.7 matches the viem golden', () {
      expect(
        getUserOperationHash(
          userOperation: userOpV07,
          entryPointAddress: EntryPointAddresses.v07,
          entryPointVersion: EntryPointVersion.v07,
          chainId: BigInt.one,
        ).toLowerCase(),
        equals(
          '0x37a07d0bd4cc911a7e66dec780a24420f3f8bc52d765817539377d6fc1e1126b',
        ),
      );
    });

    test('v0.8 matches the viem golden', () {
      expect(
        getUserOperationHash(
          userOperation: userOpV07,
          entryPointAddress: EntryPointAddresses.v08,
          entryPointVersion: EntryPointVersion.v08,
          chainId: BigInt.one,
        ).toLowerCase(),
        equals(
          '0x0ad88c6b36c1770a72ec2bfe8ba6f781e597bcfc07c6f237015edcf7adba2d4b',
        ),
      );
    });

    test('v0.9 with no paymaster agrees with viem as well as the contract', () {
      expect(
        getUserOperationHash(
          userOperation: userOpV07,
          entryPointAddress: EntryPointAddresses.v09,
          entryPointVersion: EntryPointVersion.v09,
          chainId: BigInt.one,
        ).toLowerCase(),
        equals(
          '0xe54919a1cc537fa58005313a1fe183dd69248c1d04e0533fa7381b078c11cad6',
        ),
      );
    });

    test('v0.8 and v0.9 differ only by the EntryPoint in the domain', () {
      // Same typed-data construction; the address is the only input that moves.
      final v08 = getUserOperationHash(
        userOperation: userOpV07,
        entryPointAddress: EntryPointAddresses.v08,
        entryPointVersion: EntryPointVersion.v08,
        chainId: BigInt.one,
      );
      final v09AtV08Address = getUserOperationHash(
        userOperation: userOpV07,
        entryPointAddress: EntryPointAddresses.v08,
        entryPointVersion: EntryPointVersion.v09,
        chainId: BigInt.one,
      );
      expect(v09AtV08Address, equals(v08));
    });
  });

  group('the suffix rule is confined to v0.9', () {
    // paymasterData ending in the magic bytes is a v0.9-only signal. Applying
    // it to an earlier version would silently change hashes those EntryPoints
    // have always computed verbatim.
    final lookalike = lookalikes.firstWhere(
      (l) => l['name'] == 'magicWithZeroDeclaredLength',
    );

    UserOperationV07 opWithLookalikeData() => UserOperationV07(
          sender: EthereumAddress.fromHex(cases.first['sender'] as String),
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          paymaster: EthereumAddress.fromHex(lookalike['paymaster'] as String),
          paymasterVerificationGasLimit: BigInt.from(60000),
          paymasterPostOpGasLimit: BigInt.from(70000),
          // Ends with a well-formed-looking suffix, but is only data:
          // 0xdeadbeef, then `d00d` + uint16(2) + the magic.
          paymasterData: '0xdeadbeefd00d000222e325a297439656',
        );

    test('v0.7 hashes paymasterAndData verbatim', () {
      // Recomputed the pre-v0.9 way: keccak over the packed blob, untouched.
      final userOp = opWithLookalikeData();
      final packed = getPaymasterAndData(userOp);

      // The blob does look like it carries a suffix...
      expect(getPaymasterSignatureLength(packed), greaterThan(0));
      // ...but v0.7 must not act on that.
      expect(
        getUserOperationHash(
          userOperation: userOp,
          entryPointAddress: EntryPointAddresses.v07,
          entryPointVersion: EntryPointVersion.v07,
          chainId: BigInt.one,
        ),
        isNot(
          equals(
            getUserOperationHash(
              userOperation: userOp,
              entryPointAddress: EntryPointAddresses.v07,
              entryPointVersion: EntryPointVersion.v09,
              chainId: BigInt.one,
            ),
          ),
        ),
      );
    });

    test('v0.8 hashes paymasterAndData verbatim', () {
      final userOp = opWithLookalikeData();
      final typedData = getUserOperationTypedData(
        userOperation: userOp,
        entryPointAddress: EntryPointAddresses.v08,
        entryPointVersion: EntryPointVersion.v08,
        chainId: BigInt.one,
      );
      expect(
        (typedData.message['paymasterAndData']! as String).toLowerCase(),
        equals(getPaymasterAndData(userOp).toLowerCase()),
      );
    });

    test('v0.9 strips the suffix from the digest', () {
      final userOp = opWithLookalikeData();
      final typedData = getUserOperationTypedData(
        userOperation: userOp,
        entryPointAddress: EntryPointAddresses.v09,
        entryPointVersion: EntryPointVersion.v09,
        chainId: BigInt.one,
      );
      expect(
        (typedData.message['paymasterAndData']! as String).toLowerCase(),
        endsWith(Hex.strip0x(paymasterSignatureMagic)),
      );
      expect(
        (typedData.message['paymasterAndData']! as String).toLowerCase(),
        isNot(equals(getPaymasterAndData(userOp).toLowerCase())),
      );
    });

    test('unpacking leaves a lookalike intact unless asked to split it', () {
      final packed = getPaymasterAndData(opWithLookalikeData());

      final defaultUnpack = unpackPaymasterAndData(packed);
      expect(defaultUnpack.paymasterSignature, isNull);
      expect(
        defaultUnpack.paymasterData!.toLowerCase(),
        equals('0xdeadbeefd00d000222e325a297439656'),
      );

      final v09Unpack =
          unpackPaymasterAndData(packed, parsePaymasterSignature: true);
      expect(v09Unpack.paymasterSignature, isNotNull);
    });
  });

  group('typed data', () {
    test('exposes the ERC4337 domain for v0.8 / v0.9 signing flows', () {
      final typedData = getUserOperationTypedData(
        userOperation: _userOpFromCase(caseNamed('base')),
        entryPointAddress: entryPointV09,
        entryPointVersion: EntryPointVersion.v09,
        chainId: chainId,
      );

      expect(typedData.primaryType, equals('PackedUserOperation'));
      expect(typedData.domain.name, equals('ERC4337'));
      expect(typedData.domain.version, equals('1'));
      expect(typedData.domain.chainId, equals(chainId));
      expect(typedData.domain.verifyingContract, equals(entryPointV09));
    });

    test('struct hash matches the contract', () {
      final c = caseNamed('paymasterSig65');
      final typedData = getUserOperationTypedData(
        userOperation: _userOpFromCase(c),
        entryPointAddress: entryPointV09,
        entryPointVersion: EntryPointVersion.v09,
        chainId: chainId,
      );

      expect(
        hashStruct(
          typedData.primaryType,
          typedData.message,
          typedData.types,
        ).toLowerCase(),
        equals((c['expectedStructHash'] as String).toLowerCase()),
      );
    });
  });

  group('misuse is rejected', () {
    final sender =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    UserOperationV07 opWith({String? paymasterSignature}) => UserOperationV07(
          sender: sender,
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          paymaster: EthereumAddress.fromHex(
            '0x00000000000000000000000000000000000000AA',
          ),
          paymasterVerificationGasLimit: BigInt.from(60000),
          paymasterPostOpGasLimit: BigInt.from(70000),
          paymasterData: '0xd00d',
          paymasterSignature: paymasterSignature,
        );

    test('an empty paymasterSignature is ambiguous and rejected', () {
      // '0x' cannot mean "a suffix with no bytes": the contract reads a
      // zero-length declaration as "no signature" and hashes the magic as data.
      expect(
        () => getPaymasterAndData(opWith(paymasterSignature: '0x')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a paymasterSignature on a pre-v0.9 EntryPoint is rejected', () {
      for (final version in [
        EntryPointVersion.v07,
        EntryPointVersion.v08,
      ]) {
        expect(
          () => getUserOperationHash(
            userOperation: opWith(paymasterSignature: paymasterSignatureStub),
            entryPointAddress: EntryPointAddresses.fromVersion(version),
            entryPointVersion: version,
            chainId: BigInt.one,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'paymasterSignature is meaningless before v0.9',
        );
      }
    });

    test('a v0.6 UserOperation cannot be hashed as v0.7+', () {
      expect(
        () => getUserOperationHash(
          userOperation: UserOperationV06(
            sender: sender,
            nonce: BigInt.one,
            callData: '0xabcdef',
            callGasLimit: BigInt.one,
            verificationGasLimit: BigInt.one,
            preVerificationGas: BigInt.one,
            maxFeePerGas: BigInt.one,
            maxPriorityFeePerGas: BigInt.one,
          ),
          entryPointAddress: EntryPointAddresses.v07,
          entryPointVersion: EntryPointVersion.v07,
          chainId: BigInt.one,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a v0.7 UserOperation cannot be hashed as v0.6', () {
      expect(
        () => getUserOperationHash(
          userOperation: opWith(),
          entryPointAddress: EntryPointAddresses.v06,
          entryPointVersion: EntryPointVersion.v06,
          chainId: BigInt.one,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('JSON-RPC serialization', () {
    final sender =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    UserOperationV07 op({String? paymasterSignature}) => UserOperationV07(
          sender: sender,
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          paymasterSignature: paymasterSignature,
        );

    test('omits paymasterSignature when absent', () {
      expect(op().toJson().containsKey('paymasterSignature'), isFalse);
    });

    test('emits paymasterSignature when present', () {
      expect(
        op(paymasterSignature: paymasterSignatureStub).toJson(),
        containsPair('paymasterSignature', paymasterSignatureStub),
      );
    });

    test('round-trips through fromJson', () {
      final json = op(paymasterSignature: paymasterSignatureStub).toJson();
      expect(
        UserOperationV07.fromJson(json).paymasterSignature,
        equals(paymasterSignatureStub),
      );
    });

    test('copyWith carries paymasterSignature', () {
      expect(
        op().copyWith(paymasterSignature: '0xaabbcc').paymasterSignature,
        equals('0xaabbcc'),
      );
    });
  });

  group('unpacking recovers the paymaster signature', () {
    test('splits a suffixed paymasterAndData back into its parts', () {
      final c = caseNamed('paymasterSig65');
      final unpacked = unpackPaymasterAndData(
        c['expectedPaymasterAndData'] as String,
        parsePaymasterSignature: true,
      );

      expect(
        unpacked.paymaster!.hex.toLowerCase(),
        equals((c['paymaster'] as String).toLowerCase()),
      );
      expect(
        unpacked.paymasterVerificationGasLimit,
        equals(BigInt.from(60000)),
      );
      expect(unpacked.paymasterPostOpGasLimit, equals(BigInt.from(70000)));
      expect(
        unpacked.paymasterData!.toLowerCase(),
        equals((c['paymasterData'] as String).toLowerCase()),
      );
      expect(
        unpacked.paymasterSignature!.toLowerCase(),
        equals((c['paymasterSignature'] as String).toLowerCase()),
      );
    });

    test('reports no signature when there is no suffix', () {
      final unpacked = unpackPaymasterAndData(
        caseNamed('paymaster')['expectedPaymasterAndData'] as String,
        parsePaymasterSignature: true,
      );
      expect(unpacked.paymasterSignature, isNull);
    });

    test('round-trips every fixture case through pack and unpack', () {
      for (final c in cases.where((c) => c['paymaster'] != null)) {
        final userOp = _userOpFromCase(c);
        final unpacked = unpackPaymasterAndData(
          getPaymasterAndData(userOp),
          parsePaymasterSignature: true,
        );

        final name = c['name'] as String;
        expect(unpacked.paymaster, equals(userOp.paymaster), reason: name);
        expect(
          unpacked.paymasterData?.toLowerCase(),
          equals(userOp.paymasterData?.toLowerCase()),
          reason: name,
        );
        expect(
          unpacked.paymasterSignature?.toLowerCase(),
          equals(userOp.paymasterSignature?.toLowerCase()),
          reason: name,
        );
      }
    });
  });
}
