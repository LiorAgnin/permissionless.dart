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
  required EthAddress account,
  required Erc7579ModuleType moduleType,
  required EthAddress module,
  String additionalContext = '0x',
}) async {
  final callData = encode7579IsModuleInstalled(
    moduleType: moduleType,
    module: module,
    additionalContext: additionalContext,
  );

  final result = await publicClient.call(Call(to: account, data: callData));
  return decode7579BoolResult(result);
}

/// Checks if an ERC-7579 account supports a particular module type.
///
/// Queries the account using `supportsModule(uint256)`.
///
/// Use this before attempting to install a module to ensure the
/// account implementation supports that module type.
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
  required EthAddress account,
  required Erc7579ModuleType moduleType,
}) async {
  final callData = encode7579SupportsModule(moduleType);
  final result = await publicClient.call(Call(to: account, data: callData));
  return decode7579BoolResult(result);
}

/// Gets the account identifier from an ERC-7579 account.
///
/// Queries the account using `accountId()` which returns a string
/// in the format "vendorname.accountname.semver".
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
  required EthAddress account,
}) async {
  final callData = encode7579AccountId();
  final result = await publicClient.call(Call(to: account, data: callData));
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
Future<List<EthAddress>> getInstalledModulesOfType({
  required PublicClient publicClient,
  required EthAddress account,
  required Erc7579ModuleType moduleType,
  required List<EthAddress> candidateModules,
}) async {
  final installed = <EthAddress>[];

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
