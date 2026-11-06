import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show keccak256;

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
/// This returns a properly formatted but invalid signature with the correct
/// byte length for bundler gas estimation.
///
/// [usePrecompiled] - Whether to use RIP-7212 P256 precompile. Set based on
/// chain support using `shouldUseP256Precompile` or `isRip7212Supported`.
String getDummyKernelWebAuthnSignature({bool usePrecompiled = false}) =>
    encodeKernelWebAuthnSignature(
      P256SignatureData(
        r: BigInt.parse(
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          radix: 16,
        ),
        s: BigInt.parse(
          '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0',
          radix: 16,
        ),
        // Typical authenticator data length.
        authenticatorData: Uint8List(37),
        clientDataJSON:
            '{"type":"webauthn.get","challenge":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","origin":"https://example.com"}',
        challengeIndex: 0,
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
