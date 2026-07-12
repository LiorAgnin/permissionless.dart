import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Ticket 014 — library-wide account config/API parity:
/// decodeCalls, sign(hash), configurable nonceKey, EntryPoint override.
void main() {
  // Hardhat account #0
  final owner = PrivateKeyOwner(
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  );
  final mockAddress =
      EthereumAddress.fromHex('0x1111111111111111111111111111111111111111');
  final chainId = BigInt.from(1);
  final customEntryPoint =
      EthereumAddress.fromHex('0x2222222222222222222222222222222222222222');

  final sampleCall = Call(
    to: EthereumAddress.fromHex('0x3333333333333333333333333333333333333333'),
    value: BigInt.from(42),
    data: '0xabcdef',
  );
  final sampleCalls = [
    sampleCall,
    Call(
      to: EthereumAddress.fromHex('0x4444444444444444444444444444444444444444'),
      value: BigInt.from(7),
      data: '0xdead',
    ),
  ];

  group('defaults unchanged (nonceKey = 0 / canonical EP)', () {
    test('Simple defaults to zero nonceKey and canonical EP', () {
      final account = createSimpleSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      expect(account.nonceKey, equals(BigInt.zero));
      expect(account.entryPoint, equals(EntryPointAddresses.v07));
    });

    test('Light defaults to zero nonceKey and canonical EP', () {
      final account = createLightSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      expect(account.nonceKey, equals(BigInt.zero));
      expect(account.entryPoint, equals(EntryPointAddresses.v07));
    });

    test('Safe defaults to zero nonceKey and canonical EP', () {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: mockAddress,
      );
      expect(account.nonceKey, equals(BigInt.zero));
      expect(account.entryPoint, equals(EntryPointAddresses.v07));
    });

    test('Trust defaults to zero nonceKey and canonical EP v0.6', () {
      final account = createTrustSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      expect(account.nonceKey, equals(BigInt.zero));
      expect(account.entryPoint, equals(EntryPointAddresses.v06));
    });

    test('Thirdweb defaults to zero nonceKey and canonical EP', () {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      expect(account.nonceKey, equals(BigInt.zero));
      expect(account.entryPoint, equals(EntryPointAddresses.v07));
    });
  });

  group('configurable nonceKey (passthrough accounts)', () {
    final key = BigInt.from(0x1234);

    test('Simple uses full key', () {
      final account = createSimpleSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: key,
      );
      expect(account.nonceKey, equals(key));
    });

    test('Light uses full key', () {
      final account = createLightSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: key,
      );
      expect(account.nonceKey, equals(key));
    });

    test('Safe uses full key', () {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: mockAddress,
        nonceKey: key,
      );
      expect(account.nonceKey, equals(key));
    });

    test('Biconomy uses full key', () {
      // ignore: deprecated_member_use_from_same_package
      final account = createBiconomySmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: key,
      );
      expect(account.nonceKey, equals(key));
    });

    test('Thirdweb uses full key', () {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: key,
      );
      expect(account.nonceKey, equals(key));
    });

    test('Trust uses full key', () {
      final account = createTrustSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: key,
      );
      expect(account.nonceKey, equals(key));
    });
  });

  group('encoded nonceKey (byte-match JS)', () {
    test('Etherspot: 2-byte suffix in 24-byte encoding', () {
      final userKey = BigInt.from(0x00ab);
      final account = createEtherspotSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: userKey,
      );

      // validator (20) || mode 00 || type 00 || key (2)
      final validatorHex =
          Hex.strip0x(EtherspotAddresses.ecdsaValidator.hex).toLowerCase();
      final expected = BigInt.parse(
        '${validatorHex}00'
        '00'
        '${Hex.strip0x(Hex.fromBigInt(userKey, byteLength: 2))}',
        radix: 16,
      );
      expect(account.nonceKey, equals(expected));
    });

    test('Nexus: 3-byte key slot (key % 16777215) || mode || validator', () {
      final userKey = BigInt.from(0x123456);
      final account = createNexusSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: userKey,
      );

      const timestampAdjustment = 16777215;
      final defaultedKey = userKey % BigInt.from(timestampAdjustment);
      final keyHex = Hex.fromBigInt(defaultedKey, byteLength: 3);
      final validatorHex = Hex.strip0x(NexusAddresses.k1Validator.hex);
      final packed = Hex.concat([keyHex, '0x00', validatorHex]);
      expect(account.nonceKey, equals(Hex.toBigInt(packed)));
    });

    test('Nexus wraps key above 3-byte max', () {
      // 16777215 + 5 → 5
      final userKey = BigInt.from(16777215 + 5);
      final account = createNexusSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: userKey,
      );

      final defaultedKey = BigInt.from(5);
      final keyHex = Hex.fromBigInt(defaultedKey, byteLength: 3);
      final validatorHex = Hex.strip0x(NexusAddresses.k1Validator.hex);
      final packed = Hex.concat([keyHex, '0x00', validatorHex]);
      expect(account.nonceKey, equals(Hex.toBigInt(packed)));
    });

    test('Kernel v0.3.x: mode||type||validator||2-byte salt', () {
      final userKey = BigInt.from(0x00ab);
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        version: KernelVersion.v0_3_1,
        nonceKey: userKey,
      );

      final validator =
          KernelVersionAddresses.getAddresses(KernelVersion.v0_3_1)!
              .ecdsaValidator!;
      final bytes = Uint8List(24)
        ..[0] = 0x00 // sudo
        ..[1] = 0x00 // root
        ..setRange(2, 22, validator.bytes);
      final salt = Hex.decode(Hex.fromBigInt(userKey, byteLength: 2));
      bytes[22] = salt[0];
      bytes[23] = salt[1];
      expect(account.nonceKey, equals(Hex.toBigInt(Hex.fromBytes(bytes))));
    });

    test('Kernel v0.3.x rejects nonceKey > maxUint16', () {
      expect(
        () => createKernelSmartAccount(
          owner: owner,
          chainId: chainId,
          address: mockAddress,
          version: KernelVersion.v0_3_1,
          nonceKey: BigInt.from(0x10000),
        ),
        throwsArgumentError,
      );
    });

    test('Kernel v0.2.4: passthrough nonceKey', () {
      final userKey = BigInt.from(0xdeadbeef);
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        version: KernelVersion.v0_2_4,
        nonceKey: userKey,
      );
      expect(account.nonceKey, equals(userKey));
    });
  });

  group('EntryPoint address override', () {
    test('Simple honors entryPointAddress', () {
      final account = createSimpleSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(account.entryPoint, equals(customEntryPoint));
    });

    test('Nexus honors entryPointAddress', () {
      final account = createNexusSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(account.entryPoint, equals(customEntryPoint));
    });

    test('Etherspot honors entryPointAddress', () {
      final account = createEtherspotSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(account.entryPoint, equals(customEntryPoint));
    });

    test('Trust honors entryPointAddress', () {
      final account = createTrustSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(account.entryPoint, equals(customEntryPoint));
    });

    test('Safe honors entryPointAddress', () {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(account.entryPoint, equals(customEntryPoint));
    });
  });

  group('decodeCalls round-trip', () {
    void expectCallEqual(Call actual, Call expected) {
      expect(
          actual.to.hex.toLowerCase(), equals(expected.to.hex.toLowerCase()));
      expect(actual.value, equals(expected.value));
      expect(
        Hex.strip0x(actual.data).toLowerCase(),
        equals(Hex.strip0x(expected.data).toLowerCase()),
      );
    }

    test('Simple v0.7 single + batch', () {
      final account = createSimpleSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      final single = account.encodeCall(sampleCall);
      final decodedSingle = account.decodeCalls(single);
      expect(decodedSingle, hasLength(1));
      expectCallEqual(decodedSingle.first, sampleCall);

      final batch = account.encodeCalls(sampleCalls);
      final decodedBatch = account.decodeCalls(batch);
      expect(decodedBatch, hasLength(2));
      expectCallEqual(decodedBatch[0], sampleCalls[0]);
      expectCallEqual(decodedBatch[1], sampleCalls[1]);
    });

    test('Simple v0.6 batch uses address[]/bytes[]', () {
      final account = createSimpleSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointVersion: EntryPointVersion.v06,
      );
      final batch = account.encodeCalls(sampleCalls);
      final decoded = account.decodeCalls(batch);
      expect(decoded, hasLength(2));
      // v0.6 batch has no values array — decoded values are zero
      expect(decoded[0].to.hex.toLowerCase(),
          equals(sampleCalls[0].to.hex.toLowerCase()));
      expect(decoded[0].value, equals(BigInt.zero));
      expect(
        Hex.strip0x(decoded[0].data).toLowerCase(),
        equals(Hex.strip0x(sampleCalls[0].data).toLowerCase()),
      );
    });

    test('Light single + batch', () {
      final account = createLightSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      final decoded = account.decodeCalls(account.encodeCall(sampleCall));
      expect(decoded, hasLength(1));
      expectCallEqual(decoded.first, sampleCall);

      final batchDecoded =
          account.decodeCalls(account.encodeCalls(sampleCalls));
      expect(batchDecoded, hasLength(2));
      expectCallEqual(batchDecoded[0], sampleCalls[0]);
      expectCallEqual(batchDecoded[1], sampleCalls[1]);
    });

    test('Nexus ERC-7579 single + batch', () {
      final account = createNexusSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      final decoded = account.decodeCalls(account.encodeCall(sampleCall));
      expect(decoded, hasLength(1));
      expectCallEqual(decoded.first, sampleCall);

      final batchDecoded =
          account.decodeCalls(account.encodeCalls(sampleCalls));
      expect(batchDecoded, hasLength(2));
      expectCallEqual(batchDecoded[0], sampleCalls[0]);
      expectCallEqual(batchDecoded[1], sampleCalls[1]);
    });

    test('Etherspot ERC-7579', () {
      final account = createEtherspotSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      final decoded = account.decodeCalls(account.encodeCalls(sampleCalls));
      expect(decoded, hasLength(2));
      expectCallEqual(decoded[0], sampleCalls[0]);
      expectCallEqual(decoded[1], sampleCalls[1]);
    });

    test('Kernel v0.3.x ERC-7579', () {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        version: KernelVersion.v0_3_1,
      );
      final decoded = account.decodeCalls(account.encodeCalls(sampleCalls));
      expect(decoded, hasLength(2));
      expectCallEqual(decoded[0], sampleCalls[0]);
      expectCallEqual(decoded[1], sampleCalls[1]);
    });

    test('Kernel v0.2.4 execute / executeBatch', () {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        version: KernelVersion.v0_2_4,
      );
      final single = account.decodeCalls(account.encodeCall(sampleCall));
      expect(single, hasLength(1));
      expectCallEqual(single.first, sampleCall);

      final batch = account.decodeCalls(account.encodeCalls(sampleCalls));
      expect(batch, hasLength(2));
      expectCallEqual(batch[0], sampleCalls[0]);
      expectCallEqual(batch[1], sampleCalls[1]);
    });

    test('Biconomy execute_ncC / executeBatch_y6U', () {
      // ignore: deprecated_member_use_from_same_package
      final account = createBiconomySmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      final single = account.decodeCalls(account.encodeCall(sampleCall));
      expect(single, hasLength(1));
      expectCallEqual(single.first, sampleCall);

      final batch = account.decodeCalls(account.encodeCalls(sampleCalls));
      expect(batch, hasLength(2));
      expectCallEqual(batch[0], sampleCalls[0]);
      expectCallEqual(batch[1], sampleCalls[1]);
    });

    test('Safe standard mode single + MultiSend batch', () {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: mockAddress,
      );
      final single = account.decodeCalls(account.encodeCall(sampleCall));
      expect(single, hasLength(1));
      expectCallEqual(single.first, sampleCall);

      final batch = account.decodeCalls(account.encodeCalls(sampleCalls));
      expect(batch, hasLength(2));
      expectCallEqual(batch[0], sampleCalls[0]);
      expectCallEqual(batch[1], sampleCalls[1]);
    });

    test('Thirdweb / Trust standard execute', () {
      final thirdweb = createThirdwebSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      final trust = createTrustSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );

      for (final account in [thirdweb, trust]) {
        final single = account.decodeCalls(account.encodeCall(sampleCall));
        expect(single, hasLength(1));
        expectCallEqual(single.first, sampleCall);

        final batch = account.decodeCalls(account.encodeCalls(sampleCalls));
        expect(batch, hasLength(2));
        expectCallEqual(batch[0], sampleCalls[0]);
        expectCallEqual(batch[1], sampleCalls[1]);
      }
    });
  });

  group('sign(hash) matches signMessage(hash)', () {
    test('Simple', () async {
      final account = createSimpleSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      const hash =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      final viaSign = await account.sign(hash);
      final viaMessage = await account.signMessage(hash);
      expect(viaSign, equals(viaMessage));
    });

    test('Safe', () async {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: mockAddress,
      );
      const hash =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      final viaSign = await account.sign(hash);
      final viaMessage = await account.signMessage(hash);
      expect(viaSign, equals(viaMessage));
    });

    test('Light', () async {
      final account = createLightSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      const hash =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      final viaSign = await account.sign(hash);
      final viaMessage = await account.signMessage(hash);
      expect(viaSign, equals(viaMessage));
    });
  });
}
