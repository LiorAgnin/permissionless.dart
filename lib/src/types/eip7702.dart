import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' as crypto;
import 'package:web3dart/web3dart.dart';

import 'address.dart';
import 'hex.dart';

/// EIP-7702 Authorization for EOA code delegation.
///
/// An authorization allows an EOA to delegate its code to a smart contract
/// implementation. When included in a transaction, the EOA temporarily
/// "becomes" the smart contract for the duration of the transaction.
///
/// This enables EOAs to use smart account features without deploying
/// a separate contract or changing their address.
///
/// Example:
/// ```dart
/// final auth = await Eip7702Authorization.sign(
///   chainId: BigInt.from(1),
///   contractAddress: Simple7702AccountAddresses.defaultLogic,
///   nonce: BigInt.zero,
///   privateKey: ownerPrivateKey,
/// );
///
/// // Include auth in transaction to enable smart account features
/// ```
class Eip7702Authorization {
  const Eip7702Authorization({
    required this.chainId,
    required this.address,
    required this.nonce,
    required this.v,
    required this.r,
    required this.s,
  });

  /// The chain ID this authorization is valid for.
  ///
  /// Use `BigInt.zero` for chain-agnostic authorizations (valid on any chain).
  final BigInt chainId;

  /// The smart contract address to delegate code execution to.
  ///
  /// The EOA will execute code from this contract when the authorization is active.
  final EthAddress address;

  /// The EOA's nonce at the time of signing.
  ///
  /// This prevents replay attacks by ensuring each authorization is unique.
  final BigInt nonce;

  /// The recovery id (v value) of the ECDSA signature.
  final int v;

  /// The r component of the ECDSA signature.
  final String r;

  /// The s component of the ECDSA signature.
  final String s;

  /// Signs an EIP-7702 authorization.
  ///
  /// The authorization is signed using the EOA's private key and includes:
  /// - The chain ID (or 0 for chain-agnostic)
  /// - The contract address to delegate to
  /// - The EOA's current nonce
  ///
  /// Example:
  /// ```dart
  /// final auth = await Eip7702Authorization.sign(
  ///   chainId: BigInt.from(11155111), // Sepolia
  ///   contractAddress: Simple7702AccountAddresses.defaultLogic,
  ///   nonce: await publicClient.getTransactionCount(ownerAddress),
  ///   privateKey: '0x...',
  /// );
  /// ```
  static Future<Eip7702Authorization> sign({
    required BigInt chainId,
    required EthAddress contractAddress,
    required BigInt nonce,
    required String privateKey,
  }) async {
    final key = EthPrivateKey.fromHex(privateKey);

    // EIP-7702 authorization signing hash:
    // keccak256(MAGIC || rlp([chain_id, address, nonce]))
    // where MAGIC = 0x05
    final authHash = _computeAuthorizationHash(
      chainId: chainId,
      address: contractAddress,
      nonce: nonce,
    );

    // Sign the authorization hash directly using the raw sign function.
    // Note: signToEcSignature adds an extra keccak256 hash, which we don't want
    // since authHash is already a keccak256 hash.
    final signature = crypto.sign(
      Uint8List.fromList(authHash),
      key.privateKey,
    );

    return Eip7702Authorization(
      chainId: chainId,
      address: contractAddress,
      nonce: nonce,
      v: signature.v,
      r: Hex.fromBigInt(signature.r, byteLength: 32),
      s: Hex.fromBigInt(signature.s, byteLength: 32),
    );
  }

  /// Computes the authorization hash for signing.
  ///
  /// Format: keccak256(0x05 || rlp([chain_id, address, nonce]))
  static List<int> _computeAuthorizationHash({
    required BigInt chainId,
    required EthAddress address,
    required BigInt nonce,
  }) {
    // RLP encode [chain_id, address, nonce]
    // Each item must be individually RLP-encoded before passing to _rlpEncode
    final rlpData = _rlpEncode([
      _rlpEncodeBigInt(chainId),
      _rlpEncodeBytes(Hex.decode(address.hex)), // Fixed: RLP encode address
      _rlpEncodeBigInt(nonce),
    ]);

    // Prepend MAGIC byte (0x05 for EIP-7702)
    final preImage = [0x05, ...rlpData];

    return crypto.keccak256(Uint8List.fromList(preImage)).toList();
  }

  /// RLP encodes a byte array.
  static List<int> _rlpEncodeBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return [0x80]; // Empty byte array
    }

    if (bytes.length == 1 && bytes[0] < 0x80) {
      return bytes; // Single byte less than 0x80 is itself
    } else if (bytes.length <= 55) {
      return [0x80 + bytes.length, ...bytes];
    } else {
      final lengthBytes = _encodeLength(bytes.length);
      return [0xb7 + lengthBytes.length, ...lengthBytes, ...bytes];
    }
  }

  /// RLP encodes a list of already-encoded items.
  static List<int> _rlpEncode(List<List<int>> items) {
    final payload = <int>[];
    for (final item in items) {
      payload.addAll(item);
    }

    if (payload.length <= 55) {
      return [0xc0 + payload.length, ...payload];
    } else {
      final lengthBytes = _encodeLength(payload.length);
      return [0xf7 + lengthBytes.length, ...lengthBytes, ...payload];
    }
  }

  /// RLP encodes a BigInt value.
  static List<int> _rlpEncodeBigInt(BigInt value) {
    if (value == BigInt.zero) {
      return [0x80]; // Empty byte array
    }

    final bytes = _bigIntToBytes(value);

    if (bytes.length == 1 && bytes[0] < 0x80) {
      return bytes;
    } else if (bytes.length <= 55) {
      return [0x80 + bytes.length, ...bytes];
    } else {
      final lengthBytes = _encodeLength(bytes.length);
      return [0xb7 + lengthBytes.length, ...lengthBytes, ...bytes];
    }
  }

  /// Converts a BigInt to minimal bytes (no leading zeros).
  static List<int> _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return [];

    final hex = value.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    final bytes = <int>[];
    for (var i = 0; i < padded.length; i += 2) {
      bytes.add(int.parse(padded.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// Encodes a length as bytes.
  static List<int> _encodeLength(int length) {
    final bytes = <int>[];
    var remaining = length;
    while (remaining > 0) {
      bytes.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    return bytes;
  }

  /// Converts this authorization to JSON format for RPC calls.
  Map<String, dynamic> toJson() => {
        'chainId': Hex.fromBigInt(chainId),
        'address': address.hex,
        'nonce': Hex.fromBigInt(nonce),
        'v': Hex.fromBigInt(BigInt.from(v)),
        'r': r,
        's': s,
      };

  /// Converts this authorization to the format expected by bundlers.
  ///
  /// Uses Pimlico's bundler format with `address` field and hex-encoded values.
  /// Per viem's formatAuthorization:
  /// - address, chainId, nonce (hex-encoded)
  /// - r, s (32 bytes each, hex-encoded)
  /// - yParity (1 byte, hex-encoded)
  Map<String, dynamic> toRpcFormat() {
    final yParity = v - 27; // Convert v (27/28) to yParity (0/1)
    return {
      'chainId': Hex.fromBigInt(chainId),
      'address': address.hex,
      'nonce': Hex.fromBigInt(nonce),
      // yParity: 1 byte, properly padded
      'yParity': Hex.fromBigInt(BigInt.from(yParity), byteLength: 1),
      // r and s: 32 bytes each (already padded in sign())
      'r': r,
      's': s,
    };
  }

  @override
  String toString() =>
      'Eip7702Authorization(chainId: $chainId, address: ${address.checksummed}, nonce: $nonce)';
}
