import 'dart:typed_data';

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import 'constants.dart';
import 'safe_abi.dart';

/// A call with an explicit operation type for MultiSend.
class MultiSendCall {
  /// Creates a MultiSend call.
  const MultiSendCall({
    required this.to,
    required this.value,
    required this.data,
    required this.operation,
  });

  /// Target address.
  final EthereumAddress to;

  /// ETH value in wei.
  final BigInt value;

  /// Encoded calldata.
  final String data;

  /// Operation type: call (0) or delegatecall (1).
  final OperationType operation;
}

/// Encodes multiple calls into a MultiSend transaction.
///
/// MultiSend allows batching multiple transactions into a single call.
/// Each transaction is packed as:
/// - operation (1 byte): 0 = Call, 1 = DelegateCall
/// - to (20 bytes): target address
/// - value (32 bytes): ETH value
/// - dataLength (32 bytes): length of call data
/// - data (variable): call data
///
/// Every call uses [defaultOperation].
String encodeMultiSend(
  List<Call> calls, {
  OperationType defaultOperation = OperationType.call,
}) =>
    _encodeMultiSend([
      for (final call in calls)
        MultiSendCall(
          to: call.to,
          value: call.value,
          data: call.data,
          operation: defaultOperation,
        ),
    ]);

/// Encodes multiple calls with explicit operation types into a MultiSend transaction.
///
/// This version allows each call to specify its own operation type (call vs delegatecall).
String encodeMultiSendWithOperations(List<MultiSendCall> calls) =>
    _encodeMultiSend(calls);

/// Throws an [ArgumentError] if [calls] is empty or a value does not fit in
/// uint256.
String _encodeMultiSend(List<MultiSendCall> calls) {
  if (calls.isEmpty) {
    throw ArgumentError('Cannot encode empty calls list');
  }
  final packed = <String>[];
  for (final call in calls) {
    final data = Hex.decode(call.data);
    packed.addAll([
      Hex.fromBigInt(BigInt.from(call.operation.value), byteLength: 1),
      call.to.hex,
      Hex.fromBigInt(call.value, byteLength: 32, name: 'value'),
      Hex.fromBigInt(BigInt.from(data.length), byteLength: 32),
      Hex.fromBytes(data),
    ]);
  }
  return AbiEncoder.encodeFunctionData(
    safeMultiSendSignature,
    [Hex.concat(packed)],
  );
}

/// Decodes a MultiSend transaction back into individual calls.
///
/// The selector is not checked, and each transaction's operation type is
/// dropped.
List<Call> decodeMultiSend(String multiSendData) {
  final fullData = Hex.decode(multiSendData);
  if (fullData.length < 68) {
    throw ArgumentError('Invalid MultiSend data');
  }
  // The bytes offset is relative to the end of the selector.
  final dataStart = 4 + _readWord(fullData, 4).toInt();
  final dataLength = _readWord(fullData, dataStart).toInt();
  return _unpackTransactions(
    fullData.sublist(dataStart + 32, dataStart + 32 + dataLength),
  );
}

List<Call> _unpackTransactions(Uint8List data) {
  final calls = <Call>[];
  var offset = 0;
  while (offset < data.length) {
    offset += 1;
    final to = EthereumAddress(data.sublist(offset, offset + 20));
    offset += 20;
    final value = _readWord(data, offset);
    offset += 32;
    final dataLength = _readWord(data, offset).toInt();
    offset += 32;
    final callData = data.sublist(offset, offset + dataLength);
    offset += dataLength;
    calls.add(Call(to: to, value: value, data: Hex.fromBytes(callData)));
  }
  return calls;
}

BigInt _readWord(Uint8List data, int offset) =>
    Hex.toBigInt(Hex.fromBytes(data.sublist(offset, offset + 32)));
