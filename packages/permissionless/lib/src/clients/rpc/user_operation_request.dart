import '../../types/eip7702.dart';
import '../../types/user_operation.dart';

/// Builds the JSON-RPC `userOperation` param for bundler and paymaster
/// requests, adding [authorization] (when given) as `eip7702Auth`, a single
/// object per the Pimlico API and viem.
///
/// Package-internal: not exported from any barrel.
Map<String, dynamic> userOperationRequestJson(
  UserOperation userOp, {
  Eip7702Authorization? authorization,
}) =>
    {
      ...userOp.toJson(),
      if (authorization != null) 'eip7702Auth': authorization.toRpcFormat(),
    };
