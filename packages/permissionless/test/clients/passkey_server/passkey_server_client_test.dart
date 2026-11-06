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

      test('rejects an unknown attestation value', () async {
        final mock = createMockClient(
          (_) => {...validStartRegistrationResult(), 'attestation': 'invalid'},
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        await expectLater(
          client.startRegistration(),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects a response without authenticatorSelection', () async {
        final mock = createMockClient(
          (_) =>
              validStartRegistrationResult()..remove('authenticatorSelection'),
        );
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        await expectLater(
          client.startRegistration(),
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
        expect(
          credentials[0].publicKey,
          '0x04aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        expect(credentials[1].id, 'cred-2');
      });

      test('rejects non-array response', () async {
        final mock = createMockClient((_) => {'not': 'array'});
        final client = createPasskeyServerClient(
          url: 'http://localhost:3000',
          httpClient: mock,
        );

        expect(
          client.getCredentials,
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
          client.getCredentials,
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('verifyRegistration', () {
      test('encodes credential payload matching JS base64 rules', () async {
        // Bytes chosen so standard and url alphabets differ (+/ vs -_) and
        // every field needs padding, so each field's alphabet and padding
        // choice is observable. Expected strings: ox Base64.fromBytes with
        // the options permissionless.js verifyRegistration passes.
        final rawId = Uint8List.fromList([0xfb, 0xff, 0xfe, 0x01]);
        final clientDataJSON =
            Uint8List.fromList([0xfa, 0xff, 0xbf, 0x7b, 0x22]);
        final attestationObject = Uint8List.fromList([0xf8, 0x3f, 0xff, 0x10]);
        final authenticatorData = Uint8List.fromList([0xfb, 0xef, 0xbe, 0x02]);

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
        // rawId: { pad: false, url: true }
        expect(body['rawId'], '-__-AQ');
        expect(body['authenticatorAttachment'], 'platform');
        expect(body['type'], 'public-key');
        expect(body['clientExtensionResults'], {
          'credProps': {'rk': true},
        });

        final response = body['response'] as Map<String, dynamic>;
        // clientDataJSON: defaults (standard alphabet, padded)
        expect(response['clientDataJSON'], '+v+/eyI=');
        // attestationObject: { url: true } (padded)
        expect(response['attestationObject'], '-D__EA==');
        // authenticatorData: defaults
        expect(response['authenticatorData'], '++++Ag==');
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
        // Same idea as verifyRegistration: +/ vs -_ and padding observable.
        // Expected strings: ox Base64.fromBytes with the options
        // permissionless.js verifyAuthentication passes.
        final rawId = Uint8List.fromList([0xfb, 0xff, 0xfe, 0x01]);
        final clientDataJSON =
            Uint8List.fromList([0xfa, 0xff, 0xbf, 0x7b, 0x22]);
        final authenticatorData = Uint8List.fromList([0xfb, 0xef, 0xbe, 0x02]);
        final signature = Uint8List.fromList([0xff, 0xfe, 0xfd, 0xfc, 0xfb]);
        final userHandle = Uint8List.fromList([0xfb, 0xff]);

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
        expect(body['rawId'], '-__-AQ');
        expect(body['type'], 'public-key');

        final response = body['response'] as Map<String, dynamic>;
        // clientDataJSON / signature / userHandle: { pad: false, url: true }
        expect(response['clientDataJSON'], '-v-_eyI');
        // authenticatorData: { url: true } (padded)
        expect(response['authenticatorData'], '----Ag==');
        expect(response['signature'], '__79_Ps');
        expect(response['userHandle'], '-_8');

        expect(params[1], {'uuid': 'session-uuid-1'});
        expect(result.success, isTrue);
        expect(result.publicKey, '0x04ff');
      });
    });
  });
}
