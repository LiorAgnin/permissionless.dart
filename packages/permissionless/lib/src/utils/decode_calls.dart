import 'dart:typed_data';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';
import 'encoding.dart';

/// Shared call-data decoders used by account [decodeCalls] implementations.
///
/// Mirrors the per-account decode helpers in permissionless.js
/// (`decodeCallData.ts` etc.).
class CallDataDecoder {
  CallDataDecoder._();

  /// Decodes `executeBatch((address,uint256,bytes)[])` (SimpleAccount v0.8 / Kernel v2 batch).
  static List<Call> decodeExecuteBatchTupleArray(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'executeBatch((address,uint256,bytes)[])',
      callData,
    );
    final tuples = args[0] as List;
    return [
      for (final raw in tuples)
        Call(
          to: (raw as List)[0] as EthereumAddress,
          value: raw[1] as BigInt,
          data: _bytesToHex(raw[2] as Uint8List),
        ),
    ];
  }

  /// Decodes Kernel v0.2.x `execute(address,uint256,bytes,uint8)`.
  static List<Call> decodeKernelV2Execute(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'execute(address,uint256,bytes,uint8)',
      callData,
    );
    return [
      Call(
        to: args[0] as EthereumAddress,
        value: args[1] as BigInt,
        data: _bytesToHex(args[2] as Uint8List),
      ),
    ];
  }

  static String _bytesToHex(Uint8List bytes) =>
      bytes.isEmpty ? '0x' : Hex.fromBytes(bytes);
}
