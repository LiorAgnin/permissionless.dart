import 'dart:typed_data';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';
import '../utils/encoding.dart';

/// `execute(address,uint256,bytes)`, the single-call entry point shared by
/// SimpleAccount, LightAccount, Thirdweb and Trust (Barz).
const String executeSignature = 'execute(address,uint256,bytes)';

/// The `executeBatch` ABI shapes used by SimpleAccount-style accounts.
enum ExecuteBatchAbi {
  /// `executeBatch(address[],bytes[])`: SimpleAccount v0.6, which has no
  /// per-call value.
  addressesAndBytes('executeBatch(address[],bytes[])'),

  /// `executeBatch(address[],uint256[],bytes[])`: SimpleAccount v0.7,
  /// LightAccount, Thirdweb, Trust.
  addressesValuesAndBytes('executeBatch(address[],uint256[],bytes[])'),

  /// `executeBatch((address,uint256,bytes)[])`: SimpleAccount v0.8 and
  /// Simple7702.
  callTuples('executeBatch((address,uint256,bytes)[])');

  const ExecuteBatchAbi(this.signature);

  /// The Solidity function signature.
  final String signature;
}

/// Encodes [call] as `execute(to, value, data)`.
String encodeExecute(Call call) => AbiEncoder.encodeFunctionData(
      executeSignature,
      [call.to, call.value, call.data],
    );

/// Encodes [calls] as one `executeBatch` call in the [batch] shape.
String encodeExecuteBatch(List<Call> calls, ExecuteBatchAbi batch) =>
    AbiEncoder.encodeFunctionData(
      batch.signature,
      switch (batch) {
        ExecuteBatchAbi.addressesAndBytes => [
            [for (final c in calls) c.to],
            [for (final c in calls) c.data],
          ],
        ExecuteBatchAbi.addressesValuesAndBytes => [
            [for (final c in calls) c.to],
            [for (final c in calls) c.value],
            [for (final c in calls) c.data],
          ],
        ExecuteBatchAbi.callTuples => [
            [
              for (final c in calls) [c.to, c.value, c.data],
            ],
          ],
      },
    );

/// Encodes [calls] the way these accounts expect: one call as `execute`,
/// several as `executeBatch` in the [batch] shape.
String encodeExecuteCalls(List<Call> calls, ExecuteBatchAbi batch) {
  if (calls.isEmpty) {
    throw ArgumentError('At least one call is required');
  }
  if (calls.length == 1) return encodeExecute(calls.single);
  return encodeExecuteBatch(calls, batch);
}

/// Decodes call data produced by [encodeExecuteCalls] with the same [batch].
List<Call> decodeExecuteCalls(String callData, ExecuteBatchAbi batch) {
  final selector = Hex.slice(callData, 0, 4).toLowerCase();
  if (selector == AbiEncoder.functionSelector(executeSignature)) {
    final args = AbiEncoder.decodeFunctionData(executeSignature, callData);
    return [_call(args[0], args[1], args[2])];
  }
  final args = AbiEncoder.decodeFunctionData(batch.signature, callData);
  return switch (batch) {
    ExecuteBatchAbi.addressesAndBytes => [
        for (var i = 0; i < (args[0] as List).length; i++)
          _call((args[0] as List)[i], BigInt.zero, (args[1] as List)[i]),
      ],
    ExecuteBatchAbi.addressesValuesAndBytes => [
        for (var i = 0; i < (args[0] as List).length; i++)
          _call(
            (args[0] as List)[i],
            (args[1] as List)[i],
            (args[2] as List)[i],
          ),
      ],
    ExecuteBatchAbi.callTuples => [
        for (final t in (args[0] as List).cast<List<dynamic>>())
          _call(t[0], t[1], t[2]),
      ],
  };
}

Call _call(dynamic to, dynamic value, dynamic data) => Call(
      to: to as EthereumAddress,
      value: value as BigInt,
      data: Hex.fromBytes(data as Uint8List),
    );
