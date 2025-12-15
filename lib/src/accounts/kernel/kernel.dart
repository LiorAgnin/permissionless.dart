/// Kernel smart account implementation.
///
/// Kernel (ZeroDev) is a modular ERC-4337 smart account that supports
/// plugins, validators, and executors.
///
/// ## Supported Versions
///
/// - **Kernel v0.2.4** (EntryPoint v0.6) - Legacy version, no ERC-7579
/// - **Kernel v0.3.1** (EntryPoint v0.7) - Full ERC-7579 modular account
/// - **Kernel v0.3.3** (EntryPoint v0.7) - Latest, includes EIP-7702 support
///
/// ## ERC-7579 Support
///
/// Kernel v0.3.x implements the full ERC-7579 modular account standard:
/// - ERC-7579 call encoding (`execute(bytes32 mode, bytes executionCalldata)`)
/// - Module installation/uninstallation (validators, executors, hooks)
/// - Module type queries (`supportsModule`, `isModuleInstalled`)
/// - Execution mode queries (`supportsExecutionMode`)
///
/// Note: Kernel v0.2.x does NOT support ERC-7579.
library;

export 'constants.dart';
export 'eip7702_kernel_account.dart';
export 'kernel_account.dart';
