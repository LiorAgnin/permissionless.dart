import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../types/address.dart';
import '../types/typed_data.dart';
import 'account_owner.dart';

/// Raw P256 signature data from WebAuthn signing.
///
/// Contains all components needed for on-chain verification.
class P256SignatureData {
  /// Creates a P256 signature data object.
  const P256SignatureData({
    required this.r,
    required this.s,
    required this.authenticatorData,
    required this.clientDataJSON,
    required this.challengeIndex,
    required this.typeIndex,
  });

  /// The r component of the P256 signature.
  final BigInt r;

  /// The s component of the P256 signature.
  final BigInt s;

  /// Authenticator data from WebAuthn response.
  final Uint8List authenticatorData;

  /// Client data JSON string from WebAuthn response.
  final String clientDataJSON;

  /// Index of challenge in clientDataJSON.
  final int challengeIndex;

  /// Index of type field in clientDataJSON.
  final int typeIndex;
}

/// Abstract base class for WebAuthn/Passkey account owners.
///
/// WebAuthn owners use P256 (secp256r1) signatures instead of secp256k1,
/// requiring different signature encoding and validator/signer contracts.
///
/// Unlike ECDSA owners that have an Ethereum address, WebAuthn owners
/// are identified by their P256 public key coordinates (x, y).
///
/// Example:
/// ```dart
/// // WebAuthn owners can be used with smart accounts that support them
/// final kernelAccount = createKernelSmartAccount(
///   owner: webAuthnOwner,  // Detected via isWebAuthnAccount()
///   chainId: chainId,
///   version: KernelVersion.v0_3_1,
///   publicClient: publicClient,
/// );
/// ```
abstract class WebAuthnAccountOwner implements AccountOwner {
  /// Creates a WebAuthn account owner.
  const WebAuthnAccountOwner();

  @override
  String get type => OwnerType.webAuthn;

  /// The X coordinate of the P256 public key.
  BigInt get x;

  /// The Y coordinate of the P256 public key.
  BigInt get y;

  /// The raw credential ID bytes.
  ///
  /// Used by Kernel's WebAuthn validator to generate the authenticatorIdHash.
  /// This is the credential.rawId from WebAuthn registration.
  Uint8List get credentialId;

  /// The 64-byte P256 public key as hex (0x + x(64 hex) + y(64 hex)).
  String get publicKeyHex {
    final xHex = x.toRadixString(16).padLeft(64, '0');
    final yHex = y.toRadixString(16).padLeft(64, '0');
    return '0x$xHex$yHex';
  }

  /// Returns a dummy Ethereum address derived from the P256 public key.
  ///
  /// WebAuthn accounts don't have a real Ethereum address since they use
  /// P256 instead of secp256k1. This returns a deterministic address
  /// derived from the public key for compatibility with interfaces that
  /// require an address.
  ///
  /// **Note:** This address cannot receive funds or sign transactions directly.
  @override
  EthereumAddress get address {
    // Create a deterministic "address" from the P256 public key hash
    // This is for compatibility only - WebAuthn owners don't have real addresses
    final pubKeyBytes = _bigIntToBytes(x, 32) + _bigIntToBytes(y, 32);
    final hash = keccak256(Uint8List.fromList(pubKeyBytes));
    return EthereumAddress(hash.sublist(12));
  }

  /// Signs a hash directly and returns raw P256 signature data.
  ///
  /// This is the core signing method for WebAuthn owners. Smart accounts
  /// use this method and then encode the result according to their specific
  /// signature format (Kernel, Safe, etc.).
  ///
  /// [hash] - The 32-byte hash to sign (as hex string with 0x prefix).
  ///
  /// Returns [P256SignatureData] containing the signature components and
  /// WebAuthn metadata needed for on-chain verification.
  Future<P256SignatureData> signP256(String hash);

  /// Not supported for WebAuthn owners.
  ///
  /// WebAuthn signatures require account-specific encoding. Use [signP256]
  /// and encode the result using the appropriate encoding function.
  @override
  Future<String> signRawHash(String hash) async {
    throw UnsupportedError(
      'WebAuthn owners do not support signRawHash directly. '
      'Use signP256() and encode with the appropriate encoding function.',
    );
  }

  /// Not supported for WebAuthn owners.
  ///
  /// WebAuthn signatures require account-specific encoding. Use [signP256]
  /// and encode the result using the appropriate encoding function.
  @override
  Future<String> signPersonalMessage(String hash) async {
    throw UnsupportedError(
      'WebAuthn owners do not support signPersonalMessage directly. '
      'Use signP256() and encode with the appropriate encoding function.',
    );
  }

  /// Not supported for WebAuthn owners.
  ///
  /// WebAuthn signatures require account-specific encoding. Use [signP256]
  /// and encode the result using the appropriate encoding function.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    throw UnsupportedError(
      'WebAuthn owners do not support signTypedData directly. '
      'Use signP256() and encode with the appropriate encoding function.',
    );
  }

  /// Converts BigInt to fixed-length bytes.
  static List<int> _bigIntToBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
