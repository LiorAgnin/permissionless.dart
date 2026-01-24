import 'package:flutter_test/flutter_test.dart';
import 'package:permissionless_passkeys/src/accounts/to_webauthn_account.dart';
import 'package:permissionless_passkeys/src/accounts/webauthn_account.dart';
import 'package:permissionless_passkeys/src/types/webauthn_credential.dart';
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
            result.webauthn.authenticatorData, equals(testAuthenticatorData));
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

    group('signMessage', () {
      test('throws UnimplementedError (requires keccak256)', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        expect(
          () async => await account.signMessage(message: 'Hello World'),
          throwsA(isA<UnimplementedError>()),
        );
      });
    });

    group('signTypedDataViem', () {
      test('throws UnimplementedError', () async {
        final mockSignature = _createMockSignature();

        final account = createWebAuthnAccount(
          credential: credential,
          getFn: (_) async => mockSignature,
        );

        expect(
          () async => await account.signTypedDataViem(
            domain: {},
            types: {},
            primaryType: 'Test',
            message: {},
          ),
          throwsA(isA<UnimplementedError>()),
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

Signature _createMockSignature() {
  return Signature(
    testSignatureR,
    testSignatureS,
    authData: testAuthenticatorData,
    clientDataJson: testClientDataJSON,
  );
}
