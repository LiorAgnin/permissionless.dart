import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Minimal test-local double for [WebAuthnAccountOwner].
///
/// The real subclasses live in `permissionless_passkeys`; importing that
/// package here would create a reverse dependency. For address-derivation
/// tests we only need stable `x`/`y` (which drive the base-class `address`)
/// and a `credentialId`. `signP256` is never invoked, so it throws.
class _TestWebAuthnOwner extends WebAuthnAccountOwner {
  const _TestWebAuthnOwner(this.x, this.y, this.credentialId);

  @override
  final BigInt x;

  @override
  final BigInt y;

  @override
  final Uint8List credentialId;

  @override
  Future<P256SignatureData> signP256(String hash) {
    throw UnsupportedError('test double: signP256 not implemented');
  }
}

void main() {
  // Test private key (DO NOT use in production!)
  // This is a well-known test key from Foundry/Hardhat
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
  // Mock address for unit tests (avoids RPC calls)
  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  const owner2Key =
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

  // ---- permissionless.js fixtures ----
  // From /Users/liorag/.claude/jobs/037f9518/tmp/t2/safe.ts: permissionless.js
  // toSafeSmartAccount (viem 2.21.55), owners = [privateKeyToAccount(
  // testPrivateKey)], version 1.4.1, EntryPoint v0.7, chainId 1, saltNonce 0
  // unless noted. proxyCreationCode() is answered with the mainnet value of
  // the v1.4.1 / v1.5.0 SafeProxyFactory (eth_call 0x53e5d935 via
  // ethereum-rpc.publicnode.com), so the CREATE2 addresses are independent of
  // the Dart fallback constant. Hex is lower-cased.
  //   jsFactoryData           getFactoryArgs().factoryData
  //   jsEncodeOneEth          encodeCalls([{to: mock, value: 1 ETH, 0x}])
  //   jsEncodeTransfer        encodeCalls([{to: mock, 0, transfer(mock, 10)}])
  //   jsEncode1000Wei         encodeCalls([{to: mock, value: 1000, 0x}])
  //   jsEncodeTwoCalls        encodeCalls([{mock, 1000}, {0x0987…4321, 2000}])
  //   jsStubTwoOwners         getStubSignature(), owners [key0, key1]
  //   jsStubWebAuthn          getStubSignature(), owners [webAuthn]
  //   jsSignUserOperation     signUserOperation(userOpV07(), chainId 1)
  //   js7579*                 same with erc7579LaunchpadAddress and
  //                           safe4337ModuleAddress = Safe7579 adapter
  //                           0x7579EE…0002 (as permissionless-test utils
  //                           pass it; Dart defaults to it); execute
  //                           encodings from a deployed account (eth_getCode
  //                           != 0x), setupSafe ones from an undeployed one;
  //                           js7579SetupSafeFull uses fullErc7579Account().
  const jsFactoryData =
      '0x1688f0b900000000000000000000000041675c099f32341bf84bfc5382af53'
      '4df5c7461a000000000000000000000000000000000000000000000000000000'
      '0000000060000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000284b63e800d0000000000000000000000000000000000000000000000'
      '0000000000000001000000000000000000000000000000000000000000000000'
      '00000000000000000100000000000000000000000038869bf66a61cf6bdb996a'
      '6ae40d5853fd43b5260000000000000000000000000000000000000000000000'
      '00000000000000014000000000000000000000000075cf11467937ce3f2f357c'
      'e24ffc3dbf8fd5c2260000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '000000000000000001000000000000000000000000f39fd6e51aad88f6f4ce6a'
      'b8827279cfffb922660000000000000000000000000000000000000000000000'
      '0000000000000001048d80ff0a00000000000000000000000000000000000000'
      '0000000000000000000000002000000000000000000000000000000000000000'
      '000000000000000000000000b9012dd68b007b46fbe91b9a7c3eda5a7a1063cb'
      '5b47000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '00648d0dc49f0000000000000000000000000000000000000000000000000000'
      '0000000000200000000000000000000000000000000000000000000000000000'
      '00000000000100000000000000000000000075cf11467937ce3f2f357ce24ffc'
      '3dbf8fd5c2260000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const jsEncodeOneEth =
      '0x541d63c8000000000000000000000000123456789012345678901234567890'
      '12345678900000000000000000000000000000000000000000000000000de0b6'
      'b3a7640000000000000000000000000000000000000000000000000000000000'
      '0000000080000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const jsEncodeTransfer =
      '0x541d63c8000000000000000000000000123456789012345678901234567890'
      '1234567890000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000080000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000044a9059cbb0000000000000000000000001234567890123456789012'
      '3456789012345678900000000000000000000000000000000000000000000000'
      '00000000000000000a0000000000000000000000000000000000000000000000'
      '0000000000';
  const jsEncode1000Wei =
      '0x541d63c8000000000000000000000000123456789012345678901234567890'
      '1234567890000000000000000000000000000000000000000000000000000000'
      '00000003e8000000000000000000000000000000000000000000000000000000'
      '0000000080000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const jsEncodeTwoCalls =
      '0x541d63c80000000000000000000000009641d764fc13c8b624c04430c7356c'
      '1c7c8102e2000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000080000000000000000000000000000000000000000000000000000000'
      '0000000001000000000000000000000000000000000000000000000000000000'
      '00000001048d80ff0a0000000000000000000000000000000000000000000000'
      '0000000000000000200000000000000000000000000000000000000000000000'
      '0000000000000000aa0012345678901234567890123456789012345678900000'
      '0000000000000000000000000000000000000000000000000000000003e80000'
      '0000000000000000000000000000000000000000000000000000000000000009'
      '8765432109876543210987654321098765432100000000000000000000000000'
      '000000000000000000000000000000000007d000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const jsStubTwoOwners =
      '0x000000000000000000000000fffffffffffffffffffffffffffffff0000000'
      '000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaa1cfffffffffffffffffffffffffffffff00000'
      '00000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';
  const jsStubWebAuthn =
      '0x00000000000000000000000000000000000000000000000094a4f6affbd897'
      '5951142c3999aeab7ecee555c200000000000000000000000000000000000000'
      '0000000000000000000000004100000000000000000000000000000000000000'
      '0000000000000000000000000160000000000000000000000000000000000000'
      '0000000000000000000000000080000000000000000000000000000000000000'
      '00000000000000000000000000e0635bc6d0f68ff895cae8a288ecf7542a6a9c'
      'd555df784b73e1e2ea7e9104b1db15e9015d280cb19527881c625fee43fd3a40'
      '5d5b0d199a8c8e6589a7381209e4000000000000000000000000000000000000'
      '000000000000000000000000002549960de5880e8c687434170f6476605b8fe4'
      'aeb9a28632c7995cf3ba831d97631d0000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000053226f726967696e223a22687474703a2f2f73'
      '6f6d656c617267646f6d61696e68657265736f74686174776568617665656e6f'
      '75676862797465732e636f6d222c2263726f73734f726967696e223a66616c73'
      '6500000000000000000000000000';
  const jsSignUserOperation =
      '0x0000000000000000000000008f30acd9a37b3c495a9c4d588efad1901a2a35'
      '32f41d058a691f64d7c1c7514a51606ff8af98c328ae6fa5d6d60612af219578'
      '3ac6f1fe09fc08f2ab990c59de1c';
  const js7579Encode1000Wei =
      '0xe9ae5c53000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000040000000000000000000000000000000000000000000000000000000'
      '0000000034123456789012345678901234567890123456789000000000000000'
      '000000000000000000000000000000000000000000000003e800000000000000'
      '0000000000';
  const js7579EncodeTwoCalls =
      '0xe9ae5c53010000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000040000000000000000000000000000000000000000000000000000000'
      '0000000180000000000000000000000000000000000000000000000000000000'
      '0000000020000000000000000000000000000000000000000000000000000000'
      '0000000002000000000000000000000000000000000000000000000000000000'
      '0000000040000000000000000000000000000000000000000000000000000000'
      '00000000c0000000000000000000000000123456789012345678901234567890'
      '1234567890000000000000000000000000000000000000000000000000000000'
      '00000003e8000000000000000000000000000000000000000000000000000000'
      '0000000060000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000098765432109876543210987654321'
      '0987654321000000000000000000000000000000000000000000000000000000'
      '00000007d0000000000000000000000000000000000000000000000000000000'
      '0000000060000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const js7579SetupSafe =
      '0xd9ed0e8f000000000000000000000000000000000000000000000000000000'
      '000000002000000000000000000000000041675c099f32341bf84bfc5382af53'
      '4df5c7461a000000000000000000000000000000000000000000000000000000'
      '0000000100000000000000000000000000000000000000000000000000000000'
      '00000000010000000000000000000000007579011ab74c46090561ea277ba79d'
      '510c6c00ff000000000000000000000000000000000000000000000000000000'
      '00000001400000000000000000000000007579ee8307284f293b192713648688'
      '0611f20002000000000000000000000000000000000000000000000000000000'
      '00000002c0000000000000000000000000000000000000000000000000000000'
      '00000002e0000000000000000000000000000000000000000000000000000000'
      '0000000001000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279'
      'cfffb92266000000000000000000000000000000000000000000000000000000'
      '000000014415cca6380000000000000000000000007579ee8307284f293b1927'
      '136486880611f200020000000000000000000000000000000000000000000000'
      '0000000000000000c00000000000000000000000000000000000000000000000'
      '0000000000000000e00000000000000000000000000000000000000000000000'
      '0000000000000001000000000000000000000000000000000000000000000000'
      '0000000000000001200000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '00000000a4e9ae5c530000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000400000000000000000000000000000000000000000000000'
      '0000000000000000341234567890123456789012345678901234567890000000'
      '00000000000000000000000000000000000000000000000000000003e8000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const js7579SetupSafeFull =
      '0xd9ed0e8f000000000000000000000000000000000000000000000000000000'
      '000000002000000000000000000000000041675c099f32341bf84bfc5382af53'
      '4df5c7461a000000000000000000000000000000000000000000000000000000'
      '0000000100000000000000000000000000000000000000000000000000000000'
      '00000000020000000000000000000000007579011ab74c46090561ea277ba79d'
      '510c6c00ff000000000000000000000000000000000000000000000000000000'
      '00000001600000000000000000000000007579ee8307284f293b192713648688'
      '0611f20002000000000000000000000000000000000000000000000000000000'
      '0000000380000000000000000000000000000000000000000000000000000000'
      '0000000440000000000000000000000000000000000000000000000000000000'
      '0000000002000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279'
      'cfffb9226600000000000000000000000094a4f6affbd8975951142c3999aeab'
      '7ecee555c2000000000000000000000000000000000000000000000000000000'
      '00000001e415cca6380000000000000000000000007579ee8307284f293b1927'
      '136486880611f200020000000000000000000000000000000000000000000000'
      '0000000000000000c00000000000000000000000000000000000000000000000'
      '0000000000000001600000000000000000000000000000000000000000000000'
      '0000000000000001800000000000000000000000000000000000000000000000'
      '0000000000000001a00000000000000000000000000000000000000000000000'
      '0000000000000000010000000000000000000000000000000000000000000000'
      '0000000000000000010000000000000000000000000000000000000000000000'
      '0000000000000000200000000000000000000000001234567890123456789012'
      '3456789012345678900000000000000000000000000000000000000000000000'
      '0000000000000000400000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '000000000000000001000000000000000000000000000000333034e9f539ce08'
      '819e12c1b8cb29084d0000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000001000000000000000000000000000000000000000000000000000000'
      '0000000020000000000000000000000000123456789012345678901234567890'
      '1234567890000000000000000000000000000000000000000000000000000000'
      '0000000040000000000000000000000000000000000000000000000000000000'
      '0000000002123400000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '00000000a4e9ae5c530000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000400000000000000000000000000000000000000000000000'
      '0000000000000000341234567890123456789012345678901234567890000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const js7579SignUserOperation =
      '0x00000000000000000000000010ccb4888a257d4b506a98968674827ea46b46'
      '80ed22e92a869d5d4689a9a6a209be2b1caa513baae00fe4e3f66f3040f19e2d'
      '65dc9a3bc606b70e0bbe79ad501b';

  // signUserOperation with owners [key0, key1]: key1's signature first
  // (Safe checkSignatures wants ascending signer addresses).
  const jsSignUserOperationTwoOwners =
      '0x000000000000000000000000156d8596bcc3776f279e5c48f8e512946f203a'
      '394ed947a981f424aa3b87938b0903e62488ed8659a2e90bd4d478d20374fbca'
      '2507efa3d19d5afaf66f4f2c631c8f30acd9a37b3c495a9c4d588efad1901a2a'
      '3532f41d058a691f64d7c1c7514a51606ff8af98c328ae6fa5d6d60612af2195'
      '783ac6f1fe09fc08f2ab990c59de1c';

  UserOperationV07 userOpV07() => UserOperationV07(
        sender: mockAddress,
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

  group('SafeSmartAccount', () {
    group('creation', () {
      test('defaults to Safe 1.4.1 on EntryPoint v0.7', () {
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(account.version, equals(SafeVersion.v1_4_1));
        expect(
          account.entryPoint.hex.toLowerCase(),
          equals('0x0000000071727de22e5e9d8baf0edac6f37da032'),
        );
      });

      test('threshold defaults to owners.length (permissionless.js)', () async {
        final owners = [
          PrivateKeyOwner(testPrivateKey),
          PrivateKeyOwner(owner2Key),
        ];

        // permissionless.js toSafeSmartAccount({owners: [key0, key1]})
        final jsTwoOfTwo = EthereumAddress.fromHex(
          '0xcb59e0913C0A52f9249E0890aD5DF1D8086a4078',
        );
        // ... with threshold: 1n
        final jsOneOfTwo = EthereumAddress.fromHex(
          '0xcAc83e841C3534f65E9d3471B46F6ca08AC4b664',
        );

        final byDefault =
            createSafeSmartAccount(owners: owners, chainId: BigInt.from(1));
        final explicitTwo = createSafeSmartAccount(
          owners: owners,
          threshold: BigInt.from(2),
          chainId: BigInt.from(1),
        );
        final explicitOne = createSafeSmartAccount(
          owners: owners,
          threshold: BigInt.one,
          chainId: BigInt.from(1),
        );

        expect(await byDefault.getAddress(), equals(jsTwoOfTwo));
        expect(await explicitTwo.getAddress(), equals(jsTwoOfTwo));
        expect(await explicitOne.getAddress(), equals(jsOneOfTwo));
      });

      test('throws when no owners provided', () {
        expect(
          () => createSafeSmartAccount(
            owners: [],
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });

      test('throws when threshold exceeds owner count', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        expect(
          () => createSafeSmartAccount(
            owners: [owner],
            threshold: BigInt.from(2),
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });

      test('throws when threshold is zero', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        expect(
          () => createSafeSmartAccount(
            owners: [owner],
            threshold: BigInt.zero,
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });

      test('Safe v1.5.0 address matches permissionless.js', () async {
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          version: SafeVersion.v1_5_0,
          entryPointVersion: EntryPointVersion.v07,
          chainId: BigInt.from(1),
        );

        expect(
          await account.getAddress(),
          equals(
            EthereumAddress.fromHex(
              '0x7bcdD067832F0B8cFcBbDda3C3643cCaC5998E19',
            ),
          ),
        );
      });

      // Every WebAuthn owner is listed as the one shared signer address, so
      // two of them make setup() revert (OwnerManager GS203/GS204), and
      // SafeWebAuthnSharedSigner keeps a single P-256 key per Safe.
      test('throws ArgumentError for more than one WebAuthn owner', () {
        expect(
          () => createSafeSmartAccount(
            owners: [
              _TestWebAuthnOwner(BigInt.one, BigInt.two, Uint8List(1)),
              _TestWebAuthnOwner(BigInt.from(3), BigInt.from(4), Uint8List(2)),
            ],
            chainId: BigInt.one,
            address: mockAddress,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('one WebAuthn owner'),
            ),
          ),
        );
      });

      test('throws for unsupported version combination', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        // Safe 1.5.0 doesn't support EntryPoint v0.6
        expect(
          () => createSafeSmartAccount(
            owners: [owner],
            version: SafeVersion.v1_5_0,
            entryPointVersion: EntryPointVersion.v06,
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });
    });

    // Counterfactual addresses computed offline (no `address:` override).
    group('getAddress', () {
      test('saltNonce changes the address like permissionless.js', () async {
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          saltNonce: BigInt.one,
          chainId: BigInt.from(1),
        );

        expect(
          await account.getAddress(),
          equals(
            EthereumAddress.fromHex(
              '0xe047f9CcF9a58Ce227FC85723e05cD046E37f9C0',
            ),
          ),
        );
      });

      test('owner is part of the address like permissionless.js', () async {
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(owner2Key)],
          chainId: BigInt.from(1),
        );

        expect(
          await account.getAddress(),
          equals(
            EthereumAddress.fromHex(
              '0xA389Fcc3069920C054a524DA0a11d500Dcf46BE3',
            ),
          ),
        );
      });
    });

    test('factory data and init code match permissionless.js', () async {
      final account = createSafeSmartAccount(
        owners: [PrivateKeyOwner(testPrivateKey)],
        chainId: BigInt.from(1),
        address: mockAddress,
      );
      const jsFactory = '0x4e1dcf7ad4e460cfd30791ccc4f9c8a4f820ec67';

      final factoryData = await account.getFactoryData();
      expect(factoryData!.factory.hex.toLowerCase(), equals(jsFactory));
      expect(factoryData.factoryData.toLowerCase(), equals(jsFactoryData));
      expect(
        (await account.getInitCode()).toLowerCase(),
        equals('$jsFactory${jsFactoryData.substring(2)}'),
      );
    });

    group('call encoding', () {
      late SafeSmartAccount account;

      setUp(() {
        account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          chainId: BigInt.from(1),
          address: mockAddress,
        );
      });

      test('encodeCall with value matches permissionless.js', () {
        final encoded = account.encodeCall(
          Call(
            to: mockAddress,
            value: BigInt.from(1000000000000000000), // 1 ETH
            data: '0x',
          ),
        );

        expect(encoded.toLowerCase(), equals(jsEncodeOneEth));
      });

      test('encodeCall with data matches permissionless.js', () {
        final encoded = account.encodeCall(
          Call(
            to: mockAddress,
            value: BigInt.zero,
            data:
                '0xa9059cbb0000000000000000000000001234567890123456789012345678901234567890000000000000000000000000000000000000000000000000000000000000000a',
          ),
        );

        expect(encoded.toLowerCase(), equals(jsEncodeTransfer));
      });

      test('encodeCalls with one call matches permissionless.js', () {
        final encoded = account.encodeCalls([
          Call(to: mockAddress, value: BigInt.from(1000)),
        ]);
        expect(encoded.toLowerCase(), equals(jsEncode1000Wei));
      });

      // Target is MultiSendCallOnly 0x9641…02e2, not MultiSend.
      test('multiple calls use MultiSendCallOnly like permissionless.js', () {
        final encoded = account.encodeCalls([
          Call(to: mockAddress, value: BigInt.from(1000)),
          Call(
            to: EthereumAddress.fromHex(
              '0x0987654321098765432109876543210987654321',
            ),
            value: BigInt.from(2000),
          ),
        ]);

        expect(encoded.toLowerCase(), equals(jsEncodeTwoCalls));
      });

      test('throws on empty calls', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(
          () => account.encodeCalls([]),
          throwsArgumentError,
        );
      });
    });

    group('getStubSignature', () {
      test('ECDSA stub matches permissionless.js dummy bytes', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final stub = account.getStubSignature().toLowerCase();
        // validAfter(0) + validUntil(0) + JS fixed ECDSA dummy
        const jsEcdsaDummy =
            'fffffffffffffffffffffffffffffff000000000000000000000000000000000'
            '7aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';
        expect(stub, equals('0x${'00' * 12}$jsEcdsaDummy'));
      });

      test('two-owner stub matches permissionless.js', () {
        final account = createSafeSmartAccount(
          owners: [
            PrivateKeyOwner(testPrivateKey),
            PrivateKeyOwner(owner2Key),
          ],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(
          account.getStubSignature().toLowerCase(),
          equals(jsStubTwoOwners),
        );
      });

      test('WebAuthn owner stub matches permissionless.js', () {
        final account = createSafeSmartAccount(
          owners: [_TestWebAuthnOwner(BigInt.one, BigInt.two, Uint8List(1))],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final stub = account.getStubSignature().toLowerCase();
        expect(stub, equals(jsStubWebAuthn));
        // The dynamic part is the shared dummy WebAuthn signature.
        expect(
          stub,
          endsWith(
            Hex.strip0x(getDummySafeWebAuthnSignature()).toLowerCase(),
          ),
        );
      });
    });

    group('signUserOperation', () {
      test('v0.7 SafeOp signature matches permissionless.js', () async {
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(
          (await account.signUserOperation(userOpV07())).toLowerCase(),
          equals(jsSignUserOperation),
        );
      });

      // The EntryPoint packs initCode as factory ++ factoryData, so a factory
      // with null factoryData is the same initCode as factory ++ 0x and the
      // Safe4337Module hashes exactly that. ECDSA signing is deterministic, so
      // equal signatures mean equal SafeOp hashes.
      test('two owners sign in ascending signer order like permissionless.js',
          () async {
        final account = createSafeSmartAccount(
          owners: [
            PrivateKeyOwner(testPrivateKey),
            PrivateKeyOwner(owner2Key),
          ],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(
          (await account.signUserOperation(userOpV07())).toLowerCase(),
          equals(jsSignUserOperationTwoOwners),
        );
      });

      test('signs initCode = factory when factoryData is null', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );
        final factory = EthereumAddress.fromHex(
          '0xa473ff7bb3cdc899a04dea0fbd30a72e95f0cf2f',
        );

        UserOperationV07 op({EthereumAddress? factory, String? factoryData}) =>
            UserOperationV07(
              sender: mockAddress,
              nonce: BigInt.zero,
              factory: factory,
              factoryData: factoryData,
              callData: '0x',
              callGasLimit: BigInt.from(100000),
              verificationGasLimit: BigInt.from(100000),
              preVerificationGas: BigInt.from(21000),
              maxFeePerGas: BigInt.from(1000000000),
              maxPriorityFeePerGas: BigInt.from(1000000000),
            );

        final factoryOnly =
            await account.signUserOperation(op(factory: factory));
        final factoryEmptyData = await account.signUserOperation(
          op(factory: factory, factoryData: '0x'),
        );
        final noFactory = await account.signUserOperation(op());

        expect(factoryOnly, equals(factoryEmptyData));
        expect(factoryOnly, isNot(equals(noFactory)));
      });

      test(
        'v0.6 EIP-712 SafeOp signature matches permissionless.js fixture',
        () async {
          final owner = PrivateKeyOwner(testPrivateKey);
          final account = createSafeSmartAccount(
            owners: [owner],
            chainId: BigInt.one,
            entryPointVersion: EntryPointVersion.v06,
            address: mockAddress,
          );

          final userOp = UserOperationV06(
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
            signature: '0x',
          );

          final signature = await account.signUserOperationV06(userOp);

          // viem signTypedData over EIP712_SAFE_OPERATION_TYPE_V06 with
          // Safe4337Module 0xa581c4A4…4037, validAfter=0, validUntil=0,
          // then packed as uint48‖uint48‖sig.
          expect(
            signature.toLowerCase(),
            equals(
              '0x000000000000000000000000c43b190628af4f8c76904c710f7a0f081556482309ff0352d0351986e0c8fecc298b32f1ccb48415db61fc1ef259f328e52e611cb13a51194a31c75036abbb971b',
            ),
          );
        },
      );

      test('v0.6 throws when signUserOperation (v0.7 API) is used', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        final userOp = UserOperationV07(
          sender: mockAddress,
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
        );

        expect(
          () => account.signUserOperation(userOp),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('v0.7 throws when signUserOperationV06 is used', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v07,
          address: mockAddress,
        );

        final userOp = UserOperationV06(
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
          () => account.signUserOperationV06(userOp),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    // Safe v1.4.1 + EntryPoint v0.6 has no WebAuthn shared signer; the
    // account must say so instead of failing a null check.
    group('WebAuthn owner without a shared signer address', () {
      SafeSmartAccount account() => createSafeSmartAccount(
            owners: [
              PrivateKeyOwner(testPrivateKey),
              _TestWebAuthnOwner(BigInt.one, BigInt.two, Uint8List(1)),
            ],
            chainId: BigInt.one,
            entryPointVersion: EntryPointVersion.v06,
            address: mockAddress,
          );

      test('getStubSignature throws StateError', () {
        expect(() => account().getStubSignature(), throwsStateError);
      });

      test('signUserOperationV06 throws StateError', () {
        final userOp = UserOperationV06(
          sender: mockAddress,
          nonce: BigInt.zero,
          initCode: '0x',
          callData: '0x',
          callGasLimit: BigInt.one,
          verificationGasLimit: BigInt.one,
          preVerificationGas: BigInt.one,
          maxFeePerGas: BigInt.one,
          maxPriorityFeePerGas: BigInt.one,
          paymasterAndData: '0x',
        );
        expect(
          () => account().signUserOperationV06(userOp),
          throwsStateError,
        );
      });
    });

    group('useMultiSendForSetup', () {
      // Expected CREATE2 addresses generated by calling
      // `toSafeSmartAccount` from permissionless.js@0.3.5 with the fixed
      // input (testPrivateKey, saltNonce=0n, version: '1.4.1',
      // entryPoint: { address: entryPoint07Address, version: '0.7' },
      // chainId=1) twice — once with useMultiSendForSetup: true (yields
      // multiSendAddress) and once with useMultiSendForSetup: false
      // (yields directSetupAddress). The JS transport is stubbed to
      // return chainId=1 and empty getCode; no network is required since
      // CREATE2 derivation is purely local.
      final multiSendAddress = EthereumAddress.fromHex(
        '0x124Ef647181eda69861b61596802129E3B018765',
      );
      final directSetupAddress = EthereumAddress.fromHex(
        '0x08eA90D108291a05830B25E8eFaF027979dEb8D1',
      );

      test('default is true (backwards compatible)', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final accountDefault = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
        );
        final accountExplicit = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          useMultiSendForSetup: true,
        );

        final defaultAddress = await accountDefault.getAddress();
        final explicitAddress = await accountExplicit.getAddress();

        expect(defaultAddress, equals(explicitAddress));
        expect(defaultAddress, equals(multiSendAddress));
      });

      test(
        'useMultiSendForSetup: false matches permissionless.js@0.3.5 vector',
        () async {
          final owner = PrivateKeyOwner(testPrivateKey);
          final account = createSafeSmartAccount(
            owners: [owner],
            chainId: BigInt.one,
            useMultiSendForSetup: false,
          );

          final address = await account.getAddress();

          expect(address, equals(directSetupAddress));
        },
      );

      test(
        'useMultiSendForSetup is ignored when a WebAuthn owner is present',
        () async {
          // When any owner is a WebAuthn owner, the Safe.setup fast path is
          // guarded off (see safe_account.dart `!_hasWebAuthnOwner`). Both
          // `useMultiSendForSetup: true` and `false` must therefore produce
          // the same CREATE2 address since both go through the MultiSend
          // initializer branch.
          final webAuthnOwner = _TestWebAuthnOwner(
            BigInt.from(0x1234),
            BigInt.from(0x5678),
            Uint8List.fromList(
              List<int>.generate(16, (i) => i),
            ),
          );

          final accountTrue = createSafeSmartAccount(
            owners: [webAuthnOwner],
            chainId: BigInt.one,
            useMultiSendForSetup: true,
          );
          final accountFalse = createSafeSmartAccount(
            owners: [webAuthnOwner],
            chainId: BigInt.one,
            useMultiSendForSetup: false,
          );

          final addressTrue = await accountTrue.getAddress();
          final addressFalse = await accountFalse.getAddress();

          expect(addressTrue, equals(addressFalse));
        },
      );

      test('useMultiSendForSetup is ignored in ERC-7579 mode', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        // permissionless.js toSafeSmartAccount({erc7579LaunchpadAddress,
        // safe4337ModuleAddress: Safe7579 adapter})
        final js7579Address = EthereumAddress.fromHex(
          '0x9b9f0Db7A1d3284cB021bfA593020a1F5dB07824',
        );

        final accountDefault = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );
        final accountFalse = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          useMultiSendForSetup: false,
        );

        expect(await accountDefault.getAddress(), equals(js7579Address));
        expect(await accountFalse.getAddress(), equals(js7579Address));
      });
    });

    group('7579 + v1.5.0 incompatibility', () {
      test('signMessage throws for Safe 7579 with version 1.5.0', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          version: SafeVersion.v1_5_0,
          entryPointVersion: EntryPointVersion.v07,
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        expect(
          () => account.signMessage('0x${'11' * 32}'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Safe 7579 & version 1.5.0 are not compatible'),
            ),
          ),
        );
      });

      test('signTypedData throws for Safe 7579 with version 1.5.0', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          version: SafeVersion.v1_5_0,
          entryPointVersion: EntryPointVersion.v07,
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final typedData = TypedData(
          domain: TypedDataDomain(name: 'Test', chainId: BigInt.one),
          types: {
            'Mail': [const TypedDataField(name: 'contents', type: 'string')],
          },
          primaryType: 'Mail',
          message: {'contents': 'hello'},
        );

        expect(
          () => account.signTypedData(typedData),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Safe 7579 & version 1.5.0 are not compatible'),
            ),
          ),
        );
      });
    });

    group('proxyCreationCode', () {
      /// ABI-encodes a `bytes` eth_call return value.
      String abiEncodeBytes(String hexData) {
        final payload =
            hexData.startsWith('0x') ? hexData.substring(2) : hexData;
        final length = payload.length ~/ 2;
        const offset =
            '0000000000000000000000000000000000000000000000000000000000000020';
        final lengthWord = length.toRadixString(16).padLeft(64, '0');
        final padded = payload.padRight(((length + 31) ~/ 32) * 64, '0');
        return '0x$offset$lengthWord$padded';
      }

      PublicClient publicClientReturning(String proxyCodeHex) {
        final mock = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final method = body['method'] as String;
          if (method == 'eth_call') {
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': abiEncodeBytes(proxyCodeHex),
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'error': {'code': -32000, 'message': 'unexpected $method'},
            }),
            200,
          );
        });
        return PublicClient(
          rpcClient: JsonRpcClient(
            url: Uri.parse('http://localhost:8545'),
            httpClient: mock,
          ),
        );
      }

      test('with publicClient uses factory proxyCreationCode for CREATE2',
          () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        // Baseline: hardcoded fallback
        final offline = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
        );
        final offlineAddress = await offline.getAddress();

        // Distinct proxy code from factory → different CREATE2 address
        const altProxyCode =
            '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
        final online = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          publicClient: publicClientReturning(altProxyCode),
        );
        final onlineAddress = await online.getAddress();

        expect(onlineAddress, isNot(equals(offlineAddress)));
      });

      test('RPC failure falls back to hardcoded constant', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final failing = MockClient((request) async {
          throw Exception('network down');
        });
        final offline = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
        );
        final withFailingClient = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          publicClient: PublicClient(
            rpcClient: JsonRpcClient(
              url: Uri.parse('http://localhost:8545'),
              httpClient: failing,
            ),
          ),
        );

        expect(
          await withFailingClient.getAddress(),
          equals(await offline.getAddress()),
        );
      });

      // SafeProxyFactory v1.5.0 (0x14F2…5e7b) returns this from
      // proxyCreationCode() on Ethereum, Sepolia and Base; it differs from
      // the v1.4.1 proxy, so the offline fallback must follow the version.
      const v150ProxyCreationCode =
          '0x608060405234801561001057600080fd5b506040516101b63803806101b68339'
          '818101604052602081101561003357600080fd5b810190808051906020019092'
          '9190505050600073ffffffffffffffffffffffffffffffffffffffff168173ff'
          'ffffffffffffffffffffffffffffffffffffff1614156100ca576040517f08c3'
          '79a0000000000000000000000000000000000000000000000000000000008152'
          '6004018080602001828103825260228152602001806101946022913960400191'
          '505060405180910390fd5b806000806101000a81548173ffffffffffffffffff'
          'ffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffff'
          'ffffffffff16021790555050607b806101196000396000f3fe60806040526000'
          '5463a619486e60003560e01c14156024578060601b606c5260206060f35b3660'
          '008037600080366000845af43d6000803e806040573d6000fd5b3d6000f3fea2'
          '646970667358221220e61834ebd2d8cd909d362bf67c47ef58fd665df38e6dd0'
          '36ce65611101d072e964736f6c63430007060033496e76616c69642073696e67'
          '6c65746f6e20616464726573732070726f7669646564';

      test('v1.5.0 offline address uses the v1.5.0 proxy creation code',
          () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final offline = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          version: SafeVersion.v1_5_0,
        );
        final fromFactory = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          version: SafeVersion.v1_5_0,
          publicClient: publicClientReturning(v150ProxyCreationCode),
        );

        expect(
          await offline.getAddress(),
          equals(await fromFactory.getAddress()),
        );
      });
    });
  });

  group('SafeVersionAddresses', () {
    // Fixtures from permissionless.js `toSafeSmartAccount.ts` SAFE_VERSION_TO_ADDRESSES_MAP.
    // Independent source of truth for parity — do not derive from Dart constants.
    void expectMatchesJsTable(
      SafeAddresses actual, {
      required String safeModuleSetupAddress,
      required String safe4337ModuleAddress,
      required String safeProxyFactoryAddress,
      required String safeSingletonAddress,
      required String multiSendAddress,
      required String multiSendCallOnlyAddress,
      String? webAuthnSharedSignerAddress,
      String? safeP256VerifierAddress,
    }) {
      expect(
        actual.safeModuleSetupAddress,
        equals(EthereumAddress.fromHex(safeModuleSetupAddress)),
      );
      expect(
        actual.safe4337ModuleAddress,
        equals(EthereumAddress.fromHex(safe4337ModuleAddress)),
      );
      expect(
        actual.safeProxyFactoryAddress,
        equals(EthereumAddress.fromHex(safeProxyFactoryAddress)),
      );
      expect(
        actual.safeSingletonAddress,
        equals(EthereumAddress.fromHex(safeSingletonAddress)),
      );
      expect(
        actual.multiSendAddress,
        equals(EthereumAddress.fromHex(multiSendAddress)),
      );
      expect(
        actual.multiSendCallOnlyAddress,
        equals(EthereumAddress.fromHex(multiSendCallOnlyAddress)),
      );
      if (webAuthnSharedSignerAddress == null) {
        expect(actual.webAuthnSharedSignerAddress, isNull);
      } else {
        expect(
          actual.webAuthnSharedSignerAddress,
          equals(EthereumAddress.fromHex(webAuthnSharedSignerAddress)),
        );
      }
      if (safeP256VerifierAddress == null) {
        expect(actual.safeP256VerifierAddress, isNull);
      } else {
        expect(
          actual.safeP256VerifierAddress,
          equals(EthereumAddress.fromHex(safeP256VerifierAddress)),
        );
      }
    }

    test('returns addresses for v1.4.1 + EP v0.6', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_4_1,
        EntryPointVersion.v06,
      );

      expect(addresses, isNotNull);
      expectMatchesJsTable(
        addresses!,
        safeModuleSetupAddress: '0x8EcD4ec46D4D2a6B64fE960B3D64e8B94B2234eb',
        safe4337ModuleAddress: '0xa581c4A4DB7175302464fF3C06380BC3270b4037',
        safeProxyFactoryAddress: '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
        safeSingletonAddress: '0x41675C099F32341bf84BFc5382aF534df5C7461a',
        multiSendAddress: '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526',
        multiSendCallOnlyAddress: '0x9641d764fc13c8B624c04430C7356C1C7C8102e2',
      );
    });

    test('returns addresses for v1.4.1 + EP v0.7', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_4_1,
        EntryPointVersion.v07,
      );

      expect(addresses, isNotNull);
      expectMatchesJsTable(
        addresses!,
        safeModuleSetupAddress: '0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47',
        safe4337ModuleAddress: '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226',
        safeProxyFactoryAddress: '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
        safeSingletonAddress: '0x41675C099F32341bf84BFc5382aF534df5C7461a',
        multiSendAddress: '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526',
        multiSendCallOnlyAddress: '0x9641d764fc13c8B624c04430C7356C1C7C8102e2',
        webAuthnSharedSignerAddress:
            '0x94a4F6affBd8975951142c3999aEAB7ecee555c2',
        safeP256VerifierAddress: '0xA86e0054C51E4894D88762a017ECc5E5235f5DBA',
      );
    });

    test('returns addresses for v1.5.0 + EP v0.7', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_5_0,
        EntryPointVersion.v07,
      );

      expect(addresses, isNotNull);
      // JS: MULTI_SEND_CALL_ONLY_ADDRESS 0xA83c…1836 (Etherscan: MultiSendCallOnly, verified)
      expectMatchesJsTable(
        addresses!,
        safeModuleSetupAddress: '0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47',
        safe4337ModuleAddress: '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226',
        safeProxyFactoryAddress: '0x14F2982D601c9458F93bd70B218933A6f8165e7b',
        safeSingletonAddress: '0xFf51A5898e281Db6DfC7855790607438dF2ca44b',
        multiSendAddress: '0x218543288004CD07832472D464648173c77D7eB7',
        multiSendCallOnlyAddress: '0xA83c336B20401Af773B6219BA5027174338D1836',
        webAuthnSharedSignerAddress:
            '0x94a4F6affBd8975951142c3999aEAB7ecee555c2',
        safeP256VerifierAddress: '0xA86e0054C51E4894D88762a017ECc5E5235f5DBA',
      );
    });

    test('returns null for v1.5.0 + EP v0.6', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_5_0,
        EntryPointVersion.v06,
      );

      expect(addresses, isNull);
    });
  });

  // ===========================================================================
  // ERC-7579 Mode Tests
  // ===========================================================================

  group('SafeSmartAccount ERC-7579 Mode', () {
    // Test private key (DO NOT use in production!)
    const testPrivateKey =
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
    final mockAddress =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    SafeSmartAccount erc7579Account({
      List<AccountOwner>? owners,
      List<EthereumAddress> attesters = const [],
      int attestersThreshold = 0,
      List<Safe7579ModuleInit> validators = const [],
      List<Safe7579ModuleInit> executors = const [],
      EthereumAddress? address,
    }) =>
        createSafeSmartAccount(
          owners: owners ?? [PrivateKeyOwner(testPrivateKey)],
          chainId: BigInt.from(1),
          address: address,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: attesters,
          attestersThreshold: attestersThreshold,
          validators: validators,
          executors: executors,
        );

    // Owners [key0, WebAuthn], validator (mock, 0x1234), executor (mock, 0x),
    // Rhinestone attester, attestersThreshold 1.
    SafeSmartAccount fullErc7579Account({EthereumAddress? address}) =>
        erc7579Account(
          owners: [
            PrivateKeyOwner(testPrivateKey),
            _TestWebAuthnOwner(BigInt.one, BigInt.two, Uint8List(1)),
          ],
          validators: [
            Safe7579ModuleInit(module: mockAddress, initData: '0x1234'),
          ],
          executors: [Safe7579ModuleInit(module: mockAddress)],
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
          address: address,
        );

    // Counterfactual addresses from permissionless.js (with
    // safe4337ModuleAddress = Safe7579 adapter, see the fixtures note):
    // CREATE2 commits to the launchpad initializer, so each pins
    // preValidationSetup(initHash, …).
    group('getAddress', () {
      test('default 7579 Safe matches permissionless.js', () async {
        expect(
          await erc7579Account().getAddress(),
          equals(
            EthereumAddress.fromHex(
              '0x9b9f0Db7A1d3284cB021bfA593020a1F5dB07824',
            ),
          ),
        );
      });

      test('attesters are part of the address like permissionless.js',
          () async {
        final account = erc7579Account(
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        expect(
          await account.getAddress(),
          equals(
            EthereumAddress.fromHex(
              '0x7513FBCB20c0659519cFedb807dA645822881495',
            ),
          ),
        );
      });

      test('attesters are sorted like permissionless.js', () async {
        final attesterA = EthereumAddress.fromHex(
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01',
        );
        final attesterB = EthereumAddress.fromHex(
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02',
        );
        // permissionless.js gives this address for [A, B] and for [B, A].
        final jsAddress = EthereumAddress.fromHex(
          '0x047B1AB52Da71F1111a1a1aa2BA64D78411d3F1D',
        );

        for (final attesters in [
          [attesterA, attesterB],
          [attesterB, attesterA],
        ]) {
          final account = erc7579Account(
            attesters: attesters,
            attestersThreshold: 1,
          );
          expect(await account.getAddress(), equals(jsAddress));
        }
      });

      test('validators are part of the address like permissionless.js',
          () async {
        final account = erc7579Account(
          validators: [
            Safe7579ModuleInit(
              module: EthereumAddress.fromHex(
                '0xaaaa111111111111111111111111111111111111',
              ),
            ),
          ],
        );

        expect(
          await account.getAddress(),
          equals(
            EthereumAddress.fromHex(
              '0x234Db6F0483476eeab3d895e4826B9296d6C60b9',
            ),
          ),
        );
      });

      // initHash = keccak256(abi.encode(InitData)), so this pins the
      // WebAuthn shared signer, validators, executors and attesters inside
      // preValidationSetup.
      test('full InitData with a WebAuthn owner matches permissionless.js',
          () async {
        expect(
          await fullErc7579Account().getAddress(),
          equals(
            EthereumAddress.fromHex(
              '0x0a5804eBe78DeD87A4e3e152Daaf2451AEAFEe42',
            ),
          ),
        );
      });
    });

    group('encodeCalls', () {
      test('single call uses ERC-7579 execute like permissionless.js', () {
        final encoded = erc7579Account(address: mockAddress).encodeCall(
          Call(to: mockAddress, value: BigInt.from(1000), data: '0x'),
        );

        expect(encoded.toLowerCase(), equals(js7579Encode1000Wei));
      });

      test('batch uses ERC-7579 batch execute like permissionless.js', () {
        final encoded = erc7579Account(address: mockAddress).encodeCalls([
          Call(to: mockAddress, value: BigInt.from(1000)),
          Call(
            to: EthereumAddress.fromHex(
              '0x0987654321098765432109876543210987654321',
            ),
            value: BigInt.from(2000),
          ),
        ]);

        expect(encoded.toLowerCase(), equals(js7579EncodeTwoCalls));
      });
    });

    test('signUserOperation matches permissionless.js', () async {
      final account = erc7579Account(address: mockAddress);

      expect(
        (await account.signUserOperation(userOpV07())).toLowerCase(),
        equals(js7579SignUserOperation),
      );
    });

    // permissionless.js encodeCalls on an undeployed 7579 Safe.
    group('encodeCallsForDeployment', () {
      test('wraps the calls in setupSafe(InitData) like permissionless.js', () {
        final encoded =
            erc7579Account(address: mockAddress).encodeCallsForDeployment([
          Call(to: mockAddress, value: BigInt.from(1000), data: '0x'),
        ]);

        expect(encoded.toLowerCase(), equals(js7579SetupSafe));
      });

      test('full InitData with a WebAuthn owner matches permissionless.js', () {
        final encoded =
            fullErc7579Account(address: mockAddress).encodeCallsForDeployment([
          Call(to: mockAddress, value: BigInt.zero, data: '0x'),
        ]);

        expect(encoded.toLowerCase(), equals(js7579SetupSafeFull));
      });

      test('standard mode falls back to regular encoding', () {
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(
          account.encodeCallsForDeployment([
            Call(to: mockAddress, value: BigInt.from(1000), data: '0x'),
          ]).toLowerCase(),
          equals(jsEncode1000Wei),
        );
      });

      const setupSafeSignature = 'setupSafe((address,address[],uint256,'
          'address,bytes,address,(address,bytes)[],bytes))';

      // permissionless.js get7579LaunchPadInitData maps WebAuthn owners to
      // safeWebAuthnSharedSignerAddress, as standard mode does.
      test('lists a WebAuthn owner as the shared signer', () {
        final webAuthnOwner =
            _TestWebAuthnOwner(BigInt.one, BigInt.two, Uint8List(1));
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey), webAuthnOwner],
          chainId: BigInt.one,
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final encoded = account.encodeCallsForDeployment([
          Call(to: mockAddress, value: BigInt.zero, data: '0x'),
        ]);
        final initData =
            AbiEncoder.decodeFunctionData(setupSafeSignature, encoded)[0]
                as List;
        final owners = (initData[1] as List).cast<EthereumAddress>();

        expect(
          owners,
          contains(
            SafeVersionAddresses.getAddresses(
              SafeVersion.v1_4_1,
              EntryPointVersion.v07,
            )!
                .webAuthnSharedSignerAddress,
          ),
        );
        expect(owners, isNot(contains(webAuthnOwner.address)));
      });
    });
  });

  group('Safe7579Addresses', () {
    test('has correct Safe7579 module address', () {
      expect(
        Safe7579Addresses.safe7579ModuleAddress.hex.toLowerCase(),
        equals('0x7579ee8307284f293b1927136486880611f20002'),
      );
    });

    test('has correct launchpad address', () {
      expect(
        Safe7579Addresses.erc7579LaunchpadAddress.hex.toLowerCase(),
        equals('0x7579011ab74c46090561ea277ba79d510c6c00ff'),
      );
    });

    test('has correct Rhinestone attester address', () {
      expect(
        Safe7579Addresses.rhinestoneAttester.hex.toLowerCase(),
        equals('0x000000333034e9f539ce08819e12c1b8cb29084d'),
      );
    });
  });
}
