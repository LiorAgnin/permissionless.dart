import 'dart:typed_data';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';
import 'encoding.dart';
import 'erc7579.dart';
import 'multisend.dart';

/// Shared call-data decoders used by account [decodeCalls] implementations.
///
/// Mirrors the per-account decode helpers in permissionless.js
/// (`decodeCallData.ts`, `decode7579Calls`, Safe MultiSend unpack, etc.).
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

  /// Decodes Safe `executeUserOpWithErrorString(address,uint256,bytes,uint8)`.
  ///
  /// When [to] is a MultiSend contract (checked against [multiSendAddresses]),
  /// unpacks the MultiSend payload into individual calls.
  static List<Call> decodeSafeExecuteUserOp(
    String callData, {
    required Set<String> multiSendAddresses,
  }) {
    final args = AbiEncoder.decodeFunctionData(
      'executeUserOpWithErrorString(address,uint256,bytes,uint8)',
      callData,
    );
    final to = args[0] as EthereumAddress;
    final value = args[1] as BigInt;
    final data = _bytesToHex(args[2] as Uint8List);

    final toLower = to.hex.toLowerCase();
    if (multiSendAddresses.contains(toLower)) {
      return decodeMultiSend(data);
    }

    return [Call(to: to, value: value, data: data)];
  }

  /// Decodes Safe ERC-7579 `setupSafe` and returns the nested user callData
  /// decoded via [decode7579Calls].
  static List<Call> decodeSafeSetupSafe(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'setupSafe((address,address[],uint256,address,bytes,address,(address,bytes)[],bytes))',
      callData,
    );
    final initData = args[0] as List;
    // Last field of InitData is the embedded ERC-7579 callData.
    final nested = _bytesToHex(initData.last as Uint8List);
    return decode7579Calls(nested).calls;
  }

  static String _bytesToHex(Uint8List bytes) =>
      bytes.isEmpty ? '0x' : Hex.fromBytes(bytes);
}
