import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:permissionless/permissionless.dart' show Hex, hashMessage;
import 'package:permissionless_passkeys/permissionless_passkeys.dart';
import 'package:web3_signers/web3_signers.dart';

import '../helpers/test_fixtures.dart';

void main() {
  group('WebAuthnAccount', () {
    late WebAuthnCredential credential;

    setUp(() {
      credential = _createMockCredential();
    });

    group('toWebAuthnAccount', () {
      test('creates account with correct id', () {
        final account = toWebAuthnAccount(
          ToWebAuthnAccountParameters(credential: credential),
        );

        expect(account.id, equals(testCredentialId));
      });

      test('creates account with correct publicKey', () {
        final account = toWebAuthnAccount(
          ToWebAuthnAccountParameters(credential: credential),
        );

        expect(account.publicKey.startsWith('0x'), isTrue);
        // 0x + 64 hex (x) + 64 hex (y) = 130 chars
        expect(account.publicKey.length, equals(130));
      });

      test('publicKey contains x coordinate', () {
        final account = toWebAuthnAccount(
          ToWebAuthnAccountParameters(credential: credential),
        );

        final hex = account.publicKey.substring(2);
        final xHex = hex.substring(0, 64);
        expect(xHex, equals(bigIntToHex32(testPublicKeyX)));
      });

      test('publicKey contains y coordinate', () {
        final account = toWebAuthnAccount(
          ToWebAuthnAccountParameters(credential: credential),
        );

        final hex = account.publicKey.substring(2);
        final yHex = hex.substring(64, 128);
        expect(yHex, equals(bigIntToHex32(testPublicKeyY)));
      });

      test('type is webAuthn', () {
        final account = toWebAuthnAccount(
          ToWebAuthnAccountParameters(credential: credential),
        );

        expect(account.type, equals('webAuthn'));
      });
    });

    group('createWebAuthnAccount', () {
      test('creates account with named parameters', () {
        final account = createWebAuthnAccount(
          credential: credential,
          rpId: 'test.example.com',
        );

        expect(account.id, equals(testCredentialId));
        expect(account.type, equals('webAuthn'));
      });

      test('works without rpId', () {
        final account = createWebAuthnAccount(credential: credential);

        expect(account.id, equals(testCredentialId));
        expect(account.publicKey.startsWith('0x'), isTrue);
      });
    });

    group('sign', () {
      test('returns WebAuthnSignReturnType with signature', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        final result = await account.sign(
          hash:
              '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(result.signature.startsWith('0x'), isTrue);
      });

      test('signature is 64 bytes (128 hex chars)', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        final result = await account.sign(
          hash:
              '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        // 0x + 128 hex chars = 130
        expect(result.signature.length, equals(130));
      });

      test('signature contains r value', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        final result = await account.sign(
          hash:
              '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        final sigHex = result.signature.substring(2);
        final rHex = sigHex.substring(0, 64);
        expect(rHex, equals(bigIntToHex32(testSignatureR)));
      });

      test('signature contains s value', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        final result = await account.sign(
          hash:
              '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        final sigHex = result.signature.substring(2);
        final sHex = sigHex.substring(64, 128);
        expect(sHex, equals(bigIntToHex32(testSignatureS)));
      });

      test('returns webauthn metadata', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        final result = await account.sign(
          hash:
              '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(
          result.webauthn.authenticatorData,
          equals(testAuthenticatorData),
        );
        expect(result.webauthn.clientDataJSON, equals(testClientDataJSON));
        expect(result.webauthn.typeIndex, equals(testResponseTypeLocation));
      });

      test('returns raw signature', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        final result = await account.sign(
          hash:
              '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(result.raw, equals(mockSignature));
      });

      test('throws StateError without rpId and getFn', () async {
        final account = createWebAuthnAccount(credential: credential);

        expect(
          () async => await account.sign(
            hash:
                '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('handles hash without 0x prefix', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        final result = await account.sign(
          hash:
              '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(result.signature.startsWith('0x'), isTrue);
      });
    });

    group('authenticator response without WebAuthn metadata', () {
      const hash =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      final bareSignature = Signature(testSignatureR, testSignatureS);

      test('sign throws StateError', () async {
        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => bareSignature,
        );

        await expectLater(account.sign(hash: hash), throwsA(isA<StateError>()));
      });

      test('signP256 throws StateError', () async {
        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => bareSignature,
        );

        await expectLater(account.signP256(hash), throwsA(isA<StateError>()));
      });
    });

    group('authenticator response with incomplete clientDataJSON', () {
      Future<WebAuthnSignReturnType> signWith(String clientDataJSON) =>
          createWebAuthnAccount(
            credential: credential,
            getFn: (_) async => Signature(
              testSignatureR,
              testSignatureS,
              authData: testAuthenticatorData,
              clientDataJson: clientDataJSON,
            ),
          ).sign(hash: testHash);

      // ox WebAuthnP256.sign (viem): challengeIndex =
      // clientDataJSON.indexOf('"challenge"'), typeIndex =
      // clientDataJSON.indexOf('"type"') — the offsets of the keys, which
      // on-chain WebAuthn verifiers expect.
      test('reports the "challenge" and "type" key offsets like ox', () async {
        final result = await signWith(testClientDataJSON);
        expect(result.webauthn.challengeIndex, 23);
        expect(result.webauthn.typeIndex, 1);
      });

      test('without the challenge throws StateError', () async {
        await expectLater(
          signWith('{"type":"webauthn.get","challenge":"AAAA"}'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('challenge'),
            ),
          ),
        );
      });

      test('without the "type" key throws StateError', () async {
        await expectLater(
          signWith(
            testClientDataJSON.replaceFirst('"type":"webauthn.get",', ''),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('"type"'),
            ),
          ),
        );
      });
    });

    group('signP256', () {
      test('returns the authenticator signature and metadata', () async {
        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => _createMockSignature(),
        );

        final data = await account.signP256(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(data.r, testSignatureR);
        expect(data.s, testSignatureS);
        expect(data.authenticatorData, testAuthenticatorData);
        expect(data.clientDataJSON, testClientDataJSON);
        expect(data.typeIndex, testResponseTypeLocation);
      });
    });

    group('signMessage', () {
      // viem: hashMessage('hello world')
      const helloWorldHash =
          '0xd9eba16ed0ecae432b71fe008c98cc872bb4cc214d3220a36f365326cf807d68';

      Future<String> challengeFor(dynamic message) async {
        Uint8List? challenge;
        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (c) async {
            challenge = c;
            return _createMockSignature(c);
          },
        );
        await account.signMessage(message: message);
        return Hex.fromBytes(challenge!);
      }

      test('signs the EIP-191 hash of a UTF-8 string', () async {
        expect(await challengeFor('hello world'), helloWorldHash);
      });

      test('signs the EIP-191 hash of raw bytes', () async {
        expect(
          await challengeFor(Uint8List.fromList(utf8.encode('hello world'))),
          helloWorldHash,
        );
      });

      test('treats a 0x-prefixed string as UTF-8 text, like viem', () async {
        const message = '0x68656c6c6f20776f726c64';

        expect(await challengeFor(message), hashMessage(message));
        expect(await challengeFor(message), isNot(helloWorldHash));
      });
    });

    group('signTypedDataViem', () {
      test('signs the EIP-712 hash', () async {
        Uint8List? challenge;
        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (c) async {
            challenge = c;
            return _createMockSignature(c);
          },
        );

        await account.signTypedDataViem(
          domain: {
            'name': 'Ether Mail',
            'version': '1',
            'chainId': 1,
            'verifyingContract': '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
          },
          types: {
            'Person': [
              {'name': 'name', 'type': 'string'},
              {'name': 'wallet', 'type': 'address'},
            ],
            'Mail': [
              {'name': 'from', 'type': 'Person'},
              {'name': 'to', 'type': 'Person'},
              {'name': 'contents', 'type': 'string'},
            ],
          },
          primaryType: 'Mail',
          message: {
            'from': {
              'name': 'Cow',
              'wallet': '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
            },
            'to': {
              'name': 'Bob',
              'wallet': '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
            },
            'contents': 'Hello, Bob!',
          },
        );

        // EIP-712 specification example digest.
        expect(
          Hex.fromBytes(challenge!),
          '0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2',
        );
      });
    });

    group('WebAuthnSignReturnType', () {
      test('can be constructed', () {
        final mockSignature = _createMockSignature();

        final result = WebAuthnSignReturnType(
          signature: '0xaabb',
          webauthn: WebAuthnSignMetadata(
            authenticatorData: testAuthenticatorData,
            clientDataJSON: testClientDataJSON,
            challengeIndex: 23,
            typeIndex: 9,
          ),
          raw: mockSignature,
        );

        expect(result.signature, equals('0xaabb'));
        expect(result.webauthn.challengeIndex, equals(23));
      });
    });

    group('WebAuthnSignMetadata', () {
      test('can be constructed', () {
        final metadata = WebAuthnSignMetadata(
          authenticatorData: testAuthenticatorData,
          clientDataJSON: testClientDataJSON,
          challengeIndex: 23,
          typeIndex: 9,
        );

        expect(metadata.authenticatorData, equals(testAuthenticatorData));
        expect(metadata.clientDataJSON, equals(testClientDataJSON));
        expect(metadata.challengeIndex, equals(23));
        expect(metadata.typeIndex, equals(9));
      });
    });
  });
}

WebAuthnCredential _createMockCredential() {
  final key = PassKeyPublicKey(
    x: Uint256(testPublicKeyX),
    y: Uint256(testPublicKeyY),
    credentialId: testCredentialIdBytes,
    userName: 'test@example.com',
    aaGuid: '00000000-0000-0000-0000-000000000000',
  );
  return WebAuthnCredential(
    id: testCredentialId,
    rawId: testCredentialIdBytes,
    x: testPublicKeyX,
    y: testPublicKeyY,
    raw: key,
  );
}

/// An authenticator response over [challenge], or over [testHash] if omitted.
Signature _createMockSignature([List<int>? challenge]) {
  return Signature(
    testSignatureR,
    testSignatureS,
    authData: testAuthenticatorData,
    clientDataJson: challenge == null
        ? testClientDataJSON
        : clientDataJsonFor(challenge),
  );
}
