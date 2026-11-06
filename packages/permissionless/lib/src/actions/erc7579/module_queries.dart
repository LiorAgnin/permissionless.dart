import '../../clients/public/public_client.dart';
import '../../types/address.dart';
import '../../types/user_operation.dart';
import '../../utils/erc7579.dart';

/// Checks if a module is installed on an ERC-7579 account.
///
/// Queries the account using `isModuleInstalled(uint256, address, bytes)`.
///
/// The [additionalContext] is typically empty but some modules may
/// require additional data for the check.
///
/// Throws [StateError] when the call returns no data (`0x`): [account] has
/// no code on this chain, e.g. it is not deployed yet. This function has no
/// factory to retry with; for a counterfactual account use
/// `SmartAccountClient.isModuleInstalled`, which retries through the factory
/// (permissionless.js parity).
///
/// Example:
/// ```dart
/// final isInstalled = await isModuleInstalled(
///   publicClient: publicClient,
///   account: myAccount,
///   moduleType: Erc7579ModuleType.validator,
///   module: ecdsaValidatorAddress,
/// );
///
/// if (!isInstalled) {
///   print('Need to install validator module');
/// }
/// ```
Future<bool> isModuleInstalled({
  required PublicClient publicClient,
  required EthereumAddress account,
  required Erc7579ModuleType moduleType,
  required EthereumAddress module,
  String additionalContext = '0x',
}) async {
  final callData = encode7579IsModuleInstalled(
    moduleType: moduleType,
    module: module,
    additionalContext: additionalContext,
  );

  final result = await _readAccount(
    publicClient,
    account,
    callData,
    'isModuleInstalled',
  );
  return decode7579BoolResult(result);
}

/// Checks if an ERC-7579 account supports a particular module type.
///
/// Queries the account using `supportsModule(uint256)`.
///
/// Use this before attempting to install a module to ensure the
/// account implementation supports that module type.
///
/// Throws [StateError] when the call returns no data (`0x`): [account] has
/// no code on this chain, e.g. it is not deployed yet. This function has no
/// factory to retry with; for a counterfactual account use
/// `SmartAccountClient.supportsModule`, which retries through the factory
/// (permissionless.js parity).
///
/// Example:
/// ```dart
/// final supportsHooks = await supportsModule(
///   publicClient: publicClient,
///   account: myAccount,
///   moduleType: Erc7579ModuleType.hook,
/// );
///
/// if (supportsHooks) {
///   print('Account supports hook modules');
/// } else {
///   print('Account does not support hooks');
/// }
/// ```
Future<bool> supportsModule({
  required PublicClient publicClient,
  required EthereumAddress account,
  required Erc7579ModuleType moduleType,
}) async {
  final callData = encode7579SupportsModule(moduleType);
  final result =
      await _readAccount(publicClient, account, callData, 'supportsModule');
  return decode7579BoolResult(result);
}

/// Gets the account identifier from an ERC-7579 account.
///
/// Queries the account using `accountId()` which returns a string
/// in the format "vendorname.accountname.semver".
///
/// Throws [StateError] when the call returns no data (`0x`): [account] has
/// no code on this chain, e.g. it is not deployed yet. This function has no
/// factory to retry with; for a counterfactual account use
/// `SmartAccountClient.getAccountId`, which retries through the factory
/// (permissionless.js parity).
///
/// Example:
/// ```dart
/// final accountId = await getAccountId(
///   publicClient: publicClient,
///   account: myAccount,
/// );
///
/// print('Account ID: $accountId'); // e.g., "kernel.advanced.0.3.1"
/// ```
Future<String> getAccountId({
  required PublicClient publicClient,
  required EthereumAddress account,
}) async {
  final callData = encode7579AccountId();
  final result =
      await _readAccount(publicClient, account, callData, 'getAccountId');
  return decode7579StringResult(result);
}

/// Gets the installed modules of a specific type from an ERC-7579 account.
///
/// This is a convenience function that queries multiple addresses to find
/// which ones are installed. The [candidateModules] list should contain
/// the addresses of modules you want to check.
///
/// Returns a list of addresses that are installed.
///
/// Throws [StateError] like [isModuleInstalled] when [account] has no code.
///
/// Example:
/// ```dart
/// final installedValidators = await getInstalledModulesOfType(
///   publicClient: publicClient,
///   account: myAccount,
///   moduleType: Erc7579ModuleType.validator,
///   candidateModules: [validator1, validator2, validator3],
/// );
///
/// print('Installed validators: $installedValidators');
/// ```
Future<List<EthereumAddress>> getInstalledModulesOfType({
  required PublicClient publicClient,
  required EthereumAddress account,
  required Erc7579ModuleType moduleType,
  required List<EthereumAddress> candidateModules,
}) async {
  final installed = <EthereumAddress>[];

  for (final module in candidateModules) {
    final isInstalled = await isModuleInstalled(
      publicClient: publicClient,
      account: account,
      moduleType: moduleType,
      module: module,
    );

    if (isInstalled) {
      installed.add(module);
    }
  }

  return installed;
}

/// `eth_call` to [account]; `0x` is an error, as with viem `readContract`
/// (`ContractFunctionZeroDataError`).
Future<String> _readAccount(
  PublicClient publicClient,
  EthereumAddress account,
  String callData,
  String function,
) async {
  final result = await publicClient.call(Call(to: account, data: callData));
  if (result.isEmpty || result == '0x') {
    throw StateError(
      '$function: eth_call to ${account.checksummed} returned no data; '
      'is the account deployed on this chain? For a counterfactual account '
      'use SmartAccountClient.$function, which retries through the factory.',
    );
  }
  return result;
}
