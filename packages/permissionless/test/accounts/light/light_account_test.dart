import 'package:permissionless/permissionless.dart';
import 'package:permissionless/src/accounts/standard_execute.dart';
import 'package:test/test.dart';

void main() {
  // Mock address for unit tests (avoids RPC calls)
  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  group('Light Account', () {
    group('LightAccountVersion', () {
      test('v110 is for EntryPoint v0.6', () {
        expect(
          LightAccountVersion.forEntryPoint(EntryPointVersion.v06),
          equals(LightAccountVersion.v110),
        );
      });

      test('v200 is for EntryPoint v0.7', () {
        expect(
          LightAccountVersion.forEntryPoint(EntryPointVersion.v07),
          equals(LightAccountVersion.v200),
        );
      });

      test('v110 has version string "1.1.0"', () {
        expect(LightAccountVersion.v110.version, equals('1.1.0'));
      });

      test('v200 has version string "2.0.0"', () {
        expect(LightAccountVersion.v200.version, equals('2.0.0'));
      });
    });

    group('LightAccountFactoryAddresses', () {
      test('v110 factory address is correct', () {
        expect(
          LightAccountFactoryAddresses.v110.hex.toLowerCase(),
          equals('0x00004EC70002a32400f8ae005A26081065620D20'.toLowerCase()),
        );
      });

      test('v200 factory address is correct', () {
        expect(
          LightAccountFactoryAddresses.v200.hex.toLowerCase(),
          equals('0x0000000000400CdFef5E2714E63d8040b700BC24'.toLowerCase()),
        );
      });

      test('fromVersion returns correct factory for v1.1.0', () {
        expect(
          LightAccountFactoryAddresses.fromVersion(LightAccountVersion.v110)
              .hex
              .toLowerCase(),
          equals(LightAccountFactoryAddresses.v110.hex.toLowerCase()),
        );
      });

      test('fromVersion returns correct factory for v2.0.0', () {
        expect(
          LightAccountFactoryAddresses.fromVersion(LightAccountVersion.v200)
              .hex
              .toLowerCase(),
          equals(LightAccountFactoryAddresses.v200.hex.toLowerCase()),
        );
      });
    });

    group('LightAccountSelectors', () {
      // cast sig 'createAccount(address,uint256)'
      test('createAccount matches cast sig', () {
        expect(LightAccountSelectors.createAccount, equals('0x5fbfb9cf'));
      });

      test('are the selectors of the signatures the account encodes', () {
        for (final (selector, signature) in [
          (LightAccountSelectors.execute, executeSignature),
          (
            LightAccountSelectors.executeBatch,
            ExecuteBatchAbi.addressesValuesAndBytes.signature
          ),
          (
            LightAccountSelectors.createAccount,
            lightAccountCreateAccountSignature
          ),
        ]) {
          expect(
            selector,
            AbiEncoder.functionSelector(signature),
            reason: signature,
          );
        }
      });
    });

    group('LightAccountSignatureType', () {
      test('EOA signature type is 0x00', () {
        expect(LightAccountSignatureType.eoa, equals(0x00));
      });

      test('contract signature type is 0x01', () {
        expect(LightAccountSignatureType.contract, equals(0x01));
      });

      test('contractWithAddr signature type is 0x02', () {
        expect(LightAccountSignatureType.contractWithAddr, equals(0x02));
      });
    });

    group('LightSmartAccount', () {
      late PrivateKeyOwner owner;

      setUp(() {
        owner = PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );
      });

      test(
          'v2.0.0 factoryData is createAccount(owner, 0) on the v2.0.0 factory',
          () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          address: mockAddress,
        );

        final factoryData = (await account.getFactoryData())!;

        expect(factoryData.factory, equals(LightAccountFactoryAddresses.v200));
        // cast calldata "createAccount(address,uint256)" <owner> 0
        expect(
          factoryData.factoryData.toLowerCase(),
          equals(
            '0x5fbfb9cf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('salt is the createAccount salt', () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          salt: BigInt.from(12345),
          address: mockAddress,
        );

        // cast calldata "createAccount(address,uint256)" <owner> 12345
        expect(
          (await account.getFactoryData())!.factoryData.toLowerCase(),
          equals(
            '0x5fbfb9cf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000003039',
          ),
        );
      });

      test('v1.1.0 initCode is the v1.1.0 factory ++ createAccount(owner, 0)',
          () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        // cast concat-hex 0x00004EC70002a32400f8ae005A26081065620D20 \
        //   $(cast calldata "createAccount(address,uint256)" <owner> 0)
        expect(
          (await account.getInitCode()).toLowerCase(),
          equals(
            '0x00004ec70002a32400f8ae005a26081065620d205fbfb9cf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('encodeCall encodes execute(to, value, data)', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          address: mockAddress,
        );

        final callData = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000),
            data: '0xabcd',
          ),
        );

        // cast calldata "execute(address,uint256,bytes)" \
        //   0x1234567890123456789012345678901234567890 1000 0xabcd
        expect(
          callData.toLowerCase(),
          equals(
            '0xb61d27f6000000000000000000000000123456789012345678901234567890123456789000000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000002abcd000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('encodeCalls encodes executeBatch(address[],uint256[],bytes[])', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          address: mockAddress,
        );

        final callData = account.encodeCalls([
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.from(100),
            data: '0xaabb',
          ),
        ]);

        // cast calldata "executeBatch(address[],uint256[],bytes[])" \
        //   "[0x1111…1111,0x2222…2222]" "[0,100]" "[0x,0xaabb]"
        expect(
          callData.toLowerCase(),
          equals(
            '0x47e1da2a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000020000000000000000000000001111111111111111111111111111111111111111000000000000000000000000222222222222222222222222222222222222222200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002aabb000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      // permissionless.js toLightSmartAccount getStubSignature(): the ECDSA
      // dummy, prefixed with SignatureType.EOA (0x00) on 2.0.0.
      const ecdsaDummy =
          '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

      test('v1.1.0 stub signature is the bare ECDSA dummy', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        expect(account.getStubSignature(), equals(ecdsaDummy));
      });

      test('v2.0.0 stub signature is 0x00 ++ ECDSA dummy', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          address: mockAddress,
        );

        // cast concat-hex 0x00 <ecdsaDummy>
        expect(
          account.getStubSignature(),
          equals(
            '0x00fffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c',
          ),
        );
      });
    });

    group('signUserOperation', () {
      late PrivateKeyOwner owner;

      setUp(() {
        owner = PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );
      });

      UserOperationV07 fixtureUserOpV07(EthereumAddress sender) =>
          UserOperationV07(
            sender: sender,
            nonce: BigInt.one,
            callData: '0xabcdef',
            callGasLimit: BigInt.from(100000),
            verificationGasLimit: BigInt.from(200000),
            preVerificationGas: BigInt.from(50000),
            maxFeePerGas: BigInt.from(1000000000),
            maxPriorityFeePerGas: BigInt.from(100000000),
            signature: '0x',
          );

      UserOperationV06 fixtureUserOpV06(EthereumAddress sender) =>
          UserOperationV06(
            sender: sender,
            nonce: BigInt.one,
            initCode: '0x',
            callData: '0xabcdef',
            callGasLimit: BigInt.from(100000),
            verificationGasLimit: BigInt.from(200000),
            preVerificationGas: BigInt.from(50000),
            maxFeePerGas: BigInt.from(1000000000),
            maxPriorityFeePerGas: BigInt.from(100000000),
            paymasterAndData: '0x',
            signature: '0x',
          );

      test('v0.6 personal-signs v0.6 userOpHash matching viem fixture',
          () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        final signature =
            await account.signUserOperationV06(fixtureUserOpV06(mockAddress));

        // viem getUserOperationHash (v0.6) + signMessage({ raw: hash })
        // Light v1.1.0 has no signature-type prefix.
        expect(
          signature.toLowerCase(),
          equals(
            '0x722cff5408f0bfb44be7b89c1352926b788b13e3aab3ca90eba3f140541ef0e84f013c007081d3f0d27f5fccbdb10d1d33c7582f930504f7b874134d1781c55d1b',
          ),
        );
      });

      test('v0.6 throws when signUserOperation (v0.7 API) is used', () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        expect(
          () => account.signUserOperation(fixtureUserOpV07(mockAddress)),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('v0.7 throws when signUserOperationV06 is used', () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v07,
          address: mockAddress,
        );

        expect(
          () => account.signUserOperationV06(fixtureUserOpV06(mockAddress)),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });
    group('version / EntryPoint combinations', () {
      // permissionless.js LightAccountVersion<ep>: "0.6" -> "1.1.0",
      // "0.7" -> "2.0.0"; no other pairing exists.
      final owner = PrivateKeyOwner(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );

      for (final (version, entryPointVersion) in [
        (LightAccountVersion.v110, EntryPointVersion.v06),
        (LightAccountVersion.v200, EntryPointVersion.v07),
      ]) {
        test(
            'accepts ${version.version} with EntryPoint '
            '${entryPointVersion.value}', () {
          final account = createLightSmartAccount(
            owner: owner,
            chainId: BigInt.one,
            version: version,
            entryPointVersion: entryPointVersion,
            address: mockAddress,
          );
          expect(account.version, equals(version));
          expect(account.entryPointVersion, equals(entryPointVersion));
        });
      }

      for (final (version, entryPointVersion) in [
        (LightAccountVersion.v110, EntryPointVersion.v07),
        (LightAccountVersion.v110, EntryPointVersion.v08),
        (LightAccountVersion.v200, EntryPointVersion.v06),
        (LightAccountVersion.v200, EntryPointVersion.v08),
      ]) {
        test(
            'rejects ${version.version} with EntryPoint '
            '${entryPointVersion.value}', () {
          expect(
            () => createLightSmartAccount(
              owner: owner,
              chainId: BigInt.one,
              version: version,
              entryPointVersion: entryPointVersion,
              address: mockAddress,
            ),
            throwsArgumentError,
          );
        });
      }
    });
  });
}
