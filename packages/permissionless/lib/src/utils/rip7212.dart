/// RIP-7212 P256 Precompile Support
///
/// RIP-7212 adds a precompile for secp256r1 (P256) curve verification at
/// address `0x0000000000000000000000000000000000000100`.
///
/// This enables cheap (~3,450 gas vs ~800k gas) verification of WebAuthn/Passkey
/// signatures that use the P256 curve.
///
/// **WARNING:** As of late 2024, some chains (including testnets like Sepolia)
/// have unreliable RIP-7212 precompile behavior - they work in `eth_call` but
/// return empty data in actual transactions. The [supportsRip7212] function
/// lists chains that have announced RIP-7212 support, but this does NOT
/// guarantee the precompile works reliably. When in doubt, use on-chain P256
/// verification (`usePrecompiled: false`).
///
/// See: https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7212.md
/// See also: https://github.com/ethereum-optimism/developers/discussions/791
library;

/// The address of the RIP-7212 P256 precompile as a hex string.
///
/// This address is standardized across all chains that implement RIP-7212.
const p256PrecompileAddress = '0x0000000000000000000000000000000000000100';

/// Chain IDs known to support RIP-7212 P256 precompile.
///
/// This list is based on official announcements and deployments as of late 2024.
/// Chains are added here after RIP-7212 is confirmed deployed on mainnet.
///
/// Sources:
/// - Optimism Fjord upgrade: https://specs.optimism.io/protocol/precompiles.html
/// - Polygon: https://polygon.technology
/// - Base, Arbitrum, Scroll, Linea, Zora: Various L2 announcements
const Set<int> rip7212SupportedChainIds = {
  // Ethereum Mainnet (pending Osaka hardfork)
  // 1,

  // Ethereum Testnets
  11155111, // Sepolia

  // Optimism (OP Stack - Fjord release)
  10, // Optimism Mainnet
  11155420, // Optimism Sepolia

  // Base (OP Stack)
  8453, // Base Mainnet
  84532, // Base Sepolia

  // Polygon
  137, // Polygon Mainnet
  80002, // Polygon Amoy

  // Arbitrum
  42161, // Arbitrum One
  421614, // Arbitrum Sepolia

  // Scroll
  534352, // Scroll Mainnet
  534351, // Scroll Sepolia

  // Linea
  59144, // Linea Mainnet
  59141, // Linea Sepolia

  // Zora (OP Stack)
  7777777, // Zora Mainnet
  999999999, // Zora Sepolia

  // Gnosis
  100, // Gnosis Mainnet

  // zkSync Era
  324, // zkSync Era Mainnet
  300, // zkSync Sepolia

  // World Chain (OP Stack)
  480, // World Chain Mainnet

  // Cyber (OP Stack)
  7560, // Cyber Mainnet

  // Mode (OP Stack)
  34443, // Mode Mainnet

  // Fraxtal (OP Stack)
  252, // Fraxtal Mainnet

  // Blast
  81457, // Blast Mainnet
};

/// Checks if a chain supports the RIP-7212 P256 precompile.
///
/// Returns `true` if the chain is known to have the P256 precompile deployed,
/// enabling cheaper WebAuthn signature verification (~3,450 gas vs ~800k gas).
///
/// Example:
/// ```dart
/// if (supportsRip7212(chainId: BigInt.from(10))) {
///   // Use precompile for Optimism
///   encodeKernelWebAuthnSignature(sig, usePrecompiled: true);
/// }
/// ```
bool supportsRip7212({required BigInt chainId}) =>
    rip7212SupportedChainIds.contains(chainId.toInt());

/// Returns whether to use the P256 precompile for WebAuthn signatures.
///
/// This is a convenience wrapper that handles the common pattern of
/// checking chain support and returning the appropriate flag.
///
/// Example:
/// ```dart
/// final usePrecompiled = shouldUseP256Precompile(chainId: chainId);
/// encodeKernelWebAuthnSignature(sig, usePrecompiled: usePrecompiled);
/// ```
bool shouldUseP256Precompile({required BigInt chainId}) =>
    supportsRip7212(chainId: chainId);
