import 'dart:async';

import '../../clients/bundler/types.dart';
import '../../clients/bundler/user_operation_request.dart';
import '../../clients/paymaster/types.dart';
import '../../clients/smart_account/smart_account_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../errors/errors.dart';
import '../../types/address.dart';
import '../../types/user_operation.dart';
import '../../utils/erc20.dart';
import '../../utils/user_operation_hash.dart';

/// What happened when [PimlicoActions.sendUserOperationSync] failed.
enum SendUserOperationSyncErrorKind {
  /// Rejected before sending (invalid fields, gas limits, simulation).
  /// Nothing was sent.
  rejected('rejected'),

  /// The bundle landed but reverted, so it didn't execute the user operation.
  /// Another bundler may have included it first: check
  /// `getUserOperationReceipt` before resending.
  bundleReverted('bundle_reverted'),

  /// May have been sent, but no receipt before the timeout. Keep polling
  /// `getUserOperationReceipt` instead of resending.
  pending('pending'),

  /// The bundler couldn't send the bundle and no receipt showed up before
  /// the timeout.
  notFound('not_found');

  const SendUserOperationSyncErrorKind(this.value);

  /// The permissionless.js wire name (e.g. `bundle_reverted`).
  final String value;

  String get _defaultMessage => switch (this) {
        rejected => 'User operation was rejected by the bundler.',
        bundleReverted => 'Bundle transaction reverted onchain. '
            'The user operation was not executed.',
        pending => 'User operation may have been sent but is not included '
            'yet. Poll `getUserOperationReceipt` instead of resending.',
        notFound => "Bundler couldn't send the user operation and no receipt "
            'was found.',
      };
}

/// Thrown by [PimlicoActions.sendUserOperationSync] when it can't return a
/// receipt. Mirrors permissionless.js `SendUserOperationSyncError`.
class SendUserOperationSyncError extends PermissionlessException {
  /// Creates the error. An empty or null [message] falls back to the
  /// default message for [kind].
  SendUserOperationSyncError({
    required this.kind,
    required this.userOperationHash,
    String? message,
    Object? cause,
  }) : super(
          (message == null || message.isEmpty) ? kind._defaultMessage : message,
          cause,
        );

  /// What happened.
  final SendUserOperationSyncErrorKind kind;

  /// Hash of the user operation that was (or may have been) sent.
  final String userOperationHash;

  /// Whether sending the same user operation again is safe.
  bool get canResend =>
      kind == SendUserOperationSyncErrorKind.bundleReverted ||
      kind == SendUserOperationSyncErrorKind.notFound;

  @override
  String toString() => 'SendUserOperationSyncError(${kind.value}): $message\n'
      'User operation hash: $userOperationHash'
      '${cause != null ? '\nCause: $cause' : ''}';
}

/// Pimlico-specific actions on a [SmartAccountClient].
///
/// Mirrors the smart-account half of permissionless.js `pimlicoActions`.
extension PimlicoActions on SmartAccountClient {
  /// Sends a user operation in its own bundle via
  /// `pimlico_sendUserOperationNow` and returns its receipt, without waiting
  /// for the mempool.
  ///
  /// Prepares and signs like [SmartAccountClient.sendUserOperation]
  /// (including EIP-7702 authorization). Never resends on its own. Sending
  /// and any receipt polling must finish within [timeout] (default: the
  /// bundler RPC client's timeout), which starts after prepare and sign.
  /// Otherwise it throws a [SendUserOperationSyncError] whose `kind` says
  /// what happened and whose `canResend` says whether sending the same user
  /// operation again is safe.
  ///
  /// A receipt with `success == false` (the call reverted) is returned, not
  /// thrown.
  ///
  /// Supports EntryPoint v0.7 and v0.8. The bundler must serve
  /// `pimlico_sendUserOperationNow` (Pimlico; Alto with
  /// `--enable-instant-bundling-endpoint`).
  ///
  /// Docs: https://docs.pimlico.io/references/bundler/endpoints/pimlico_sendUserOperationNow
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   final receipt = await client.sendUserOperationSync(
  ///     calls: [Call(to: recipient, value: BigInt.zero)],
  ///   );
  ///   print(receipt.receipt?.transactionHash);
  /// } on SendUserOperationSyncError catch (e) {
  ///   if (e.canResend) { /* safe to retry */ }
  /// }
  /// ```
  Future<UserOperationReceipt> sendUserOperationSync({
    List<Call>? calls,
    String? callData,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
    BigInt? callGasLimit,
    BigInt? verificationGasLimit,
    BigInt? preVerificationGas,
    String? signature,
    EthereumAddress? factory,
    String? factoryData,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
    EthereumAddress? entryPointAddress,
    Duration? timeout,
    Duration pollingInterval = const Duration(seconds: 2),
  }) async {
    final entryPointVersion = entryPointVersionOf(account.entryPoint);
    if (entryPointVersion != EntryPointVersion.v07 &&
        entryPointVersion != EntryPointVersion.v08) {
      throw UnsupportedError(
        'sendUserOperationSync supports EntryPoint v0.7 and v0.8; the '
        'account uses ${account.entryPoint.hex}.',
      );
    }
    final entryPoint = entryPointAddress ?? account.entryPoint;

    final prepared = await prepareUserOperationWithAuth(
      calls: calls,
      callData: callData,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
      callGasLimit: callGasLimit,
      verificationGasLimit: verificationGasLimit,
      preVerificationGas: preVerificationGas,
      signature: signature,
      factory: factory,
      factoryData: factoryData,
      paymasterContext: paymasterContext,
      sender: sender,
      stateOverride: stateOverride,
    );
    final userOp = signature != null
        ? prepared.userOp
        : await signUserOperation(prepared.userOp);

    final currentAccount = account;
    final userOperationHash = getUserOperationHash(
      userOperation: userOp,
      entryPointAddress: entryPoint,
      entryPointVersion: entryPointVersion!,
      chainId: account.chainId,
      eip7702DelegationAddress: prepared.authorization?.address ??
          (currentAccount is Eip7702SmartAccount
              ? currentAccount.accountLogicAddress
              : null),
    );

    final deadline = DateTime.now().add(timeout ?? bundler.rpcClient.timeout);

    // Settles [future] into an outcome, or [_Expired] at the deadline. Errors
    // become values first, so an inner TimeoutException (e.g. the HTTP
    // client's) is never mistaken for the deadline.
    Future<_Outcome<T>> beforeDeadline<T>(Future<T> future) {
      final remaining = deadline.difference(DateTime.now());
      return future
          .then<_Outcome<T>>(
            _Done<T>.new,
            onError: _Failed<T>.new,
          )
          .timeout(
            remaining.isNegative ? Duration.zero : remaining,
            onTimeout: _Expired<T>.new,
          );
    }

    Future<UserOperationReceipt?> waitForReceipt() async {
      while (DateTime.now().isBefore(deadline)) {
        switch (await beforeDeadline(
          bundler.getUserOperationReceipt(userOperationHash),
        )) {
          case _Expired():
            return null;
          case _Done(:final value?):
            return value;
          case _Done() || _Failed():
            break;
        }
        await beforeDeadline(Future<void>.delayed(pollingInterval));
      }
      return null;
    }

    final response = await beforeDeadline(
      bundler.rpcClient.call('pimlico_sendUserOperationNow', [
        userOperationRequestJson(userOp, authorization: prepared.authorization),
        entryPoint.hex,
      ]),
    );

    final Object? error;
    switch (response) {
      case _Expired():
        // No answer before the deadline: it may have been sent.
        throw SendUserOperationSyncError(
          kind: SendUserOperationSyncErrorKind.pending,
          userOperationHash: userOperationHash,
        );
      case _Done(:final Map<String, dynamic> value):
        return UserOperationReceipt.fromJson(value);
      case _Done():
        // `null` (or a non-object) result: the outcome is unclear, so poll.
        error = null;
      case _Failed(error: final failure):
        error = failure;
    }

    // A JSON-RPC error answer from the bundler. HTTP failures, transport
    // timeouts and socket errors are "no answer", like viem's non-RPC errors.
    final rpcError =
        error is BundlerRpcError && error is! BundlerHttpError ? error : null;
    final rpcData = rpcError?.data;
    final hasTransactionHash =
        rpcData is Map && rpcData['transactionHash'] != null;

    if (rpcError != null && rpcError.code == -32521) {
      throw SendUserOperationSyncError(
        kind: SendUserOperationSyncErrorKind.bundleReverted,
        userOperationHash: userOperationHash,
        message: rpcError.message,
        cause: rpcError,
      );
    }

    if (rpcError != null && !hasTransactionHash && rpcError.code != -32603) {
      throw SendUserOperationSyncError(
        kind: SendUserOperationSyncErrorKind.rejected,
        userOperationHash: userOperationHash,
        cause: rpcError,
      );
    }

    // Sent but not included yet, internal error, or no answer at all:
    // poll until the deadline, never resend.
    final receipt = await waitForReceipt();
    if (receipt != null) return receipt;
    throw SendUserOperationSyncError(
      // Only -32603 without a transaction hash means it wasn't sent.
      kind: rpcError?.code == -32603 && !hasTransactionHash
          ? SendUserOperationSyncErrorKind.notFound
          : SendUserOperationSyncErrorKind.pending,
      userOperationHash: userOperationHash,
      cause: error,
    );
  }
}

sealed class _Outcome<T> {}

final class _Done<T> extends _Outcome<T> {
  _Done(this.value);
  final T value;
}

final class _Failed<T> extends _Outcome<T> {
  _Failed(this.error);
  final Object error;
}

final class _Expired<T> extends _Outcome<T> {}
