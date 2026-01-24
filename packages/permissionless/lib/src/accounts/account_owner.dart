import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/typed_data.dart';
import '../utils/message_hash.dart';

/// Owner type identifiers for smart account owners.
///
/// Used to distinguish between different owner types (ECDSA, WebAuthn, etc.)
/// in smart account implementations.
class OwnerType {
  OwnerType._();

  /// Standard ECDSA private key owner.
  static const String local = 'local';

  /// WebAuthn/Passkey owner using P256 signatures.
  static const String webAuthn = 'webAuthn';
}

/// Base interface for all smart account owners.
///
/// This unified interface supports all signing modes required by different
/// ERC-4337 smart account implementations:
/// - Personal message signing (EIP-191) for most accounts
/// - Raw hash signing for accounts like Kernel
/// - EIP-712 typed data signing for accounts like Safe
abstract class AccountOwner {
  /// Creates an [AccountOwner].
  ///
  /// Implementations must provide all signing methods to support
  /// various smart account signing requirements.
  const AccountOwner();

  /// The type of this owner (e.g., 'local' for ECDSA, 'webAuthn' for passkeys).
  ///
  /// Smart accounts use this to determine how to encode signatures.
  String get type => OwnerType.local;

  /// The Ethereum address of this owner.
  EthereumAddress get address;

  /// Signs a hash with EIP-191 personal message prefix.
  ///
  /// This adds the standard Ethereum prefix before signing:
  /// `"\x19Ethereum Signed Message:\n32" + hash`
  ///
  /// Used by: SimpleAccount, Nexus, Biconomy, Light, Trust, Thirdweb, Etherspot
  Future<String> signPersonalMessage(String hash);

  /// Signs a hash directly without any prefix.
  ///
  /// This signs the raw hash bytes using ECDSA.
  ///
  /// Used by: Kernel
  Future<String> signRawHash(String hash);

  /// Signs EIP-712 typed data.
  ///
  /// This computes the EIP-712 hash and signs it directly (no personal prefix).
  ///
  /// Used by: Safe, Trust, Light, Thirdweb
  Future<String> signTypedData(TypedData typedData);
}

/// Private key-based implementation of [AccountOwner].
///
/// This single implementation handles all signing modes, replacing the
/// previously duplicated PrivateKey*Owner classes.
///
/// Example:
/// ```dart
/// final owner = PrivateKeyOwner('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
/// print(owner.address); // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
///
/// // For SimpleAccount, Nexus, etc.
/// final sig = await owner.signPersonalMessage(userOpHash);
///
/// // For Kernel
/// final sig = await owner.signRawHash(userOpHash);
///
/// // For Safe EIP-712
/// final sig = await owner.signTypedData(typedData);
/// ```
class PrivateKeyOwner implements AccountOwner {
  /// Creates an owner from a hex-encoded private key.
  ///
  /// The private key can optionally include the '0x' prefix.
  PrivateKeyOwner(String privateKeyHex)
      : _privateKey = EthPrivateKey.fromHex(privateKeyHex);

  final EthPrivateKey _privateKey;

  @override
  String get type => OwnerType.local;

  @override
  EthereumAddress get address => _privateKey.address;

  /// The public key (64 bytes, uncompressed without 04 prefix).
  ///
  /// Required by TrustAccount for the Barz factory.
  Uint8List get publicKey {
    final fullPubKey = privateKeyBytesToPublic(_privateKey.privateKey);
    // Remove the 04 prefix if present (uncompressed point marker)
    if (fullPubKey.length == 65 && fullPubKey[0] == 0x04) {
      return Uint8List.fromList(fullPubKey.sublist(1));
    }
    return fullPubKey;
  }

  @override
  Future<String> signPersonalMessage(String hash) async {
    final hashBytes = Hex.decode(hash);

    // Use web3dart's signPersonalMessageToUint8List which:
    // 1. Adds "\x19Ethereum Signed Message:\n{length}" prefix
    // 2. Hashes with keccak256
    // 3. Signs with ECDSA
    // 4. Returns r + s + v (65 bytes)
    final signature = _privateKey.signPersonalMessageToUint8List(
      Uint8List.fromList(hashBytes),
    );

    return Hex.fromBytes(signature);
  }

  @override
  Future<String> signRawHash(String hash) async {
    final hashBytes = Hex.decode(hash);

    // Sign the hash directly using low-level sign() from web3dart/crypto
    // This does NOT add any prefix - it signs the raw 32-byte hash
    final sig = sign(Uint8List.fromList(hashBytes), _privateKey.privateKey);

    // Encode as r (32 bytes) + s (32 bytes) + v (1 byte)
    final r = Hex.fromBigInt(sig.r, byteLength: 32);
    final s = Hex.fromBigInt(sig.s, byteLength: 32);
    var v = sig.v;
    if (v < 27) {
      v += 27;
    }

    return Hex.concat([r, s, Hex.fromBigInt(BigInt.from(v), byteLength: 1)]);
  }

  @override
  Future<String> signTypedData(TypedData typedData) async {
    // Compute EIP-712 hash
    final hash = hashTypedData(typedData);
    final hashBytes = Hex.decode(hash);

    // Sign the EIP-712 hash directly (no personal message prefix)
    final sig = sign(Uint8List.fromList(hashBytes), _privateKey.privateKey);

    // Encode as r (32 bytes) + s (32 bytes) + v (1 byte)
    final r = Hex.fromBigInt(sig.r, byteLength: 32);
    final s = Hex.fromBigInt(sig.s, byteLength: 32);
    var v = sig.v;
    if (v < 27) {
      v += 27;
    }

    return Hex.concat([r, s, Hex.fromBigInt(BigInt.from(v), byteLength: 1)]);
  }
}
