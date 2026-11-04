import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/user_operation.dart';

/// Builds the JSON-RPC `userOperation` param for an EIP-7702-aware request.
///
/// Adds [authorization] (when given) as `eip7702Auth`, a single object per the
/// Pimlico API, and shortens the padded EIP-7702 factory marker to `0x7702`,
/// which is what bundlers expect.
///
/// Package-internal: not exported from the bundler barrel.
Map<String, dynamic> userOperationRequestJson(
  UserOperation userOp, {
  Eip7702Authorization? authorization,
}) {
  final json = userOp.toJson();
  if (authorization != null) {
    json['eip7702Auth'] = authorization.toRpcFormat();
  }
  final factory = json['factory'] as String?;
  if (factory != null &&
      factory.toLowerCase() == eip7702FactoryMarkerAddress.hex.toLowerCase()) {
    json['factory'] = eip7702FactoryMarkerShort;
  }
  return json;
}
