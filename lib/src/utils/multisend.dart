import 'dart:typed_data';

import '../accounts/safe/constants.dart';
import '../types/address.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';
import 'encoding.dart';

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
  final EthAddress to;

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
String encodeMultiSend(
  List<Call> calls, {
  OperationType defaultOperation = OperationType.call,
}) {
  if (calls.isEmpty) {
    throw ArgumentError('Cannot encode empty calls list');
  }

  final buffer = <int>[];

  for (final call in calls) {
    // Compute values first
    final valueBytes = _bigIntToBytes32(call.value);
    final dataBytes = Hex.decode(call.data);
    final lengthBytes = _bigIntToBytes32(BigInt.from(dataBytes.length));

    // Pack transaction: operation (1) + to (20) + value (32) + dataLength (32) + data
    buffer
      ..add(defaultOperation.value)
      ..addAll(call.to.bytes)
      ..addAll(valueBytes)
      ..addAll(lengthBytes)
      ..addAll(dataBytes);
  }

  final packedTransactions = Hex.fromBytes(Uint8List.fromList(buffer));

  // Encode as multiSend(bytes) call
  const dataOffset = 32; // Single parameter offset
  final encodedTransactions = AbiEncoder.encodeBytes(packedTransactions);

  return Hex.concat([
    SafeSelectors.multiSend,
    AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
    Hex.strip0x(encodedTransactions),
  ]);
}

/// Encodes multiple calls with explicit operation types into a MultiSend transaction.
///
/// This version allows each call to specify its own operation type (call vs delegatecall).
String encodeMultiSendWithOperations(List<MultiSendCall> calls) {
  if (calls.isEmpty) {
    throw ArgumentError('Cannot encode empty calls list');
  }

  final buffer = <int>[];

  for (final call in calls) {
    // Compute values first
    final valueBytes = _bigIntToBytes32(call.value);
    final dataBytes = Hex.decode(call.data);
    final lengthBytes = _bigIntToBytes32(BigInt.from(dataBytes.length));

    // Pack transaction: operation (1) + to (20) + value (32) + dataLength (32) + data
    buffer
      ..add(call.operation.value)
      ..addAll(call.to.bytes)
      ..addAll(valueBytes)
      ..addAll(lengthBytes)
      ..addAll(dataBytes);
  }

  final packedTransactions = Hex.fromBytes(Uint8List.fromList(buffer));

  // Encode as multiSend(bytes) call
  const dataOffset = 32; // Single parameter offset
  final encodedTransactions = AbiEncoder.encodeBytes(packedTransactions);

  return Hex.concat([
    SafeSelectors.multiSend,
    AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
    Hex.strip0x(encodedTransactions),
  ]);
}

/// Decodes a MultiSend transaction back into individual calls.
List<Call> decodeMultiSend(String multiSendData) {
  // Skip function selector (4 bytes) and offset (32 bytes)
  // Then read length (32 bytes) and data
  final fullData = Hex.decode(multiSendData);

  if (fullData.length < 68) {
    throw ArgumentError('Invalid MultiSend data');
  }

  // Read offset (bytes 4-36)
  final offsetBytes = fullData.sublist(4, 36);
  final offset = _bytes32ToBigInt(Uint8List.fromList(offsetBytes)).toInt();

  // Read length at offset position (relative to after selector)
  final dataStart = 4 + offset;
  final lengthBytes = fullData.sublist(dataStart, dataStart + 32);
  final dataLength = _bytes32ToBigInt(Uint8List.fromList(lengthBytes)).toInt();

  // Read packed transactions
  final transactionsData =
      fullData.sublist(dataStart + 32, dataStart + 32 + dataLength);

  return _unpackTransactions(Uint8List.fromList(transactionsData));
}

List<Call> _unpackTransactions(Uint8List data) {
  final calls = <Call>[];
  var offset = 0;

  while (offset < data.length) {
    // Operation (1 byte) - we skip it for now, just extracting calls
    offset += 1;

    // To address (20 bytes)
    final toBytes = data.sublist(offset, offset + 20);
    final to = EthAddress(Hex.fromBytes(Uint8List.fromList(toBytes)));
    offset += 20;

    // Value (32 bytes)
    final valueBytes = data.sublist(offset, offset + 32);
    final value = _bytes32ToBigInt(Uint8List.fromList(valueBytes));
    offset += 32;

    // Data length (32 bytes)
    final lengthBytes = data.sublist(offset, offset + 32);
    final dataLength =
        _bytes32ToBigInt(Uint8List.fromList(lengthBytes)).toInt();
    offset += 32;

    // Data
    final callData = data.sublist(offset, offset + dataLength);
    offset += dataLength;

    calls.add(
      Call(
        to: to,
        value: value,
        data: callData.isEmpty
            ? '0x'
            : Hex.fromBytes(Uint8List.fromList(callData)),
      ),
    );
  }

  return calls;
}

Uint8List _bigIntToBytes32(BigInt value) {
  final bytes = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0; i--) {
    bytes[i] = (v & BigInt.from(0xFF)).toInt();
    v = v >> 8;
  }
  return bytes;
}

BigInt _bytes32ToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}
