/// RIP-7212 / EIP-7951 P256 Precompile Support
///
/// Adds a precompile for secp256r1 (P256) curve verification at
/// address `0x0000000000000000000000000000000000000100`.
///
/// This enables cheap verification of WebAuthn/Passkey signatures:
/// - **L2s (RIP-7212)**: ~3,450 gas
/// - **Ethereum Mainnet (EIP-7951)**: ~6,900 gas
/// - **Solidity verifier**: ~800,000 gas
///
/// **Note:** Ethereum mainnet has supported this via EIP-7951 since the
/// Fusaka upgrade (December 3, 2025). Most L2s support RIP-7212.
///
/// See: https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7212.md
/// See: https://eips.ethereum.org/EIPS/eip-7951
///
/// This library is the static chain list; `isRip7212Supported` probes a live
/// chain through a `PublicClient`.
library;

/// The address of the RIP-7212 P256 precompile as a hex string.
///
/// This address is standardized across all chains that implement RIP-7212.
const p256PrecompileAddress = '0x0000000000000000000000000000000000000100';

/// Chain IDs known to support the P256 precompile.
///
/// This list is based on official announcements and deployments.
/// Chains are added here after the precompile is confirmed deployed.
///
/// Sources:
/// - Ethereum EIP-7951 (Fusaka): https://eips.ethereum.org/EIPS/eip-7951
/// - Optimism Fjord upgrade: https://specs.optimism.io/protocol/precompiles.html
/// - ZeroDev: https://docs.zerodev.app/sdk/advanced/passkeys#chains-with-native-passkey-precompiles
/// - Polygon, Arbitrum, Scroll, Linea, Zora, Celo: Various announcements
const Set<int> rip7212SupportedChainIds = {
  // ── Ethereum ──────────────────────────────────────────────────────────────
  1, // Ethereum Mainnet (EIP-7951 via Fusaka upgrade, Dec 3 2025)
  11155111, // Sepolia
  17000, // Holesky

  // ── Optimism (OP Stack - Fjord release) ───────────────────────────────────
  10, // OP Mainnet
  11155420, // OP Sepolia

  // ── Base (OP Stack) ───────────────────────────────────────────────────────
  8453, // Base Mainnet
  84532, // Base Sepolia

  // ── Unichain (OP Stack) ───────────────────────────────────────────────────
  130, // Unichain Mainnet
  1301, // Unichain Sepolia

  // ── Mode (OP Stack) ───────────────────────────────────────────────────────
  34443, // Mode Mainnet
  919, // Mode Sepolia

  // ── Zora (OP Stack) ───────────────────────────────────────────────────────
  7777777, // Zora Mainnet
  999999999, // Zora Sepolia

  // ── World Chain (OP Stack) ────────────────────────────────────────────────
  480, // World Chain Mainnet

  // ── Cyber (OP Stack) ──────────────────────────────────────────────────────
  7560, // Cyber Mainnet

  // ── Fraxtal (OP Stack) ────────────────────────────────────────────────────
  252, // Fraxtal Mainnet

  // ── Ink (OP Stack) ────────────────────────────────────────────────────────
  57073, // Ink Mainnet
  763373, // Ink Sepolia

  // ── Shape (OP Stack) ──────────────────────────────────────────────────────
  360, // Shape Mainnet

  // ── Polynomial (OP Stack) ─────────────────────────────────────────────────
  8008, // Polynomial Mainnet

  // ── Mint (OP Stack) ───────────────────────────────────────────────────────
  185, // Mint Mainnet

  // ── Katana (OP Stack) ─────────────────────────────────────────────────────
  747474, // Katana Mainnet

  // ── Degen (OP Stack) ──────────────────────────────────────────────────────
  666666666, // Degen Mainnet

  // ── BOB (OP Stack) ────────────────────────────────────────────────────────
  60808, // BOB Mainnet

  // ── Onyx (OP Stack) ───────────────────────────────────────────────────────
  80888, // Onyx Mainnet

  // ── BNB Smart Chain ───────────────────────────────────────────────────────
  56, // BNB Smart Chain Mainnet
  204, // opBNB Mainnet
  97, // BNB Smart Chain Testnet

  // ── Polygon ───────────────────────────────────────────────────────────────
  137, // Polygon Mainnet
  80002, // Polygon Amoy

  // ── Arbitrum ──────────────────────────────────────────────────────────────
  42161, // Arbitrum One
  42170, // Arbitrum Nova
  421614, // Arbitrum Sepolia

  // ── Scroll ────────────────────────────────────────────────────────────────
  534352, // Scroll Mainnet
  534351, // Scroll Sepolia

  // ── Linea ─────────────────────────────────────────────────────────────────
  59144, // Linea Mainnet
  59141, // Linea Sepolia

  // ── zkSync Era ────────────────────────────────────────────────────────────
  324, // zkSync Era Mainnet
  300, // zkSync Sepolia

  // ── Avalanche ─────────────────────────────────────────────────────────────
  43114, // Avalanche C-Chain
  43113, // Avalanche Fuji

  // ── Mantle ────────────────────────────────────────────────────────────────
  5000, // Mantle Mainnet
  5003, // Mantle Sepolia

  // ── Celo ──────────────────────────────────────────────────────────────────
  42220, // Celo Mainnet

  // ── X Layer ───────────────────────────────────────────────────────────────
  196, // X Layer Mainnet
  195, // X Layer Testnet

  // ── Flow ──────────────────────────────────────────────────────────────────
  747, // Flow Mainnet

  // ── Story ─────────────────────────────────────────────────────────────────
  1514, // Story Mainnet
  1315, // Story Aeneid (testnet)

  // ── Monad ─────────────────────────────────────────────────────────────────
  143, // Monad Mainnet
  10143, // Monad Testnet

  // ── Abstract ──────────────────────────────────────────────────────────────
  2741, // Abstract Mainnet

  // ── Hemi ──────────────────────────────────────────────────────────────────
  43111, // Hemi Network Mainnet
  743111, // Hemi Sepolia

  // ── Plume ─────────────────────────────────────────────────────────────────
  98866, // Plume Mainnet
  98867, // Plume Testnet

  // ── Ethernity ─────────────────────────────────────────────────────────────
  183, // Ethernity Mainnet

  // ── Apechain ──────────────────────────────────────────────────────────────
  33139, // Apechain Mainnet
  33111, // Curtis Testnet (Apechain)

  // ── ZetaChain ─────────────────────────────────────────────────────────────
  7000, // ZetaChain Mainnet

  // ── B3 ────────────────────────────────────────────────────────────────────
  8333, // B3 Mainnet

  // ── Warden Protocol ───────────────────────────────────────────────────────
  8765, // Warden Protocol Mainnet

  // ── Edge ──────────────────────────────────────────────────────────────────
  3343, // Edge Mainnet

  // ── Perennial ─────────────────────────────────────────────────────────────
  1424, // Perennial Mainnet

  // ── MegaETH ───────────────────────────────────────────────────────────────
  6343, // MegaETH Testnet v2

  // ── Open Campus ───────────────────────────────────────────────────────────
  656476, // Open Campus Codex

  // ── Incentiv ──────────────────────────────────────────────────────────────
  28802, // Incentiv Testnet
};

/// Checks if a chain supports the P256 precompile (RIP-7212 / EIP-7951).
///
/// Returns `true` if the chain is known to have the P256 precompile deployed,
/// enabling cheaper WebAuthn signature verification:
/// - L2s: ~3,450 gas (RIP-7212)
/// - Mainnet: ~6,900 gas (EIP-7951)
/// - Without precompile: ~800,000 gas
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
/// Same as [supportsRip7212].
@Deprecated('Use supportsRip7212')
bool shouldUseP256Precompile({required BigInt chainId}) =>
    supportsRip7212(chainId: chainId);
