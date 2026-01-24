/// ERC-7579 module management actions.
///
/// This library provides actions for managing modules on ERC-7579
/// compliant smart accounts.
///
/// Example:
/// ```dart
/// import 'package:permissionless/actions/erc7579.dart';
///
/// // Install a module
/// final hash = await client.installModule(
///   type: Erc7579ModuleType.validator,
///   address: validatorAddress,
///   maxFeePerGas: gasPrices.fast.maxFeePerGas,
///   maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
/// );
///
/// // Query module status
/// final isInstalled = await isModuleInstalled(
///   publicClient: publicClient,
///   account: accountAddress,
///   moduleType: Erc7579ModuleType.validator,
///   module: validatorAddress,
/// );
/// ```
library;

export 'erc7579_actions.dart';
export 'module_queries.dart';
