import '../../clients/bundler/types.dart';
import '../../clients/smart_account/smart_account_client.dart';
import '../../types/address.dart';
import '../../types/calls_status.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';

/// Extension methods for SmartAccountClient providing high-level actions.
///
/// These actions mirror the TypeScript permissionless.js API:
/// - `signMessage` - EIP-191 personal message signing
/// - `signTypedData` - EIP-712 typed data signing
/// - `sendTransaction` - Send a single transaction and wait for tx hash
/// - `writeContract` - Encode and send a contract call
/// - `sendCalls` - ERC-5792 batch calls (returns immediately)
/// - `getCallsStatus` - ERC-5792 status check
///
/// Example:
/// ```dart
/// // Sign a message
/// final signature = await client.signMessage('Hello, World!');
///
/// // Send a transaction
/// final txHash = await client.sendTransaction(
///   to: recipient,
///   value: parseEther('1'),
///   maxFeePerGas: gasPrices.fast.maxFeePerGas,
///   maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
/// );
/// ```
extension SmartAccountActions on SmartAccountClient {
  /// Signs a personal message (EIP-191).
  ///
  /// The message is hashed using the Ethereum personal message format:
  /// `keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)`
  ///
  /// Returns the signature as a hex string.
  Future<String> signMessage(String message) => account.signMessage(message);

  /// Signs EIP-712 typed data.
  ///
  /// The typed data is hashed using the EIP-712 format:
  /// `keccak256("\x19\x01" + domainSeparator + hashStruct(message))`
  ///
  /// Returns the signature as a hex string.
  Future<String> signTypedData(TypedData typedData) =>
      account.signTypedData(typedData);

  /// Sends a transaction and waits for the on-chain transaction hash.
  ///
  /// Unlike [sendUserOperation], this method waits for the UserOperation
  /// to be included on-chain and returns the actual transaction hash
  /// (not the UserOperation hash).
  ///
  /// Parameters:
  /// - [to] - The destination address
  /// - [value] - The amount of ETH to send (defaults to 0)
  /// - [data] - The calldata (defaults to '0x')
  /// - [maxFeePerGas] - Maximum fee per gas
  /// - [maxPriorityFeePerGas] - Maximum priority fee per gas
  /// - [nonce] - Optional nonce override
  /// - [timeout] - How long to wait for confirmation (default 60s)
  ///
  /// Example:
  /// ```dart
  /// final txHash = await client.sendTransaction(
  ///   to: EthAddress('0x...'),
  ///   value: BigInt.from(1000000000000000000), // 1 ETH
  ///   maxFeePerGas: BigInt.from(30000000000),
  ///   maxPriorityFeePerGas: BigInt.from(1000000000),
  /// );
  /// print('Transaction: $txHash');
  /// ```
  Future<String> sendTransaction({
    required EthAddress to,
    BigInt? value,
    String data = '0x',
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final hash = await sendUserOperation(
      calls: [Call(to: to, value: value, data: data)],
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );

    final receipt = await waitForReceipt(hash, timeout: timeout);

    // Return the on-chain transaction hash if available
    return receipt?.receipt?.transactionHash ?? hash;
  }

  /// Sends a contract write call.
  ///
  /// Encodes the function call using the provided signature and arguments,
  /// then sends it as a transaction.
  ///
  /// Parameters:
  /// - [address] - The contract address
  /// - [functionSignature] - The function signature (e.g., 'transfer(address,uint256)')
  /// - [args] - The function arguments (must match signature order)
  /// - [value] - ETH value to send (defaults to 0)
  /// - [maxFeePerGas] - Maximum fee per gas
  /// - [maxPriorityFeePerGas] - Maximum priority fee per gas
  /// - [nonce] - Optional nonce override
  ///
  /// Example:
  /// ```dart
  /// // ERC-20 transfer
  /// final txHash = await client.writeContract(
  ///   address: tokenAddress,
  ///   functionSignature: 'transfer(address,uint256)',
  ///   args: [recipient, amount],
  ///   maxFeePerGas: gasPrices.fast.maxFeePerGas,
  ///   maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
  /// );
  /// ```
  Future<String> writeContract({
    required EthAddress address,
    required String functionSignature,
    List<dynamic> args = const [],
    BigInt? value,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final callData = _encodeFunction(functionSignature, args);

    return sendTransaction(
      to: address,
      data: callData,
      value: value,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
      timeout: timeout,
    );
  }

  /// Sends multiple calls as a batch (ERC-5792).
  ///
  /// Unlike [sendTransaction], this method returns immediately with the
  /// UserOperation hash (call ID) without waiting for confirmation.
  /// Use [getCallsStatus] to check the status later.
  ///
  /// Parameters:
  /// - [calls] - List of calls to execute atomically
  /// - [maxFeePerGas] - Maximum fee per gas
  /// - [maxPriorityFeePerGas] - Maximum priority fee per gas
  /// - [nonce] - Optional nonce override
  ///
  /// Returns the call ID (UserOperation hash) for status tracking.
  ///
  /// Example:
  /// ```dart
  /// final callId = await client.sendCalls(
  ///   calls: [
  ///     Call(to: address1, value: amount1),
  ///     Call(to: address2, data: callData2),
  ///   ],
  ///   maxFeePerGas: gasPrices.fast.maxFeePerGas,
  ///   maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
  /// );
  ///
  /// // Check status later
  /// final status = await client.getCallsStatus(callId);
  /// ```
  Future<String> sendCalls({
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
  }) =>
      sendUserOperation(
        calls: calls,
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        nonce: nonce,
      );

  /// Gets the status of a sendCalls operation (ERC-5792).
  ///
  /// Returns the current status of a batch call operation:
  /// - [CallsStatusType.pending] - Still being processed (status code 100)
  /// - [CallsStatusType.success] - Completed successfully (status code 200)
  /// - [CallsStatusType.failure] - Failed (status code 500)
  ///
  /// Example:
  /// ```dart
  /// final callId = await client.sendCalls(...);
  ///
  /// // Poll for status
  /// while (true) {
  ///   final status = await client.getCallsStatus(callId);
  ///   if (status.status == CallsStatusType.success) {
  ///     print('Success! Tx: ${status.receipts?.first.transactionHash}');
  ///     break;
  ///   } else if (status.status == CallsStatusType.failure) {
  ///     print('Failed!');
  ///     break;
  ///   }
  ///   await Future.delayed(Duration(seconds: 2));
  /// }
  /// ```
  Future<CallsStatus> getCallsStatus(String id) async {
    try {
      final receipt = await bundler.getUserOperationReceipt(id);
      if (receipt != null) {
        return CallsStatus(
          id: id,
          version: '1.0',
          chainId: account.chainId,
          status: receipt.success
              ? CallsStatusType.success
              : CallsStatusType.failure,
          statusCode: receipt.success ? 200 : 500,
          atomic: true,
          receipts: receipt.receipt != null
              ? [_toCallReceipt(receipt.receipt!)]
              : null,
        );
      }
    } catch (_) {
      // Receipt not found - operation is still pending
    }

    // Default to pending status
    return CallsStatus(
      id: id,
      version: '1.0',
      chainId: account.chainId,
      status: CallsStatusType.pending,
      statusCode: 100,
      atomic: true,
    );
  }

  /// Converts a TransactionReceipt to CallReceipt.
  CallReceipt _toCallReceipt(TransactionReceipt receipt) => CallReceipt(
        status: receipt.status == 1 ? 'success' : 'reverted',
        logs: receipt.logs
            .map(
              (log) => {
                'address': log.address.hex,
                'topics': log.topics,
                'data': log.data,
              },
            )
            .toList(),
        blockHash: receipt.blockHash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed,
        transactionHash: receipt.transactionHash,
      );

  /// Encodes a function call with the given signature and arguments.
  ///
  /// This is a simplified encoder that supports basic types:
  /// - address
  /// - uint256, uint128, uint48, etc.
  /// - bool
  /// - bytes, bytes32
  String _encodeFunction(String signature, List<dynamic> args) {
    final selector = AbiEncoder.functionSelector(signature);

    if (args.isEmpty) {
      return selector;
    }

    // Parse argument types from signature
    final paramsStart = signature.indexOf('(');
    final paramsEnd = signature.lastIndexOf(')');
    if (paramsStart == -1 || paramsEnd == -1) {
      throw ArgumentError('Invalid function signature: $signature');
    }

    final paramsStr = signature.substring(paramsStart + 1, paramsEnd);
    final types = paramsStr.isEmpty ? <String>[] : paramsStr.split(',');

    if (types.length != args.length) {
      throw ArgumentError(
        'Argument count mismatch: expected ${types.length}, got ${args.length}',
      );
    }

    // Encode each argument
    final encodedParams = <String>[];
    for (var i = 0; i < args.length; i++) {
      final type = types[i].trim();
      final value = args[i];
      encodedParams.add(_encodeArg(type, value));
    }

    return AbiEncoder.encodeFunctionCall(selector, encodedParams);
  }

  /// Encodes a single argument based on its Solidity type.
  String _encodeArg(String type, dynamic value) {
    if (type == 'address') {
      if (value is EthAddress) {
        return AbiEncoder.encodeAddress(value);
      }
      return AbiEncoder.encodeAddress(EthAddress(value.toString()));
    }

    if (type.startsWith('uint')) {
      BigInt bigValue;
      if (value is BigInt) {
        bigValue = value;
      } else if (value is int) {
        bigValue = BigInt.from(value);
      } else {
        bigValue = BigInt.parse(value.toString());
      }
      return AbiEncoder.encodeUint256(bigValue);
    }

    if (type == 'bool') {
      return AbiEncoder.encodeBool(value: value as bool);
    }

    if (type == 'bytes32') {
      return AbiEncoder.encodeBytes32(value.toString());
    }

    if (type == 'bytes') {
      return AbiEncoder.encodeBytes(value.toString());
    }

    throw ArgumentError('Unsupported argument type: $type');
  }
}
