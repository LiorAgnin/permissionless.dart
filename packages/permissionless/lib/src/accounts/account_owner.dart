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
  /// Informational, mirroring viem's `account.type`: no account in this
  /// library reads it. Accounts pick WebAuthn signature encoding by class, so
  /// a passkey owner must extend `WebAuthnAccountOwner`; overriding [type]
  /// alone still gets ECDSA encoding.
  String get type => OwnerType.local;

  /// The Ethereum address of this owner.
  EthereumAddress get address;

  /// Signs a hash with EIP-191 personal message prefix.
  ///
  /// This adds the standard Ethereum prefix before signing:
  /// `"\x19Ethereum Signed Message:\n32" + hash`
  Future<String> signPersonalMessage(String hash);

  /// Signs a hash directly without any prefix.
  ///
  /// This signs the raw hash bytes using ECDSA.
  Future<String> signRawHash(String hash);

  /// Signs EIP-712 typed data.
  ///
  /// This computes the EIP-712 hash and signs it directly (no personal prefix).
  Future<String> signTypedData(TypedData typedData);
}

/// Private key-based implementation of [AccountOwner].
///
/// Example:
/// ```dart
/// final owner = PrivateKeyOwner('0x<your-private-key>');
/// print(owner.address); // the EOA address derived from the key
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

  /// The uncompressed secp256k1 public key (64 bytes, without the `04`
  /// prefix; web3dart's `privateKeyBytesToPublic` already drops it).
  Uint8List get publicKey => privateKeyBytesToPublic(_privateKey.privateKey);

  @override
  Future<String> signPersonalMessage(String hash) async => Hex.fromBytes(
        _privateKey.signPersonalMessageToUint8List(Hex.decode(hash)),
      );

  @override
  Future<String> signRawHash(String hash) async => _signDigest(hash);

  @override
  Future<String> signTypedData(TypedData typedData) async =>
      _signDigest(hashTypedData(typedData));

  /// ECDSA over the 32-byte [digest] as `r ‖ s ‖ v` (65 bytes).
  ///
  /// web3dart's `sign` already returns `v` as 27 or 28.
  String _signDigest(String digest) {
    final sig = sign(Hex.decode(digest), _privateKey.privateKey);
    return Hex.concat([
      Hex.fromBigInt(sig.r, byteLength: 32),
      Hex.fromBigInt(sig.s, byteLength: 32),
      Hex.fromBigInt(BigInt.from(sig.v), byteLength: 1),
    ]);
  }
}
