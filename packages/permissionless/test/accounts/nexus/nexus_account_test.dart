import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  // Hardhat account 0 — do not use in production
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  // Fixed UserOperation fields matching permissionless.js / viem fixture
  // (chainId=1, sender=mockAddress, no factory/paymaster).
  //
  // JS fixture (viem getUserOperationHash + localOwner.signMessage raw hash):
  // userOpHash: 0x152aa3402c1452b6e84bd92cdf80a83d4a93c90fa5bf441053bb90075df2191d
  // signature:  0x00538c3d1fb4197de5a15394fcaf23ca1a570c63576424c0615656be0e112f5964840719f944a8d5b0e21ad3a262725d1004ac6a9926ac6299b3f48d1c0c0d8d1b
  const jsFixtureUserOpSignature =
      '0x00538c3d1fb4197de5a15394fcaf23ca1a570c63576424c0615656be0e112f59'
      '64840719f944a8d5b0e21ad3a262725d1004ac6a9926ac6299b3f48d1c0c0d8d1b';

  UserOperationV07 fixtureUserOp(EthereumAddress sender) => UserOperationV07(
        sender: sender,
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

  group('NexusAddresses', () {
    test('k1ValidatorFactory address matches permissionless.js', () {
      expect(
        NexusAddresses.k1ValidatorFactory.hex.toLowerCase(),
        equals('0x00000bb19a3579f4d779215def97afbd0e30db55'),
      );
    });

    test('k1Validator address matches permissionless.js', () {
      expect(
        NexusAddresses.k1Validator.hex.toLowerCase(),
        equals('0x00000004171351c442b202678c48d8ab5b321e8f'),
      );
    });
  });

  group('NexusSelectors', () {
    test('createAccount selector is correct', () {
      // keccak256("createAccount(address,uint256,address[],uint8)")[0:4]
      expect(NexusSelectors.createAccount, equals('0x0d51f0b7'));
    });

    test('computeAccountAddress selector is correct', () {
      // keccak256("computeAccountAddress(address,uint256,address[],uint8)")[0:4]
      expect(NexusSelectors.computeAccountAddress, equals('0x322cc8ca'));
    });
  });

  group('NexusSmartAccount', () {
    late PrivateKeyOwner owner;
    late NexusSmartAccount account;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      account = createNexusSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        address: mockAddress,
      );
    });

    group('creation', () {
      test('creates account with defaults for EntryPoint v0.7', () {
        expect(account.owner, equals(owner));
        expect(account.chainId, equals(BigInt.one));
        expect(account.entryPointVersion, equals(EntryPointVersion.v07));
        expect(account.index, equals(BigInt.zero));
      });

      test('getAddress returns configured address', () async {
        final address = await account.getAddress();
        expect(
            address.hex.toLowerCase(), equals(mockAddress.hex.toLowerCase()));
      });
    });

    group('signUserOperation', () {
      test('returns bare 65-byte ECDSA signature (no validator prefix)',
          () async {
        final signature =
            await account.signUserOperation(fixtureUserOp(mockAddress));

        expect(signature, startsWith('0x'));
        // 65 bytes = 130 hex chars + 0x prefix
        expect(signature.length, equals(132));
        expect((signature.length - 2) ~/ 2, equals(65));
      });

      test('does not prepend K1 validator address', () async {
        final signature =
            await account.signUserOperation(fixtureUserOp(mockAddress));

        final validatorHex =
            Hex.strip0x(NexusAddresses.k1Validator.hex).toLowerCase();
        final sigBody = Hex.strip0x(signature).toLowerCase();

        // Bug was packing validator (20B) + sig (65B) = 85B starting with validator
        expect(sigBody.startsWith(validatorHex), isFalse);
        expect(signature.length, isNot(equals(172))); // 85 bytes + 0x
      });

      test('byte-matches permissionless.js for same key and userOp', () async {
        final signature =
            await account.signUserOperation(fixtureUserOp(mockAddress));

        expect(
          signature.toLowerCase(),
          equals(jsFixtureUserOpSignature.toLowerCase()),
        );
      });
    });

    group('signMessage (ERC-1271)', () {
      test('still packs validator address + 65-byte signature', () async {
        final signature = await account.signMessage('hello nexus');

        expect(signature, startsWith('0x'));
        // 20-byte validator + 65-byte ECDSA = 85 bytes = 170 hex + 0x
        expect(signature.length, equals(172));
        expect((signature.length - 2) ~/ 2, equals(85));

        final validatorHex =
            Hex.strip0x(NexusAddresses.k1Validator.hex).toLowerCase();
        final sigBody = Hex.strip0x(signature).toLowerCase();
        expect(sigBody.startsWith(validatorHex), isTrue);
      });
    });

    group('getStubSignature', () {
      test('includes validator address for gas estimation', () {
        final stub = account.getStubSignature();
        expect(stub, startsWith('0x'));
        final validatorHex =
            Hex.strip0x(NexusAddresses.k1Validator.hex).toLowerCase();
        expect(Hex.strip0x(stub).toLowerCase().contains(validatorHex), isTrue);
      });
    });
  });
}
