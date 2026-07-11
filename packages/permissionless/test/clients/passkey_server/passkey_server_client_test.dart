import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Recorded-style fixtures matching permissionless.js passkey server RPC shapes.
void main() {
  group('PasskeyServerClient', () {
    late List<Map<String, dynamic>> capturedRequests;

    MockClient createMockClient(
      dynamic Function(Map<String, dynamic> request) responseFactory,
    ) {
      capturedRequests = [];
      return MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedRequests.add(body);
        final response = responseFactory(body);
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': response,
          }),
          200,
        );
      });
    }

    /// Sample bytes used across encode/decode fixtures.
    /// ASCII "challenge-bytes!!" → base64 "Y2hhbGxlbmdlLWJ5dGVzISE="
    Uint8List challengeBytes() =>
        Uint8List.fromList(utf8.encode('challenge-bytes!!'));

    /// base64 of challengeBytes (standard, padded)
    String challengeB64() => base64Encode(challengeBytes());

    /// user id bytes
    Uint8List userIdBytes() => Uint8List.fromList(utf8.encode('user-id-01'));

    String userIdB64() => base64Encode(userIdBytes());

    Map<String, dynamic> validStartRegistrationResult() => {
          'rp': {'id': 'example.com', 'name': 'Example'},
          'user': {
            'id': userIdB64(),
            'name': 'alice@example.com',
            'displayName': 'Alice',
          },
          'challenge': challengeB64(),
          'timeout': 60000,
          'authenticatorSelection': {
            'authenticatorAttachment': 'platform',
            'requireResidentKey': true,
            'residentKey': 'required',
            'userVerification': 'required',
          },
          'attestation': 'none',
          'extensions': {
            'credProps': true,
          },
        };

    group('startRegistration', () {
      test('calls pks_startRegistration with context and decodes fields',
          () async {
        final mock = createMockClient((_) => validStartRegistrationResult());
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        final options = await client.startRegistration(
          context: {'userName': 'alice@example.com'},
        );

        expect(capturedRequests.single['method'], 'pks_startRegistration');
        expect(
          capturedRequests.single['params'],
          equals([
            {'userName': 'alice@example.com'},
          ]),
        );

        expect(options.rp.id, 'example.com');
        expect(options.rp.name, 'Example');
        expect(options.user.name, 'alice@example.com');
        expect(options.user.displayName, 'Alice');
        expect(options.user.id, equals(userIdBytes()));
        expect(options.challenge, equals(challengeBytes()));
        expect(options.attestation, 'none');
        expect(options.timeout, 60000);
        expect(
          options.authenticatorSelection?.authenticatorAttachment,
          'platform',
        );
        expect(options.authenticatorSelection?.requireResidentKey, isTrue);
        expect(options.extensions?['credProps'], isTrue);
      });

      test('sends null context when omitted', () async {
        final mock = createMockClient((_) => validStartRegistrationResult());
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        await client.startRegistration();

        expect(capturedRequests.single['params'], equals([null]));
      });

      test('rejects invalid registration response shape', () async {
        final mock = createMockClient(
          (_) => {
            'rp': {'id': 'example.com', 'name': 'Example'},
            'user': {
              'id': userIdB64(),
              'name': 'alice',
              'displayName': 'Alice',
            },
            'challenge': challengeB64(),
            // missing authenticatorSelection / bad attestation
            'attestation': 'invalid',
          },
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        expect(
          () => client.startRegistration(),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('startAuthentication', () {
      test('calls pks_startAuthentication and returns hex challenge', () async {
        final mock = createMockClient(
          (_) => {
            'challenge': challengeB64(),
            'rpId': 'example.com',
            'timeout': 30000,
            'userVerification': 'preferred',
            'uuid': 'session-uuid-1',
          },
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        final options = await client.startAuthentication();

        expect(capturedRequests.single['method'], 'pks_startAuthentication');
        expect(capturedRequests.single['params'], equals(<dynamic>[]));
        expect(options.rpId, 'example.com');
        expect(options.uuid, 'session-uuid-1');
        expect(options.userVerification, 'preferred');
        expect(options.timeout, 30000);
        // permissionless.js: toHex(Base64.toBytes(challenge))
        expect(options.challenge, Hex.fromBytes(challengeBytes()));
        expect(options.challenge.startsWith('0x'), isTrue);
      });
    });

    group('getCredentials', () {
      test('calls pks_getCredentials and parses list', () async {
        final mock = createMockClient(
          (_) => [
            {
              'id': 'cred-1',
              'publicKey':
                  '0x04aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
            {
              'id': 'cred-2',
              'publicKey':
                  '0x04bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            },
          ],
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        final credentials = await client.getCredentials(
          context: {'userName': 'alice@example.com'},
        );

        expect(capturedRequests.single['method'], 'pks_getCredentials');
        expect(
          capturedRequests.single['params'],
          equals([
            {'userName': 'alice@example.com'},
          ]),
        );
        expect(credentials, hasLength(2));
        expect(credentials[0].id, 'cred-1');
        expect(credentials[0].publicKey.startsWith('0x'), isTrue);
        expect(credentials[1].id, 'cred-2');
      });

      test('rejects non-array response', () async {
        final mock = createMockClient((_) => {'not': 'array'});
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        expect(
          () => client.getCredentials(),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects invalid public key format', () async {
        final mock = createMockClient(
          (_) => [
            {'id': 'cred-1', 'publicKey': 'not-hex'},
          ],
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        expect(
          () => client.getCredentials(),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('verifyRegistration', () {
      test('encodes credential payload matching JS base64 rules', () async {
        final rawId = Uint8List.fromList([1, 2, 3, 4, 5]);
        final clientDataJSON =
            Uint8List.fromList(utf8.encode('{"type":"webauthn.create"}'));
        final attestationObject = Uint8List.fromList([10, 20, 30, 40, 50]);
        final authenticatorData = Uint8List.fromList([9, 8, 7]);

        final mock = createMockClient(
          (_) => {
            'success': true,
            'id': 'cred-id-1',
            'publicKey': '0x04abcd',
            'userName': 'alice@example.com',
          },
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        final result = await client.verifyRegistration(
          credential: PasskeyRegistrationCredential(
            id: 'cred-id-1',
            rawId: rawId,
            authenticatorAttachment: 'platform',
            response: PasskeyAttestationResponse(
              clientDataJSON: clientDataJSON,
              attestationObject: attestationObject,
              authenticatorData: authenticatorData,
              transports: const ['internal'],
              publicKeyAlgorithm: -7,
            ),
            clientExtensionResults: const {
              'credProps': {'rk': true},
            },
          ),
          context: {'userName': 'alice@example.com'},
        );

        expect(capturedRequests.single['method'], 'pks_verifyRegistration');
        final params = capturedRequests.single['params'] as List<dynamic>;
        expect(params, hasLength(2));

        final body = params[0] as Map<String, dynamic>;
        expect(body['id'], 'cred-id-1');
        // rawId: base64url, no pad
        expect(body['rawId'], base64Url.encode(rawId).replaceAll('=', ''));
        expect(body['authenticatorAttachment'], 'platform');
        expect(body['type'], 'public-key');
        expect(body['clientExtensionResults'], {
          'credProps': {'rk': true},
        });

        final response = body['response'] as Map<String, dynamic>;
        // clientDataJSON: standard base64 (pad true, url false)
        expect(response['clientDataJSON'], base64Encode(clientDataJSON));
        // attestationObject: base64url with pad
        expect(
            response['attestationObject'], base64Url.encode(attestationObject));
        // authenticatorData: standard base64
        expect(response['authenticatorData'], base64Encode(authenticatorData));
        expect(response['transports'], ['internal']);
        expect(response['publicKeyAlgorithm'], -7);

        expect(params[1], {'userName': 'alice@example.com'});

        expect(result.success, isTrue);
        expect(result.id, 'cred-id-1');
        expect(result.publicKey, '0x04abcd');
        expect(result.userName, 'alice@example.com');
      });

      test('rejects verification result without 0x public key', () async {
        final mock = createMockClient(
          (_) => {
            'success': true,
            'id': 'cred-id-1',
            'publicKey': 'deadbeef',
            'userName': 'alice',
          },
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        expect(
          () => client.verifyRegistration(
            credential: PasskeyRegistrationCredential(
              id: 'x',
              rawId: Uint8List.fromList([1]),
              authenticatorAttachment: 'platform',
              response: PasskeyAttestationResponse(
                clientDataJSON: Uint8List.fromList([1]),
                attestationObject: Uint8List.fromList([2]),
              ),
            ),
          ),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('verifyAuthentication', () {
      test('encodes assertion payload matching JS base64url rules', () async {
        final rawId = Uint8List.fromList([1, 2, 3, 4]);
        final clientDataJSON =
            Uint8List.fromList(utf8.encode('{"type":"webauthn.get"}'));
        final authenticatorData = Uint8List.fromList([5, 6, 7, 8]);
        final signature = Uint8List.fromList([9, 10, 11]);
        final userHandle = Uint8List.fromList([12, 13]);

        final mock = createMockClient(
          (_) => {
            'success': true,
            'id': 'cred-id-1',
            'publicKey': '0x04ff',
            'userName': 'alice@example.com',
          },
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        final result = await client.verifyAuthentication(
          credential: PasskeyAuthenticationCredential(
            id: 'cred-id-1',
            rawId: rawId,
            authenticatorAttachment: 'platform',
            response: PasskeyAssertionResponse(
              clientDataJSON: clientDataJSON,
              authenticatorData: authenticatorData,
              signature: signature,
              userHandle: userHandle,
            ),
          ),
          uuid: 'session-uuid-1',
        );

        expect(capturedRequests.single['method'], 'pks_verifyAuthentication');
        final params = capturedRequests.single['params'] as List<dynamic>;
        expect(params, hasLength(2));

        final body = params[0] as Map<String, dynamic>;
        expect(body['rawId'], base64Url.encode(rawId).replaceAll('=', ''));
        expect(body['type'], 'public-key');

        final response = body['response'] as Map<String, dynamic>;
        // clientDataJSON / signature / userHandle: base64url no pad
        expect(
          response['clientDataJSON'],
          base64Url.encode(clientDataJSON).replaceAll('=', ''),
        );
        // authenticatorData: base64url with pad (url: true only)
        expect(
          response['authenticatorData'],
          base64Url.encode(authenticatorData),
        );
        expect(
          response['signature'],
          base64Url.encode(signature).replaceAll('=', ''),
        );
        expect(
          response['userHandle'],
          base64Url.encode(userHandle).replaceAll('=', ''),
        );

        expect(params[1], {'uuid': 'session-uuid-1'});
        expect(result.success, isTrue);
        expect(result.publicKey, '0x04ff');
      });
    });
  });
}
