// Apps import both barrels (see the package Quick Start). Every WebAuthn
// encoder name must then resolve to the single implementation in core
// `package:permissionless`; a same-named export from this package makes the
// unqualified calls below ambiguous and the file stops compiling.
import 'package:flutter_test/flutter_test.dart';
import 'package:permissionless/permissionless.dart';
import 'package:permissionless/permissionless.dart' as core;
import 'package:permissionless_passkeys/permissionless_passkeys.dart';
import 'package:web3_signers/web3_signers.dart' show PassKeyPublicKey, Uint256;
import 'package:web3_signers/web3_signers.dart' as signers;

import 'helpers/test_fixtures.dart';

void main() {
  group('importing permissionless and permissionless_passkeys together', () {
    final signature = P256SignatureData(
      r: testSignatureR,
      s: testSignatureS,
      authenticatorData: testAuthenticatorData,
      clientDataJSON: testClientDataJSON,
      challengeIndex: 23,
      typeIndex: testResponseTypeLocation,
    );
    const verifier = '0x445a0683e494ea0c5af3e83c5159fbe47cf9e765';

    test('getDummySafeWebAuthnSignature resolves to core', () {
      expect(
        getDummySafeWebAuthnSignature(),
        core.getDummySafeWebAuthnSignature(),
      );
    });

    test('getDummyKernelWebAuthnSignature resolves to core', () {
      expect(
        getDummyKernelWebAuthnSignature(usePrecompiled: true),
        core.getDummyKernelWebAuthnSignature(usePrecompiled: true),
      );
    });

    test('encodeSafeWebAuthnSignature resolves to core', () {
      expect(
        encodeSafeWebAuthnSignature(signature),
        core.encodeSafeWebAuthnSignature(signature),
      );
    });

    test('encodeKernelWebAuthnSignature resolves to core', () {
      expect(
        encodeKernelWebAuthnSignature(signature),
        core.encodeKernelWebAuthnSignature(signature),
      );
    });

    test('a passkeys account signature encodes with core encoders', () async {
      final account = createWebAuthnAccount(
        credential: WebAuthnCredential.fromPublicKey(
          PassKeyPublicKey(
            x: Uint256(testPublicKeyX),
            y: Uint256(testPublicKeyY),
            credentialId: testCredentialIdBytes,
            userName: 'test@example.com',
            aaGuid: '',
          ),
        ),
        getFn: (c) async => signers.Signature(
          testSignatureR,
          testSignatureS,
          authData: testAuthenticatorData,
          clientDataJson: clientDataJsonFor(c),
        ),
      );

      final data = await account.signP256(Hex.zero32);

      expect(
        encodeSafeWebAuthnSignature(data),
        core.encodeSafeWebAuthnSignature(data),
      );
      expect(
        encodeKernelWebAuthnSignature(data),
        core.encodeKernelWebAuthnSignature(data),
      );
    });

    test('encodeWebAuthnSignerConfigure uses the real configure selector', () {
      final calldata = encodeWebAuthnSignerConfigure(
        x: testPublicKeyX,
        y: testPublicKeyY,
        p256VerifierAddress: verifier,
      );

      expect(calldata.substring(0, 10), '0x0dd9692f');
      expect(
        encodeWebAuthnSignerConfig(
          x: testPublicKeyX,
          y: testPublicKeyY,
          p256VerifierAddress: verifier,
        ),
        core.encodeWebAuthnSignerConfig(
          x: testPublicKeyX,
          y: testPublicKeyY,
          p256VerifierAddress: verifier,
        ),
      );
    });
  });
}
