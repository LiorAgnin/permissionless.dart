import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../../utils/rip7212.dart';
import 'public_client.dart';

// First Wycheproof vector in daimo-eth/p256-verifier: a valid P256
// signature, so a deployed precompile must return uint256(1).
const _p256TestHash =
    '0xbb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023';
const _p256TestR =
    '0x2ba3a8be6b94d5ec80a6d9d1190a436effe50d85a1eee859b8cc6af9bd5c2e18';
const _p256TestS =
    '0x4cd60b855d442f5b3c7b11eb6c4e0ae7525fe710fab9aa7c77a67f79e6fadd76';
const _p256TestX =
    '0x2927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838';
const _p256TestY =
    '0xc7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e';

/// Cache of RIP-7212 support results, keyed by chain ID.
///
/// Precompile support is immutable for a given chain, so results are
/// cached for the lifetime of the application.
final Map<int, bool> _rip7212Cache = {};

/// Dynamically checks if the connected chain supports the RIP-7212 P256 precompile.
///
/// Makes an `eth_call` to the precompile address with a known-valid P256
/// test vector. Returns `true` if the precompile exists and verifies
/// the signature correctly.
///
/// Results are cached per chain ID — precompile support is immutable
/// for a given chain, so the expensive RPC call only happens once.
///
/// This is more reliable than the static [supportsRip7212] check since
/// it detects support on any chain, including new chains not yet in
/// [rip7212SupportedChainIds].
///
/// Example:
/// ```dart
/// final client = createPublicClient(url: 'https://rpc.example.com');
/// final supported = await isRip7212Supported(client);
/// if (supported) {
///   // Use precompile for cheaper P256 verification
/// }
/// ```
Future<bool> isRip7212Supported(PublicClient client) async {
  final chainId = (await client.getChainId()).toInt();

  if (_rip7212Cache.containsKey(chainId)) {
    return _rip7212Cache[chainId]!;
  }

  // Precompile input: hash || r || s || x || y (5 × 32 bytes = 160 bytes)
  final calldata = Hex.concat([
    _p256TestHash,
    _p256TestR,
    _p256TestS,
    _p256TestX,
    _p256TestY,
  ]);

  try {
    final result = await client.call(
      Call(
        to: EthereumAddress.fromHex(p256PrecompileAddress),
        data: calldata,
      ),
    );

    // Success: precompile returns uint256(1) for valid signature
    final supported = Hex.toBigInt(result) == BigInt.one;
    _rip7212Cache[chainId] = supported;
    return supported;
  } on Exception {
    // Reverts or empty response → precompile not deployed on this chain
    _rip7212Cache[chainId] = false;
    return false;
  }
}

/// Clears the cached RIP-7212 support results.
///
/// Primarily useful for testing. In production, the cache is valid
/// for the lifetime of the application since precompile support
/// doesn't change for a given chain.
void clearRip7212Cache() => _rip7212Cache.clear();
