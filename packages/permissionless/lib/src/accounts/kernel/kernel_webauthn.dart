import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show keccak256;

import '../../types/hex.dart';
import '../../utils/encoding.dart';
import '../webauthn_owner.dart';

/// `abi.encode` layout the Kernel WebAuthn validator decodes a signature from.
const _kernelWebAuthnSignatureTypes = [
  'bytes', // authenticatorData
  'string', // clientDataJSON
  'uint256', // responseTypeLocation
  'uint256', // r
  'uint256', // s
  'bool', // usePrecompiled
];

/// Encodes a P256 signature for Kernel WebAuthn validator verification.
///
/// The Kernel WebAuthn validator expects:
/// ```solidity
/// abi.encode(
///   bytes authenticatorData,
///   string clientDataJSON,
///   uint256 responseTypeLocation,
///   uint256 r,
///   uint256 s,
///   bool usePrecompiled
/// )
/// ```
///
/// [signature] - The raw P256 signature data from WebAuthn signing.
/// [usePrecompiled] - Whether to use RIP-7212 P256 precompile (default: true).
///
/// Example:
/// ```dart
/// final sigData = await webAuthnOwner.signP256(userOpHash);
/// final encoded = encodeKernelWebAuthnSignature(sigData);
/// ```
String encodeKernelWebAuthnSignature(
  P256SignatureData signature, {
  bool usePrecompiled = true,
}) =>
    AbiEncoder.encodeParameters(_kernelWebAuthnSignatureTypes, [
      signature.authenticatorData,
      signature.clientDataJSON,
      signature.typeIndex,
      signature.r,
      signature.s,
      usePrecompiled,
    ]);

/// Returns a dummy Kernel WebAuthn signature for gas estimation.
///
/// The values are permissionless.js `toKernelSmartAccount.getStubSignature`'s.
/// r and s lie inside the P-256 curve order, so a bundler's simulation runs
/// the verifier's full curve math before the signature fails; an
/// out-of-range r would be rejected early and make the estimate far too low.
///
/// Keep [usePrecompiled] false for estimation unless the account will
/// definitely sign with the RIP-7212 precompile: the Solidity verifier costs
/// more gas, so a `false` stub covers both encodings.
String getDummyKernelWebAuthnSignature({bool usePrecompiled = false}) =>
    encodeKernelWebAuthnSignature(
      P256SignatureData(
        r: BigInt.parse(
          '44941127272049826721201904734628716258498742255959991581049806490182030242267',
        ),
        s: BigInt.parse(
          '9910254599581058084911561569808925251374718953855182016200087235935345969636',
        ),
        authenticatorData: Hex.decode(
          '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631d00000000',
        ),
        clientDataJSON: '{"type":"webauthn.get",'
            '"challenge":"tbxXNFS9X_4Byr1cMwqKrIGB-_30a0QhZ6y7ucM0BOE",'
            '"origin":"http://localhost:3000","crossOrigin":false, '
            '"other_keys_can_be_added_here":"do not compare clientDataJSON '
            'against a template. See https://goo.gl/yabPex"}',
        challengeIndex: 23,
        typeIndex: 1,
      ),
      usePrecompiled: usePrecompiled,
    );

/// Encodes the WebAuthn validator data for Kernel v0.3.x initialization.
///
/// The WebAuthn validator expects ABI-encoded tuple + authenticatorIdHash:
/// ```solidity
/// (tuple(uint256 x, uint256 y) webAuthnData, bytes32 authenticatorIdHash)
/// ```
///
/// Where authenticatorIdHash = keccak256(credentialId)
String encodeKernelWebAuthnValidatorData({
  required BigInt x,
  required BigInt y,
  required Uint8List credentialId,
}) =>
    AbiEncoder.encodeParameters(
      ['(uint256,uint256)', 'bytes32'],
      [
        [x, y],
        keccak256(credentialId),
      ],
    );
