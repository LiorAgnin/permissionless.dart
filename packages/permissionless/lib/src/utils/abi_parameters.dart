import '../types/hex.dart';
import 'encoding.dart';

// `abi.encode(params)` is the argument block of any function taking those
// params, so these reuse AbiEncoder's function codec under a placeholder name.
const String _placeholder = 'parameters';

/// `abi.encode` of [args] typed by the comma-separated Solidity [types]
/// (viem `encodeAbiParameters`), e.g. `'address,bytes'`.
String encodeAbiParameters(String types, List<dynamic> args) => Hex.slice(
      AbiEncoder.encodeFunctionData('$_placeholder($types)', args),
      4,
    );

/// Inverse of [encodeAbiParameters] (viem `decodeAbiParameters`).
List<dynamic> decodeAbiParameters(String types, String data) {
  final signature = '$_placeholder($types)';
  return AbiEncoder.decodeFunctionData(
    signature,
    Hex.concat([AbiEncoder.functionSelector(signature), data]),
  );
}
