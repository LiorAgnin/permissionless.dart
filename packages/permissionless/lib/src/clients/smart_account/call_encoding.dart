import '../../types/user_operation.dart';
import 'smart_account_interface.dart';

/// Encodes [calls] as the call data of a UserOperation sent by [account];
/// [deploysAccount] is whether that operation also deploys the account
/// (see [DeploymentCallsEncoder]).
String encodeUserOperationCalls(
  SmartAccount account,
  List<Call> calls, {
  required bool deploysAccount,
}) =>
    deploysAccount && account is DeploymentCallsEncoder
        ? account.encodeCallsForDeployment(calls)
        : account.encodeCalls(calls);
