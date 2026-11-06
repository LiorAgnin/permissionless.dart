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
/// Standard Safe does NOT implement ERC-7579. Passing
/// `erc7579LaunchpadAddress` deploys the Safe through the Safe7579 launchpad
/// with the Safe7579 adapter as its module, as permissionless.js does.
library;

export 'constants.dart';
export 'multisend.dart';
export 'safe_account.dart';
export 'safe_encoding.dart'
    hide decodeSafeExecuteUserOp, decodeSafeSetupSafe, safe7579InitHash;
