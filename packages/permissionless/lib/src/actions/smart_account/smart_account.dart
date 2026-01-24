/// Smart Account Actions for ERC-4337 smart accounts.
///
/// This module provides extension methods on [SmartAccountClient] for
/// common operations like message signing, transactions, and contract writes.
///
/// Usage:
/// ```dart
/// import 'package:permissionless/permissionless.dart';
///
/// // The extension methods are automatically available on SmartAccountClient
/// final signature = await client.signMessage('Hello');
/// final txHash = await client.sendTransaction(to: address, value: amount, ...);
/// ```
library;

export 'smart_account_actions.dart';
