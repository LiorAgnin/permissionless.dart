import 'dart:convert';
import 'dart:typed_data';

import 'package:permissionless/permissionless.dart'
    show
        EthereumAddress,
        Hex,
        P256SignatureData,
        TypedData,
        TypedDataDomain,
        TypedDataField,
        hashMessage,
        hashTypedData;
import 'package:web3_signers/web3_signers.dart';
import 'package:web3dart/web3dart.dart' show keccak256;

import '../types/webauthn_credential.dart';
import 'webauthn_account.dart';

/// Parameters for creating a WebAuthn account.
///
/// Matches viem's `ToWebAuthnAccountParameters` type.
class ToWebAuthnAccountParameters {
  /// Creates parameters for toWebAuthnAccount.
  const ToWebAuthnAccountParameters({
    required this.credential,
    this.rpId,
    this.getFn,
  });

  /// The WebAuthn credential containing public key coordinates.
  final WebAuthnCredential credential;

  /// Relying Party identifier (your domain).
  ///
  /// Must match the rpId used during credential registration. The credential
  /// does not record its rpId, so without an rpId (or an empty one) the
  /// account can only sign through [getFn].
  final String? rpId;

  /// Optional custom function for WebAuthn authentication.
  ///
  /// If provided, this function will be called instead of the default
  /// PassKeySigner authentication flow. Useful for custom WebAuthn
  /// implementations or testing.
  final Future<Signature> Function(Uint8List challenge)? getFn;
}

/// Creates a WebAuthn account from a credential.
///
/// This function matches viem's `toWebAuthnAccount` for API compatibility.
/// It creates an account that can sign messages using the device's
/// biometric authentication (Face ID, Touch ID, Windows Hello).
///
/// [params] - Configuration including credential and rpId.
///
/// Example:
/// ```dart
/// final account = toWebAuthnAccount(
///   ToWebAuthnAccountParameters(
///     credential: credential,
///     rpId: 'myapp.com',
///   ),
/// );
///
/// final signed = await account.sign(hash: userOpHash);
/// ```
WebAuthnAccount toWebAuthnAccount(ToWebAuthnAccountParameters params) {
  return _WebAuthnAccountImpl(
    credential: params.credential,
    rpId: params.rpId,
    getFn: params.getFn,
  );
}

/// Convenience function to create a WebAuthn account with named parameters.
///
/// This is the recommended way to create WebAuthn accounts in Dart,
/// using idiomatic named parameters instead of a parameters object.
///
/// Example:
/// ```dart
/// final account = createWebAuthnAccount(
///   credential: credential,
///   rpId: 'myapp.com',
/// );
///
/// print('Public Key: ${account.publicKey}');
///
/// final result = await account.sign(hash: '0x1234...');
/// print('Signature: ${result.signature}');
/// ```
WebAuthnAccount createWebAuthnAccount({
  required WebAuthnCredential credential,
  String? rpId,
  Future<Signature> Function(Uint8List challenge)? getFn,
}) {
  return _WebAuthnAccountImpl(credential: credential, rpId: rpId, getFn: getFn);
}

/// Creates a WebAuthn account from a credential.
///
/// Same as [createWebAuthnAccount]; kept under this name for existing
/// callers.
///
/// The account can be passed as an owner to smart accounts like
/// Kernel or Safe that support WebAuthn authentication.
///
/// [credential] - The WebAuthn credential (from `createPasskeyCredential`)
/// [rpId] - Relying Party identifier (must match credential registration)
/// [getFn] - Optional custom signing function for testing
///
/// Example:
/// ```dart
/// final webAuthnAccount = createWebAuthnAccountFromCredential(
///   credential: credential,
///   rpId: 'myapp.com',
/// );
///
/// // Use with Kernel smart account (v0.3.x supports WebAuthn)
/// final kernelAccount = createKernelSmartAccount(
///   owner: webAuthnAccount,
///   chainId: BigInt.from(11155111),
///   version: KernelVersion.v0_3_1,
///   publicClient: publicClient,
/// );
///
/// // Use with Safe smart account
/// final safeAccount = createSafeSmartAccount(
///   owners: [webAuthnAccount],
///   chainId: BigInt.from(11155111),
///   publicClient: publicClient,
/// );
/// ```
WebAuthnAccount createWebAuthnAccountFromCredential({
  required WebAuthnCredential credential,
  String? rpId,
  Future<Signature> Function(Uint8List challenge)? getFn,
}) {
  return _WebAuthnAccountImpl(credential: credential, rpId: rpId, getFn: getFn);
}

class _WebAuthnAccountImpl extends WebAuthnAccount {
  _WebAuthnAccountImpl({required this.credential, String? rpId, this.getFn})
    : _signer = rpId == null || rpId.isEmpty
          ? null
          // rpName is only shown during registration; signing ignores it.
          : PassKeySigner.withConfig(
              PassKeyConfig(rpId: rpId, rpName: rpId),
              credential.raw,
            );

  final WebAuthnCredential credential;
  final Future<Signature> Function(Uint8List challenge)? getFn;
  final PassKeySigner? _signer;

  @override
  String get id => credential.id;

  @override
  String get publicKey => publicKeyHex;

  @override
  BigInt get x => credential.x;

  @override
  BigInt get y => credential.y;

  @override
  Uint8List get credentialId => credential.rawId;

  @override
  Future<P256SignatureData> signP256(String hash) async =>
      (await sign(hash: hash)).toP256SignatureData();

  @override
  Future<WebAuthnSignReturnType> sign({required String hash}) async {
    final challenge = Hex.decode(hash);
    final signature = await _authenticate(challenge);

    final authenticatorData = signature.authData;
    final clientDataJSON = signature.clientDataJson;
    if (authenticatorData == null || clientDataJSON == null) {
      throw StateError(
        'The authenticator returned no WebAuthn metadata '
        '(authenticatorData/clientDataJSON); the signature cannot be '
        'verified on-chain.',
      );
    }

    return WebAuthnSignReturnType(
      signature: Hex.concat([
        Hex.fromBigInt(signature.r, byteLength: 32),
        Hex.fromBigInt(signature.s, byteLength: 32),
      ]),
      webauthn: WebAuthnSignMetadata(
        authenticatorData: authenticatorData,
        clientDataJSON: clientDataJSON,
        challengeIndex: signature.getChallengeLocation(challenge)!,
        typeIndex: signature.getTypeLocation()!,
      ),
      raw: signature,
    );
  }

  // viem semantics: a String is UTF-8 text even if it looks like hex; bytes
  // play the role of viem's `{ raw }`.
  @override
  Future<WebAuthnSignReturnType> signMessage({required dynamic message}) {
    final hash = switch (message) {
      String() => hashMessage(message),
      List<int>() => _hashRawMessage(message),
      _ => throw ArgumentError.value(
        message,
        'message',
        'must be a String or bytes',
      ),
    };
    return sign(hash: hash);
  }

  @override
  Future<WebAuthnSignReturnType> signTypedDataViem({
    required Map<String, dynamic> domain,
    required Map<String, List<Map<String, String>>> types,
    required String primaryType,
    required Map<String, dynamic> message,
  }) {
    final typedData = TypedData(
      domain: _typedDataDomain(domain),
      types: {
        for (final MapEntry(:key, :value) in types.entries)
          key: [
            for (final field in value)
              TypedDataField(name: field['name']!, type: field['type']!),
          ],
      },
      primaryType: primaryType,
      message: message,
    );
    return sign(hash: hashTypedData(typedData));
  }

  Future<Signature> _authenticate(Uint8List challenge) async {
    final getFn = this.getFn;
    if (getFn != null) {
      return getFn(challenge);
    }

    final signer = _signer;
    if (signer == null) {
      throw StateError(
        'Cannot sign: no rpId provided and no custom getFn configured. '
        'Provide rpId when creating the account or use a custom getFn.',
      );
    }

    return signer.signAsync(challenge);
  }
}

/// EIP-191 hash of raw bytes; core `hashMessage` only accepts UTF-8 text.
String _hashRawMessage(List<int> message) => Hex.fromBytes(
  keccak256(
    Uint8List.fromList([
      ...utf8.encode('\x19Ethereum Signed Message:\n${message.length}'),
      ...message,
    ]),
  ),
);

TypedDataDomain _typedDataDomain(Map<String, dynamic> domain) {
  final chainId = domain['chainId'];
  final verifyingContract = domain['verifyingContract'];
  return TypedDataDomain(
    name: domain['name'] as String?,
    version: domain['version'] as String?,
    chainId: switch (chainId) {
      null => null,
      BigInt() => chainId,
      int() => BigInt.from(chainId),
      _ => BigInt.parse(chainId.toString()),
    },
    verifyingContract: switch (verifyingContract) {
      null => null,
      EthereumAddress() => verifyingContract,
      _ => EthereumAddress.fromHex(verifyingContract.toString()),
    },
    salt: domain['salt'] as String?,
  );
}
