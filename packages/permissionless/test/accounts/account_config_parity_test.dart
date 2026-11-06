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
    // nonceKey is what SmartAccountClient passes to EntryPoint.getNonce.
    // The full uint192 range must pass through untouched.
    final key = (BigInt.one << 192) - BigInt.one;

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

      // permissionless.js getNonceKeyWithEncoding: validator (20) ‖ mode 00
      // ‖ type 00 ‖ key (2). cast concat-hex \
      //   0x0740Ed7c11b9da33d9C80Bd76b826e4E90CC1906 0x00 0x00 0x00ab
      expect(
        account.nonceKey,
        equals(
          BigInt.parse('0x0740ed7c11b9da33d9c80bd76b826e4e90cc1906000000ab'),
        ),
      );
    });

    test('Nexus: 3-byte key slot (key % 16777215) || mode || validator', () {
      final userKey = BigInt.from(0x123456);
      final account = createNexusSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        nonceKey: userKey,
      );

      // permissionless.js toNexusSmartAccount getNonce: key (3) ‖ mode 00
      // ‖ K1 validator. cast concat-hex \
      //   0x123456 0x00 0x00000004171351c442B202678c48D8AB5B321E8f
      expect(
        account.nonceKey,
        equals(
          BigInt.parse('0x1234560000000004171351c442b202678c48d8ab5b321e8f'),
        ),
      );
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

      // cast concat-hex \
      //   0x000005 0x00 0x00000004171351c442B202678c48D8AB5B321E8f
      expect(
        account.nonceKey,
        equals(
          BigInt.parse('0x0000050000000004171351c442b202678c48d8ab5b321e8f'),
        ),
      );
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

      // permissionless.js kernel getNonceKeyWithEncoding: mode 00 ‖ type 00
      // ‖ v0.3.1 ECDSA validator ‖ key (2). cast concat-hex \
      //   0x00 0x00 0x845ADb2C711129d4f3966735eD98a9F09fC4cE57 0x00ab
      expect(
        account.nonceKey,
        equals(
          BigInt.parse('0x0000845adb2c711129d4f3966735ed98a9f09fc4ce5700ab'),
        ),
      );
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

  group('EntryPoint address override reaches the signed userOp hash', () {
    // Expected values: published permissionless.js 0.3.5 (viem 2.44.4),
    // to<Account>SmartAccount({ client /* mainnet */, owner(s): Hardhat #0,
    //   address: 0x1111…1111,
    //   entryPoint: { address: 0x2222…2222, version } })
    //   .signUserOperation(op)
    UserOperationV07 op07() => UserOperationV07(
          sender: mockAddress,
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
        );

    // personal_sign(getUserOperationHash(op, ep: 0x2222…, v0.7, chainId 1))
    const personalSignedV07 =
        '0xbe374421b82771da251b6368f9649cfbb28dffc496fbcfd0f217c9430b9b28be77748dbbf19036d2203c0d40dc4571f6a2333028ba64790608aa7b00691f1ea81c';

    test('Simple', () async {
      final account = createSimpleSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(await account.signUserOperation(op07()), personalSignedV07);
    });

    test('Nexus', () async {
      final account = createNexusSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(await account.signUserOperation(op07()), personalSignedV07);
    });

    test('Etherspot', () async {
      final account = createEtherspotSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      expect(await account.signUserOperation(op07()), personalSignedV07);
    });

    test('Trust (v0.6)', () async {
      final account = createTrustSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      final op = UserOperationV06(
        sender: mockAddress,
        nonce: BigInt.one,
        initCode: '0x',
        callData: '0xabcdef',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
        paymasterAndData: '0x',
      );
      expect(
        await account.signUserOperationV06(op),
        '0xfc80394a60fc31945a42c8f9e1b695a8ff5209f770da1d176a50e4985a2390ef487e14cf079724ecc109c94b51b6324824e07ebb39b24567e92b44b30ebda46c1b',
      );
    });

    test('Safe 1.4.1 (SafeOp entryPoint field)', () async {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: mockAddress,
        entryPointAddress: customEntryPoint,
      );
      // validAfter (6) ‖ validUntil (6) ‖ EIP-712 SafeOp signature
      expect(
        await account.signUserOperation(op07()),
        '0x000000000000000000000000476588e5a0dc4e7e8b9ebfd25f3ec90b8673fe85f3df31a0a0c1213095ec9ff770b429f8083d1d0dbc741e65d95b498e6cf1d53c65caf6f27d2e816d888613261c',
      );
    });
  });

  group('decodeCalls round-trip', () {
    void expectCallEqual(Call actual, Call expected) {
      expect(
        actual.to.hex.toLowerCase(),
        equals(expected.to.hex.toLowerCase()),
      );
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
      expect(
        decoded[0].to.hex.toLowerCase(),
        equals(sampleCalls[0].to.hex.toLowerCase()),
      );
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

  // No permissionless.js vector for Simple: JS Simple throws on signMessage
  // ("isn't 1271 compliant"), while Dart personal-signs hashMessage(message),
  // applying EIP-191 twice. Which behavior is right is open, so only the
  // sign → signMessage delegation is checked here.
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
  });

  group('sign(hash) matches permissionless.js sign({ hash })', () {
    // permissionless.js 0.3.5 (viem 2.44.4): sign({ hash }) is
    // signMessage({ message: hash }), the hash taken as UTF-8 text. Account
    // 0x1111…1111 on mainnet, reported as deployed (no ERC-6492 wrapper).
    const hash =
        '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';

    test('Safe 1.4.1', () async {
      final account = createSafeSmartAccount(
        owners: [owner],
        chainId: chainId,
        address: mockAddress,
      );
      expect(
        await account.sign(hash),
        '0x3ee7704168486ab02e3e50004775942c39d7a8897a3e8095ec0eaeb923c0efa723f217a266c8951551d005bf37e04b436760a976bbfb9bca897c08d7ed7eca2420',
      );
    });

    test('Light 2.0.0', () async {
      final account = createLightSmartAccount(
        owner: owner,
        chainId: chainId,
        address: mockAddress,
      );
      expect(
        await account.sign(hash),
        '0x00fe3ab0b644ca84701f2aae7c325b0f81c175ca99632d932126a2e5a1794e2ac9201b768e9c46b3513aa25266e657bdb61f2c24db315981065cd45af018a2d6f61b',
      );
    });
  });
}
