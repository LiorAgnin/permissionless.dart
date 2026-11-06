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

/// Probe answers by chain ID. Precompile support does not change for a
/// chain, so an answer is kept for the lifetime of the application.
final Map<int, bool> _rip7212Cache = {};

/// Chain ID of each client already asked, so a cached answer costs no RPC.
var _clientChainIds = Expando<int>();

/// Dynamically checks if the connected chain supports the RIP-7212 P256 precompile.
///
/// Makes an `eth_call` to the precompile address with a known-valid P256
/// test vector. Returns `true` if the precompile exists and verifies
/// the signature correctly.
///
/// The answer is cached per chain ID once the precompile call returns:
/// precompile support is immutable for a given chain, so the probe runs
/// once. A call that fails (timeout, HTTP or JSON-RPC error) returns `false`
/// without caching it, so the next call probes again.
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
  final chainId = _clientChainIds[client] ??
      (_clientChainIds[client] = (await client.getChainId()).toInt());

  final cached = _rip7212Cache[chainId];
  if (cached != null) return cached;

  final bool supported;
  try {
    final result = await client.call(
      Call(
        to: EthereumAddress.fromHex(p256PrecompileAddress),
        // Precompile input: hash ‖ r ‖ s ‖ x ‖ y.
        data: Hex.concat([
          _p256TestHash,
          _p256TestR,
          _p256TestS,
          _p256TestX,
          _p256TestY,
        ]),
      ),
    );
    // Without the precompile the call hits an empty account and returns
    // `0x`; only a deployed precompile returns uint256(1).
    supported = Hex.toBigInt(result) == BigInt.one;
  } on Exception {
    return false;
  }
  return _rip7212Cache[chainId] = supported;
}

/// Clears the cached RIP-7212 support results.
///
/// Primarily useful for testing. In production, the cache is valid
/// for the lifetime of the application since precompile support
/// doesn't change for a given chain.
void clearRip7212Cache() {
  _rip7212Cache.clear();
  _clientChainIds = Expando<int>();
}
