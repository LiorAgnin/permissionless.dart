/// Kernel smart account implementation.
///
/// Kernel (ZeroDev) is a modular ERC-4337 smart account that supports
/// plugins, validators, and executors.
///
/// ## Supported Versions
///
/// EntryPoint v0.6 (no ERC-7579):
/// - **0.2.1**, **0.2.2** (default for EP v0.6), **0.2.3**, **0.2.4**
///
/// EntryPoint v0.7 (ERC-7579):
/// - **0.3.0-beta** (default for EP v0.7; 4-arg `initialize`)
/// - **0.3.1**, **0.3.2**, **0.3.3** (EIP-7702)
///
/// Defaults match permissionless.js `toKernelSmartAccount`.
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
