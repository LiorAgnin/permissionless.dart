import '../../clients/bundler/types.dart';
import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_client.dart';
import '../../types/address.dart';
import '../../types/user_operation.dart';
import '../../utils/erc7579.dart';

/// Extension methods for ERC-7579 module management on [SmartAccountClient].
///
/// These methods allow you to install, uninstall, and manage modules
/// on ERC-7579 compliant smart accounts like Kernel and Etherspot.
///
/// Example:
/// ```dart
/// import 'package:permissionless/permissionless.dart';
///
/// // Install a validator module
/// final hash = await client.installModule(
///   type: Erc7579ModuleType.validator,
///   address: ecdsaValidatorAddress,
///   initData: encodedOwnerAddress,
///   maxFeePerGas: gasPrices.fast.maxFeePerGas,
///   maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
/// );
///
/// // Wait for confirmation
/// final receipt = await client.waitForReceipt(hash);
/// ```
extension Erc7579Actions on SmartAccountClient {
  /// Installs a single module on the smart account.
  ///
  /// The [initData] is passed to the module's `onInstall` function.
  /// Its format depends on the specific module being installed.
  ///
  /// Returns the UserOperation hash.
  ///
  /// Example:
  /// ```dart
  /// final hash = await client.installModule(
  ///   type: Erc7579ModuleType.validator,
  ///   address: passkeyValidatorAddress,
  ///   initData: encodedPasskeyCredential,
  ///   maxFeePerGas: BigInt.from(1000000000),
  ///   maxPriorityFeePerGas: BigInt.from(1000000000),
  /// );
  /// ```
  Future<String> installModule({
    required Erc7579ModuleType type,
    required EthAddress address,
    String initData = '0x',
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
  }) async {
    final accountAddress = await getAddress();

    final installCallData = encode7579InstallModule(
      moduleType: type,
      module: address,
      initData: initData,
    );

    return sendUserOperation(
      calls: [Call(to: accountAddress, data: installCallData)],
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );
  }

  /// Installs multiple modules in a single UserOperation.
  ///
  /// More gas-efficient than multiple individual installations.
  ///
  /// Returns the UserOperation hash.
  ///
  /// Example:
  /// ```dart
  /// final hash = await client.installModules(
  ///   modules: [
  ///     InstallModuleConfig(
  ///       type: Erc7579ModuleType.validator,
  ///       address: ecdsaValidatorAddress,
  ///       initData: encodedOwner,
  ///     ),
  ///     InstallModuleConfig(
  ///       type: Erc7579ModuleType.executor,
  ///       address: sessionKeyModuleAddress,
  ///       initData: encodedSessionKey,
  ///     ),
  ///   ],
  ///   maxFeePerGas: BigInt.from(1000000000),
  ///   maxPriorityFeePerGas: BigInt.from(1000000000),
  /// );
  /// ```
  Future<String> installModules({
    required List<InstallModuleConfig> modules,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
  }) async {
    if (modules.isEmpty) {
      throw ArgumentError('At least one module is required');
    }

    final accountAddress = await getAddress();

    final calls = modules.map((module) {
      final callData = encode7579InstallModule(
        moduleType: module.type,
        module: module.address,
        initData: module.initData,
      );
      return Call(to: accountAddress, data: callData);
    }).toList();

    return sendUserOperation(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );
  }

  /// Uninstalls a single module from the smart account.
  ///
  /// The [deInitData] is passed to the module's `onUninstall` function.
  /// Its format depends on the specific module being uninstalled.
  ///
  /// Returns the UserOperation hash.
  ///
  /// Example:
  /// ```dart
  /// final hash = await client.uninstallModule(
  ///   type: Erc7579ModuleType.executor,
  ///   address: oldSessionKeyModule,
  ///   deInitData: '0x',
  ///   maxFeePerGas: BigInt.from(1000000000),
  ///   maxPriorityFeePerGas: BigInt.from(1000000000),
  /// );
  /// ```
  Future<String> uninstallModule({
    required Erc7579ModuleType type,
    required EthAddress address,
    String deInitData = '0x',
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
  }) async {
    final accountAddress = await getAddress();

    final uninstallCallData = encode7579UninstallModule(
      moduleType: type,
      module: address,
      deInitData: deInitData,
    );

    return sendUserOperation(
      calls: [Call(to: accountAddress, data: uninstallCallData)],
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );
  }

  /// Uninstalls multiple modules in a single UserOperation.
  ///
  /// More gas-efficient than multiple individual uninstallations.
  ///
  /// Returns the UserOperation hash.
  ///
  /// Example:
  /// ```dart
  /// final hash = await client.uninstallModules(
  ///   modules: [
  ///     UninstallModuleConfig(
  ///       type: Erc7579ModuleType.executor,
  ///       address: oldExecutor1,
  ///     ),
  ///     UninstallModuleConfig(
  ///       type: Erc7579ModuleType.executor,
  ///       address: oldExecutor2,
  ///     ),
  ///   ],
  ///   maxFeePerGas: BigInt.from(1000000000),
  ///   maxPriorityFeePerGas: BigInt.from(1000000000),
  /// );
  /// ```
  Future<String> uninstallModules({
    required List<UninstallModuleConfig> modules,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
  }) async {
    if (modules.isEmpty) {
      throw ArgumentError('At least one module is required');
    }

    final accountAddress = await getAddress();

    final calls = modules.map((module) {
      final callData = encode7579UninstallModule(
        moduleType: module.type,
        module: module.address,
        deInitData: module.deInitData,
      );
      return Call(to: accountAddress, data: callData);
    }).toList();

    return sendUserOperation(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );
  }

  /// Installs a module and waits for the transaction to be confirmed.
  ///
  /// Convenience method that combines [installModule] with [waitForReceipt].
  ///
  /// Returns the UserOperation receipt, or null if timed out.
  Future<UserOperationReceipt?> installModuleAndWait({
    required Erc7579ModuleType type,
    required EthAddress address,
    String initData = '0x',
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    Duration timeout = const Duration(seconds: 60),
    Duration pollingInterval = const Duration(seconds: 2),
  }) async {
    final hash = await installModule(
      type: type,
      address: address,
      initData: initData,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );

    return waitForReceipt(
      hash,
      timeout: timeout,
      pollingInterval: pollingInterval,
    );
  }

  /// Uninstalls a module and waits for the transaction to be confirmed.
  ///
  /// Convenience method that combines [uninstallModule] with [waitForReceipt].
  ///
  /// Returns the UserOperation receipt, or null if timed out.
  Future<UserOperationReceipt?> uninstallModuleAndWait({
    required Erc7579ModuleType type,
    required EthAddress address,
    String deInitData = '0x',
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    Duration timeout = const Duration(seconds: 60),
    Duration pollingInterval = const Duration(seconds: 2),
  }) async {
    final hash = await uninstallModule(
      type: type,
      address: address,
      deInitData: deInitData,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );

    return waitForReceipt(
      hash,
      timeout: timeout,
      pollingInterval: pollingInterval,
    );
  }

  // ================================================================
  // Account Capability Queries
  // ================================================================

  /// Checks if the account supports a specific execution mode.
  ///
  /// ERC-7579 accounts may support different execution modes:
  /// - Single call (call)
  /// - Batch call (batchCall)
  /// - Delegate call (delegateCall)
  ///
  /// Each mode can also have different error handling behavior
  /// (revert on error vs try/continue).
  ///
  /// Example:
  /// ```dart
  /// // Check if batch calls with try mode are supported
  /// final supportsBatchTry = await client.supportsExecutionMode(
  ///   publicClient: publicClient,
  ///   mode: ExecutionMode(
  ///     type: Erc7579CallKind.batchCall,
  ///     revertOnError: false,
  ///   ),
  /// );
  ///
  /// if (supportsBatchTry) {
  ///   // Execute batch with try mode
  /// }
  /// ```
  Future<bool> supportsExecutionMode({
    required PublicClient publicClient,
    required ExecutionMode mode,
  }) async {
    final accountAddress = await getAddress();
    final callData = encode7579SupportsExecutionMode(mode);

    try {
      final result =
          await publicClient.call(Call(to: accountAddress, data: callData));
      return decode7579BoolResult(result);
    } catch (_) {
      // If the call fails, the mode is not supported
      return false;
    }
  }

  /// Checks if the account supports a specific module type.
  ///
  /// ERC-7579 accounts may support different module types:
  /// - Validator modules
  /// - Executor modules
  /// - Fallback handler modules
  /// - Hook modules
  ///
  /// Example:
  /// ```dart
  /// final supportsHooks = await client.supportsModule(
  ///   publicClient: publicClient,
  ///   moduleType: Erc7579ModuleType.hook,
  /// );
  /// ```
  Future<bool> supportsModule({
    required PublicClient publicClient,
    required Erc7579ModuleType moduleType,
  }) async {
    final accountAddress = await getAddress();
    final callData = encode7579SupportsModule(moduleType);

    try {
      final result =
          await publicClient.call(Call(to: accountAddress, data: callData));
      return decode7579BoolResult(result);
    } catch (_) {
      return false;
    }
  }

  /// Checks if a specific module is installed on the account.
  ///
  /// Returns true if the module of the specified type and address
  /// is currently installed.
  ///
  /// Example:
  /// ```dart
  /// final isInstalled = await client.isModuleInstalled(
  ///   publicClient: publicClient,
  ///   type: Erc7579ModuleType.validator,
  ///   address: ecdsaValidatorAddress,
  /// );
  /// ```
  Future<bool> isModuleInstalled({
    required PublicClient publicClient,
    required Erc7579ModuleType type,
    required EthAddress address,
    String additionalContext = '0x',
  }) async {
    final accountAddress = await getAddress();
    final callData = encode7579IsModuleInstalled(
      moduleType: type,
      module: address,
      additionalContext: additionalContext,
    );

    try {
      final result =
          await publicClient.call(Call(to: accountAddress, data: callData));
      return decode7579BoolResult(result);
    } catch (_) {
      return false;
    }
  }

  /// Gets the account's implementation identifier.
  ///
  /// Returns a string in the format "vendorname.accountname.semver",
  /// e.g., "kernel.advanced.0.3.1" or "safe.default.1.5.0".
  ///
  /// Example:
  /// ```dart
  /// final accountId = await client.getAccountId(publicClient: publicClient);
  /// print('Account type: $accountId');
  /// ```
  Future<String> getAccountId({
    required PublicClient publicClient,
  }) async {
    final accountAddress = await getAddress();
    final callData = encode7579AccountId();

    try {
      final result =
          await publicClient.call(Call(to: accountAddress, data: callData));
      return decode7579StringResult(result);
    } catch (_) {
      return '';
    }
  }
}
