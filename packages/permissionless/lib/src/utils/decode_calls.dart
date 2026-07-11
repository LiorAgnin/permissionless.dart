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

  /// Decodes `execute(address,uint256,bytes)` into a single-element list.
  static List<Call> decodeExecute(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'execute(address,uint256,bytes)',
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

  /// Decodes `executeBatch(address[],uint256[],bytes[])` (v0.7 / Light / Thirdweb / Trust).
  static List<Call> decodeExecuteBatchWithValues(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'executeBatch(address[],uint256[],bytes[])',
      callData,
    );
    final destinations = (args[0] as List).cast<EthereumAddress>();
    final values = (args[1] as List).cast<BigInt>();
    final datas = (args[2] as List).cast<Uint8List>();
    return [
      for (var i = 0; i < destinations.length; i++)
        Call(
          to: destinations[i],
          value: values[i],
          data: _bytesToHex(datas[i]),
        ),
    ];
  }

  /// Decodes `executeBatch(address[],bytes[])` (SimpleAccount v0.6).
  static List<Call> decodeExecuteBatchV06(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'executeBatch(address[],bytes[])',
      callData,
    );
    final destinations = (args[0] as List).cast<EthereumAddress>();
    final datas = (args[1] as List).cast<Uint8List>();
    return [
      for (var i = 0; i < destinations.length; i++)
        Call(
          to: destinations[i],
          value: BigInt.zero,
          data: _bytesToHex(datas[i]),
        ),
    ];
  }

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

  /// Decodes Biconomy `execute_ncC(address,uint256,bytes)`.
  static List<Call> decodeBiconomyExecute(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'execute_ncC(address,uint256,bytes)',
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

  /// Decodes Biconomy `executeBatch_y6U(address[],uint256[],bytes[])`.
  static List<Call> decodeBiconomyExecuteBatch(String callData) {
    final args = AbiEncoder.decodeFunctionData(
      'executeBatch_y6U(address[],uint256[],bytes[])',
      callData,
    );
    final destinations = (args[0] as List).cast<EthereumAddress>();
    final values = (args[1] as List).cast<BigInt>();
    final datas = (args[2] as List).cast<Uint8List>();
    return [
      for (var i = 0; i < destinations.length; i++)
        Call(
          to: destinations[i],
          value: values[i],
          data: _bytesToHex(datas[i]),
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

  /// Tries batch then single `execute` for accounts that share the standard
  /// Simple/Light/Thirdweb/Trust ABI shape.
  ///
  /// When [entryPointVersion] is set, uses the version-specific batch decoder
  /// for SimpleAccount. When null, uses the v0.7 three-array batch form.
  static List<Call> decodeStandardExecute({
    required String callData,
    EntryPointVersion? entryPointVersion,
  }) {
    final selector = _selector(callData);

    if (entryPointVersion == EntryPointVersion.v08) {
      if (selector == SimpleBatchSelectors.executeBatchV08) {
        return decodeExecuteBatchTupleArray(callData);
      }
    } else if (entryPointVersion == EntryPointVersion.v06) {
      if (selector == SimpleBatchSelectors.executeBatchV06) {
        return decodeExecuteBatchV06(callData);
      }
    } else {
      // v0.7 or unspecified three-array batch
      if (selector == SimpleBatchSelectors.executeBatchV07) {
        return decodeExecuteBatchWithValues(callData);
      }
    }

    // Single execute is shared across versions
    if (selector == SimpleBatchSelectors.execute) {
      return decodeExecute(callData);
    }

    // Fallback: try batch forms then single (JS try/catch style)
    try {
      if (entryPointVersion == EntryPointVersion.v08) {
        return decodeExecuteBatchTupleArray(callData);
      }
      if (entryPointVersion == EntryPointVersion.v06) {
        return decodeExecuteBatchV06(callData);
      }
      return decodeExecuteBatchWithValues(callData);
    } catch (_) {
      return decodeExecute(callData);
    }
  }

  static String _selector(String callData) {
    final hex = Hex.strip0x(callData);
    if (hex.length < 8) {
      throw ArgumentError('Call data too short');
    }
    return '0x${hex.substring(0, 8).toLowerCase()}';
  }

  static String _bytesToHex(Uint8List bytes) =>
      bytes.isEmpty ? '0x' : Hex.fromBytes(bytes);
}

/// Selectors shared by Simple / Light / Thirdweb / Trust execute ABIs.
class SimpleBatchSelectors {
  SimpleBatchSelectors._();

  static const String execute = '0xb61d27f6';
  static const String executeBatchV06 = '0x18dfb3c7';
  static const String executeBatchV07 = '0x47e1da2a';
  static const String executeBatchV08 = '0x34fcd5be';
}
