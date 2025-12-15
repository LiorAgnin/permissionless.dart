/// Dart implementation of permissionless.js for ERC-4337 smart accounts.
///
/// This library provides tools for creating and managing ERC-4337 smart
/// accounts, starting with Safe account support.
///
/// Example:
/// ```dart
/// import 'package:permissionless/permissionless.dart';
///
/// void main() async {
///   final owner = PrivateKeyOwner('0x...');
///   final account = createSafeSmartAccount(
///     owners: [owner],
///     chainId: BigInt.from(1),
///   );
///
///   final address = await account.getAddress();
///   print('Safe address: $address');
/// }
/// ```
library;

// Accounts
export 'src/accounts/account_owner.dart';
export 'src/accounts/biconomy/biconomy.dart';
export 'src/accounts/etherspot/etherspot.dart';
export 'src/accounts/kernel/kernel.dart';
export 'src/accounts/light/light.dart';
export 'src/accounts/nexus/nexus.dart';
export 'src/accounts/safe/safe.dart';
export 'src/accounts/simple/simple.dart';
export 'src/accounts/thirdweb/thirdweb.dart';
export 'src/accounts/trust/trust.dart';
// Actions
export 'src/actions/erc7579/erc7579.dart';
export 'src/actions/smart_account/smart_account.dart';
// Clients
export 'src/clients/bundler/bundler.dart';
export 'src/clients/etherspot/etherspot.dart';
export 'src/clients/paymaster/paymaster.dart';
export 'src/clients/pimlico/pimlico.dart';
export 'src/clients/public/public.dart';
export 'src/clients/smart_account/smart_account.dart';
// Constants
export 'src/constants/entry_point.dart';
// Experimental (API may change)
export 'src/experimental/experimental.dart';
// Types
export 'src/types/address.dart';
export 'src/types/calls_status.dart';
export 'src/types/eip7702.dart';
export 'src/types/hex.dart';
export 'src/types/typed_data.dart';
export 'src/types/user_operation.dart';
// Utilities
export 'src/utils/encoding.dart';
export 'src/utils/erc20.dart';
export 'src/utils/erc20_paymaster.dart';
export 'src/utils/erc7579.dart';
export 'src/utils/gas.dart';
export 'src/utils/message_hash.dart';
export 'src/utils/multisend.dart';
export 'src/utils/packed_user_operation.dart';
export 'src/utils/units.dart';
