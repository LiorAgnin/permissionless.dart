/// Safe Smart Account implementation.
///
/// Safe (formerly Gnosis Safe) is the most widely used multi-signature
/// smart account in Ethereum, securing billions of dollars in assets.
///
/// ## Supported Versions
///
/// - **Safe v1.4.1** - Supports EntryPoint v0.6 and v0.7
/// - **Safe v1.5.0** - EntryPoint v0.7 only
///
/// ## Features
///
/// - Multi-owner support with configurable threshold
/// - EIP-1271 signature validation
/// - Module system for extensibility
/// - Fallback handler support
/// - EntryPoint v0.6 and v0.7 support
///
/// ## Note on ERC-7579
///
/// Standard Safe does NOT implement ERC-7579. However, Safe can optionally
/// be configured with ERC-7579 support via the Safe7579 launchpad by
/// providing `erc7579LaunchpadAddress` in permissionless.js.
///
/// This Dart implementation currently supports standard Safe only.
/// For native ERC-7579 support, consider Kernel v0.3.x or Nexus.
library;

export 'constants.dart';
export 'safe_account.dart';
