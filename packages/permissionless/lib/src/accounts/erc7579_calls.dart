import '../types/user_operation.dart';
import '../utils/erc7579.dart';

/// Call data for ERC-7579 accounts (Kernel v0.3.x, Nexus, Etherspot): one
/// call in call mode, several in batch mode, as the permissionless.js
/// accounts branch on `calls.length`.
String encodeErc7579AccountCalls(List<Call> calls) {
  if (calls.isEmpty) {
    throw ArgumentError('At least one call is required');
  }
  if (calls.length == 1) return encode7579Execute(calls.single);
  return encode7579ExecuteBatch(calls);
}
