import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/user_operation.dart';
import '../../utils/gas.dart';
import '../../utils/state_override.dart';
import '../bundler/bundler_client.dart';
import '../bundler/types.dart';
import '../paymaster/paymaster_client.dart';
import '../paymaster/types.dart';
import '../public/public_client.dart';
import 'call_encoding.dart';
import 'smart_account_interface.dart';

/// A prepared UserOperation ready for signing and submission.
///
/// For EIP-7702 accounts, this may include an authorization that must be
/// submitted alongside the UserOperation.
class PreparedUserOperation {
  /// Creates a prepared UserOperation result.
  ///
  /// - [userOp]: The prepared but unsigned UserOperation
  /// - [authorization]: Optional EIP-7702 authorization for first-time delegation
  const PreparedUserOperation({
    required this.userOp,
    this.authorization,
  });

  /// The prepared UserOperation (unsigned).
  final UserOperationV07 userOp;

  /// Optional EIP-7702 authorization for first-time delegation.
  ///
  /// This is only set for EIP-7702 accounts when delegation is not yet active.
  final Eip7702Authorization? authorization;

  /// Whether this operation requires EIP-7702 authorization.
  bool get needsAuthorization => authorization != null;
}

/// Hook that estimates EIP-1559 fees for UserOperation preparation.
///
/// Mirrors viem/permissionless.js `userOperation.estimateFeesPerGas`.
/// Use this to inject a Pimlico gas-price oracle or custom fee source.
typedef EstimateFeesPerGas = Future<FeeEstimate> Function();

/// Unified client for ERC-4337 smart account operations.
///
/// Orchestrates the smart account, bundler, and optional paymaster
/// to provide a seamless UserOperation flow.
///
/// Example:
/// ```dart
/// final client = SmartAccountClient(
///   account: safeAccount,
///   bundler: bundlerClient,
///   publicClient: publicClient,
///   paymaster: paymasterClient, // optional
/// );
///
/// // Send a simple transfer
/// final hash = await client.sendUserOperation(
///   calls: [Call(to: recipient, value: amount)],
///   maxFeePerGas: BigInt.from(1000000000),
///   maxPriorityFeePerGas: BigInt.from(1000000000),
/// );
///
/// // Wait for confirmation
/// final receipt = await client.waitForReceipt(hash);
/// ```
class SmartAccountClient {
  /// Creates a smart account client with the given components.
  ///
  /// Prefer using [createSmartAccountClient] factory function instead.
  ///
  /// - [account]: The smart account implementation to use
  /// - [bundler]: Bundler client for gas estimation and UserOp submission
  /// - [publicClient]: Public client for nonce queries and deployment checks
  /// - [paymaster]: Optional paymaster for sponsored/ERC-20 gas payment
  /// - [paymasterContext]: Optional default paymaster context (per-call overrides)
  /// - [estimateFeesPerGas]: Optional fee-estimation hook used when fees are
  ///   not supplied to prepare/send methods
  /// - [gasMultipliers]: Optional gas multipliers for buffering estimates
  ///   (Dart-only; viem returns raw bundler estimates without multipliers)
  SmartAccountClient({
    required this.account,
    required this.bundler,
    required this.publicClient,
    this.paymaster,
    this.paymasterContext,
    this.estimateFeesPerGas,
    this.gasMultipliers = GasMultipliers.standard,
  });

  /// The smart account to use for operations.
  final SmartAccount account;

  /// Gas multipliers for buffering estimates.
  ///
  /// Default is [GasMultipliers.standard] which adds 10% buffers.
  /// Use [GasMultipliers.conservative] for WebAuthn/P256 signatures.
  ///
  /// **Dart-only:** viem/permissionless.js return raw bundler gas estimates
  /// without post-estimation multipliers. These buffers are intentional for
  /// reliability (bundlers sometimes underestimate) but mean gas limits will
  /// not be byte-identical to viem for the same inputs.
  final GasMultipliers gasMultipliers;

  /// The bundler client for gas estimation and submission.
  final BundlerClient bundler;

  /// Optional paymaster client for sponsored transactions.
  final PaymasterClient? paymaster;

  /// Default paymaster context applied when a per-call context is not provided.
  ///
  /// Mirrors permissionless.js `createSmartAccountClient({ paymasterContext })`.
  final PaymasterContext? paymasterContext;

  /// Optional fee-estimation hook used when [maxFeePerGas] /
  /// [maxPriorityFeePerGas] are not supplied to prepare/send methods.
  ///
  /// Mirrors viem `userOperation.estimateFeesPerGas`. When null, fees fall
  /// back to [PublicClient.getFeeData] with a 2× buffer (viem default).
  final EstimateFeesPerGas? estimateFeesPerGas;

  /// Optional public client for EIP-7702 delegation status checks.
  ///
  /// Required for EIP-7702 accounts to check if delegation is active
  /// and to retrieve the EOA nonce for authorization creation.
  final PublicClient publicClient;

  /// Gets the address of the smart account.
  Future<EthereumAddress> getAddress() => account.getAddress();

  /// Creates an EIP-7702 authorization if needed.
  ///
  /// Returns null if authorization is not needed (non-EIP-7702 account, or
  /// the EOA is already delegated to this account's logic contract).
  ///
  /// If the EOA has code delegated to a *different* implementation (e.g. ran
  /// Simple7702 then Kernel7702 with the same key), a new authorization is
  /// created so the bundler can re-delegate.
  Future<Eip7702Authorization?> _createAuthorizationIfNeeded() async {
    if (account is! Eip7702SmartAccount) {
      return null;
    }

    final eip7702 = account as Eip7702SmartAccount;
    final address = await eip7702.getAddress();
    final code = (await publicClient.getCode(address)).toLowerCase();

    // An active EIP-7702 delegation is `0xef0100 ‖ implementation`. Any other
    // code (none, a different implementation, or non-7702 code) gets a fresh
    // authorization; the bundler rejects it if the EOA cannot be delegated.
    final isDelegatedHere = code.length >= 48 &&
        code.startsWith('0xef0100') &&
        '0x${code.substring(8, 48)}' == eip7702.accountLogicAddress.hex;
    if (isDelegatedHere) return null;

    final eoaNonce = await publicClient.getTransactionCount(address);
    return eip7702.getAuthorization(nonce: eoaNonce);
  }

  /// Prepares a UserOperation without signing.
  ///
  /// This builds the UserOperation, applies paymaster stub data (if using),
  /// estimates gas (only for fields that are missing), and applies final
  /// paymaster data. The returned UserOp is ready for signing.
  ///
  /// Use this for advanced workflows where you need to inspect or modify
  /// the UserOperation before signing.
  ///
  /// Partial-override semantics match viem `prepareUserOperation`: supply any
  /// of [callData], gas limits, [signature], [factory]/[factoryData], or fees
  /// and only the missing fields are filled.
  ///
  /// Provide either [calls] (encoded by the account) or pre-encoded [callData].
  ///
  /// [sender] can be provided to override the account's computed address.
  /// This is useful when the local address computation doesn't match
  /// the factory's CREATE2 calculation (use getSenderAddress to get the
  /// correct address from the EntryPoint).
  ///
  /// [stateOverride] can be provided to override contract state during gas
  /// estimation. This is useful for ERC-20 paymaster scenarios where you need
  /// to simulate having sufficient token balance before the account is funded.
  ///
  /// **Note:** For EIP-7702 accounts, use [prepareUserOperationWithAuth] to
  /// get the authorization required for submission.
  Future<UserOperationV07> prepareUserOperation({
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
  }) async {
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
    return prepared.userOp;
  }

  /// Prepares a UserOperation with EIP-7702 authorization support.
  ///
  /// This is similar to [prepareUserOperation], but returns a
  /// [PreparedUserOperation] that includes any required EIP-7702
  /// authorization for first-time delegation.
  ///
  /// For non-EIP-7702 accounts, the authorization will be null.
  ///
  /// Partial-override semantics match viem: user-supplied fields are kept and
  /// only missing fields are filled. Gas estimation is skipped when
  /// [callGasLimit], [verificationGasLimit], and [preVerificationGas] are all
  /// provided.
  ///
  /// Provide either [calls] or pre-encoded [callData].
  ///
  /// [stateOverride] can be provided to override contract state during gas
  /// estimation. This is useful for ERC-20 paymaster scenarios where you need
  /// to simulate having sufficient token balance before the account is funded.
  ///
  /// [skipFinalPaymasterData] skips the trailing `pm_getPaymasterData` call:
  /// the returned op keeps the stub paymaster data (gas fields are still
  /// estimated). Use it when the caller re-requests final paymaster data
  /// itself over modified calldata (e.g. the ERC-20 paymaster helper) —
  /// this avoids a paid paymaster round-trip whose result would be discarded.
  ///
  /// Example:
  /// ```dart
  /// final prepared = await client.prepareUserOperationWithAuth(
  ///   calls: [Call(to: recipient, value: amount)],
  ///   maxFeePerGas: gasPrices.fast.maxFeePerGas,
  ///   maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
  /// );
  ///
  /// final signedOp = await client.signUserOperation(prepared.userOp);
  /// final hash = await client.sendPreparedUserOperation(
  ///   signedOp,
  ///   authorization: prepared.authorization,
  /// );
  /// ```
  Future<PreparedUserOperation> prepareUserOperationWithAuth({
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
    bool skipFinalPaymasterData = false,
  }) async {
    _requireCalls(calls, callData);

    final resolvedContext = paymasterContext ?? this.paymasterContext;
    sender ??= await account.getAddress();

    final authorization = await _createAuthorizationIfNeeded();
    final needsAuth = authorization != null;

    final isDeployed = await publicClient.isDeployed(sender);
    final accountNonce = await _resolveNonce(sender, nonce);

    // Resolve factory: honor overrides, else derive
    var resolvedFactory = factory;
    var resolvedFactoryData = factoryData;
    if (resolvedFactory == null && resolvedFactoryData == null) {
      if (needsAuth) {
        // EIP-7702 first-time (no code yet): on EntryPoint v0.8 set the 0x7702
        // initCode marker so the EntryPoint applies the delegation. v0.7 has
        // no marker (non-empty initCode for the delegated EOA reverts AA10)
        // and the authorization travels alone, like permissionless.js's 7702
        // Kernel. Re-delegation (EOA already has 0xef0100… code to a
        // *different* implementation) must omit factory — Pimlico rejects
        // factory when the sender is already constructed.
        if (!isDeployed &&
            entryPointVersionOfAccount(account) == EntryPointVersion.v08) {
          resolvedFactory = eip7702FactoryMarkerAddress;
          resolvedFactoryData = '0x';
        }
      } else if (!isDeployed) {
        final data = await account.getFactoryData();
        if (data != null) {
          resolvedFactory = data.factory;
          resolvedFactoryData = data.factoryData;
        }
      }
    }

    final resolvedCallData = callData ??
        encodeUserOperationCalls(
          account,
          calls!,
          deploysAccount: resolvedFactory != null,
        );

    // Resolve fees: keep both when supplied; else hook; else 2× getFeeData
    final fees = await _resolveFees(
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
    );

    var userOp = UserOperationV07(
      sender: sender,
      nonce: accountNonce,
      factory: resolvedFactory,
      factoryData: resolvedFactoryData,
      callData: resolvedCallData,
      callGasLimit: callGasLimit ?? BigInt.zero,
      verificationGasLimit: verificationGasLimit ?? BigInt.zero,
      preVerificationGas: preVerificationGas ?? BigInt.zero,
      maxFeePerGas: fees.maxFeePerGas,
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
      signature: signature ?? account.getStubSignature(),
    );

    // The EIP-7702 authorization (when present) is forwarded so the paymaster
    // sees the same `eip7702Auth` context as the bundler (viem parity).
    final stubData = await _paymasterStubData(
      userOp,
      resolvedContext,
      authorization: authorization,
    );
    if (stubData != null) userOp = userOp.withPaymasterStub(stubData);

    final stateOverrideJson = stateOverride != null && stateOverride.isNotEmpty
        ? stateOverridesToJson(stateOverride)
        : null;

    // viem estimates only when at least one core gas field is missing.
    final needsGasEstimate = callGasLimit == null ||
        verificationGasLimit == null ||
        preVerificationGas == null;

    if (needsGasEstimate) {
      final gasEstimate = await bundler.estimateUserOperationGas(
        userOp,
        stateOverride: stateOverrideJson,
        entryPoint: account.entryPoint,
        authorization: authorization,
      );
      userOp = _applyGasEstimate(
        userOp,
        gasEstimate,
        preserveCallGasLimit: callGasLimit,
        preserveVerificationGasLimit: verificationGasLimit,
        preservePreVerificationGas: preVerificationGas,
      );
    }

    // skipFinalPaymasterData mirrors permissionless.js, where the prepare
    // step substitutes stub data and the single real pm_getPaymasterData
    // happens at the end of the helper.
    final finalData = await _finalPaymasterData(
      userOp,
      stubData,
      resolvedContext,
      skip: skipFinalPaymasterData,
      authorization: authorization,
    );
    if (finalData != null) userOp = userOp.withPaymasterData(finalData);

    return PreparedUserOperation(
      userOp: userOp,
      authorization: authorization,
    );
  }

  static void _requireCalls(List<Call>? calls, String? callData) {
    if (calls == null && callData == null) {
      throw ArgumentError('Either calls or callData must be provided');
    }
  }

  /// The caller's [nonce], else the EntryPoint's next nonce for [sender] on
  /// the account's nonce key.
  Future<BigInt> _resolveNonce(EthereumAddress sender, BigInt? nonce) async =>
      nonce ??
      await publicClient.getAccountNonce(
        sender,
        account.entryPoint,
        nonceKey: account.nonceKey,
      );

  /// Resolves max fee fields using caller values, the client hook, or a
  /// 2×-buffered [PublicClient.getFeeData] fallback (viem parity).
  Future<FeeEstimate> _resolveFees({
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
  }) async {
    if (maxFeePerGas != null && maxPriorityFeePerGas != null) {
      return FeeEstimate(
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
      );
    }

    if (estimateFeesPerGas != null) {
      final hooked = await estimateFeesPerGas!();
      return FeeEstimate(
        maxFeePerGas: maxFeePerGas ?? hooked.maxFeePerGas,
        maxPriorityFeePerGas:
            maxPriorityFeePerGas ?? hooked.maxPriorityFeePerGas,
      );
    }

    // viem fallback: estimateFeesPerGas + 2× buffer on missing fields
    final feeData = await publicClient.getFeeData();
    final baseMax = feeData.gasPrice;
    final basePriority = feeData.maxPriorityFeePerGas ?? feeData.gasPrice;
    return FeeEstimate(
      maxFeePerGas: maxFeePerGas ?? baseMax * BigInt.two,
      maxPriorityFeePerGas: maxPriorityFeePerGas ?? basePriority * BigInt.two,
    );
  }

  /// ERC-7677 `pm_getPaymasterStubData` for [userOp], or null without a
  /// [paymaster]. viem `prepareUserOperation` runs it for every EntryPoint
  /// version.
  Future<PaymasterStubData?> _paymasterStubData(
    UserOperation userOp,
    PaymasterContext? context, {
    Eip7702Authorization? authorization,
  }) async =>
      paymaster?.getPaymasterStubData(
        userOp: userOp,
        entryPoint: account.entryPoint,
        chainId: account.chainId,
        context: context,
        authorization: authorization,
      );

  /// ERC-7677 `pm_getPaymasterData` over the estimated [userOp]; null when
  /// there is no [stub] (no paymaster), the stub is final, or [skip] is set.
  Future<PaymasterData?> _finalPaymasterData(
    UserOperation userOp,
    PaymasterStubData? stub,
    PaymasterContext? context, {
    bool skip = false,
    Eip7702Authorization? authorization,
  }) async {
    if (stub == null || stub.isFinal || skip) return null;
    return paymaster!.getPaymasterData(
      userOp: userOp,
      entryPoint: account.entryPoint,
      chainId: account.chainId,
      context: context,
      authorization: authorization,
    );
  }

  /// Signs a prepared UserOperation.
  ///
  /// Returns the UserOperation with the signature field populated.
  Future<UserOperationV07> signUserOperation(UserOperationV07 userOp) async {
    final signature = await account.signUserOperation(userOp);
    return userOp.copyWith(signature: signature);
  }

  /// Sends a signed UserOperation to the bundler.
  ///
  /// Pass the [PreparedUserOperation.authorization] of an EIP-7702 account
  /// as [authorization]; it is sent as the op's `eip7702Auth`.
  ///
  /// Returns the UserOperation hash for tracking.
  Future<String> sendPreparedUserOperation(
    UserOperationV07 userOp, {
    Eip7702Authorization? authorization,
  }) =>
      bundler.sendUserOperation(
        userOp,
        entryPoint: account.entryPoint,
        authorization: authorization,
      );

  /// Sends a signed UserOperation with optional EIP-7702 authorization.
  ///
  /// Same as [sendPreparedUserOperation] with a positional [authorization].
  ///
  /// Returns the UserOperation hash for tracking.
  ///
  /// Example:
  /// ```dart
  /// final prepared = await client.prepareUserOperationWithAuth(...);
  /// final signedOp = await client.signUserOperation(prepared.userOp);
  /// final hash = await client.sendPreparedUserOperationWithAuth(
  ///   signedOp,
  ///   prepared.authorization,
  /// );
  /// ```
  Future<String> sendPreparedUserOperationWithAuth(
    UserOperationV07 userOp,
    Eip7702Authorization? authorization,
  ) =>
      sendPreparedUserOperation(userOp, authorization: authorization);

  /// Prepares, signs, and sends a UserOperation in one call.
  ///
  /// This is the primary method for sending transactions.
  /// Returns the UserOperation hash.
  ///
  /// For EIP-7702 accounts, this automatically handles authorization
  /// creation and submission when the publicClient is available.
  ///
  /// [stateOverride] can be provided to override contract state during gas
  /// estimation. This is useful for ERC-20 paymaster scenarios where you need
  /// to simulate having sufficient token balance before the account is funded.
  ///
  /// Example:
  /// ```dart
  /// final hash = await client.sendUserOperation(
  ///   calls: [
  ///     Call(
  ///       to: EthereumAddress.fromHex('0x...'),
  ///       value: BigInt.from(1000000000000000000), // 1 ETH
  ///     ),
  ///   ],
  ///   maxFeePerGas: BigInt.from(1000000000),
  ///   maxPriorityFeePerGas: BigInt.from(1000000000),
  /// );
  /// ```
  Future<String> sendUserOperation({
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
  }) async {
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

    // If the caller supplied a final signature, skip re-signing.
    final signedOp = signature != null
        ? prepared.userOp
        : await signUserOperation(prepared.userOp);
    return sendPreparedUserOperation(
      signedOp,
      authorization: prepared.authorization,
    );
  }

  /// Sends a UserOperation and waits for the receipt.
  ///
  /// Convenience method that combines [sendUserOperation] with
  /// [waitForReceipt].
  ///
  /// For EIP-7702 accounts, this automatically handles authorization
  /// creation and submission when the publicClient is available.
  ///
  /// Throws [TimeoutException] if the receipt is not found within [timeout].
  ///
  /// [stateOverride] can be provided to override contract state during gas
  /// estimation. This is useful for ERC-20 paymaster scenarios where you need
  /// to simulate having sufficient token balance before the account is funded.
  Future<UserOperationReceipt> sendUserOperationAndWait({
    List<Call>? calls,
    String? callData,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    Duration timeout = defaultReceiptTimeout,
    Duration pollingInterval = defaultReceiptPollingInterval,
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
    BigInt? callGasLimit,
    BigInt? verificationGasLimit,
    BigInt? preVerificationGas,
    String? signature,
    EthereumAddress? factory,
    String? factoryData,
  }) async {
    final hash = await sendUserOperation(
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

    return waitForReceipt(
      hash,
      timeout: timeout,
      pollingInterval: pollingInterval,
    );
  }

  /// Waits for a UserOperation receipt.
  ///
  /// Polls the bundler until the operation is included or times out.
  ///
  /// Default timeout is 120 seconds (viem parity).
  ///
  /// Throws [TimeoutException] if the receipt is not found within [timeout].
  Future<UserOperationReceipt> waitForReceipt(
    String userOpHash, {
    Duration timeout = defaultReceiptTimeout,
    Duration pollingInterval = defaultReceiptPollingInterval,
  }) =>
      bundler.waitForUserOperationReceipt(
        userOpHash,
        timeout: timeout,
        pollingInterval: pollingInterval,
      );

  /// Prepares a UserOperation v0.6 without signing.
  ///
  /// This builds the UserOperation, applies paymaster stub data (if using),
  /// estimates gas (only for fields that are missing), and applies final
  /// paymaster data. The returned UserOp is ready for signing.
  ///
  /// The paymaster steps are ERC-7677 (`pm_getPaymasterStubData`, then
  /// `pm_getPaymasterData` unless the stub is final), the same as
  /// [prepareUserOperation] and viem `prepareUserOperation` on every
  /// EntryPoint version; the paymaster answers with `paymasterAndData`.
  /// Gas limits come from the bundler estimate.
  ///
  /// Use this for advanced workflows where you need to inspect or modify
  /// the UserOperation before signing.
  ///
  /// [sender] can be provided to override the account's computed address.
  /// This is useful when the local address computation doesn't match
  /// the factory's CREATE2 calculation (use getSenderAddress to get the
  /// correct address from the EntryPoint).
  ///
  /// [stateOverride] and [skipFinalPaymasterData] behave as in
  /// [prepareUserOperationWithAuth].
  Future<UserOperationV06> prepareUserOperationV06({
    List<Call>? calls,
    String? callData,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
    BigInt? callGasLimit,
    BigInt? verificationGasLimit,
    BigInt? preVerificationGas,
    String? signature,
    String? initCode,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
    bool skipFinalPaymasterData = false,
  }) async {
    _requireCalls(calls, callData);

    final resolvedContext = paymasterContext ?? this.paymasterContext;
    sender ??= await account.getAddress();

    final isDeployed = await publicClient.isDeployed(sender);
    final accountNonce = await _resolveNonce(sender, nonce);

    final resolvedInitCode =
        initCode ?? (isDeployed ? '0x' : await account.getInitCode());

    final fees = await _resolveFees(
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
    );

    final resolvedCallData = callData ??
        encodeUserOperationCalls(
          account,
          calls!,
          deploysAccount: resolvedInitCode != '0x',
        );

    var userOp = UserOperationV06(
      sender: sender,
      nonce: accountNonce,
      initCode: resolvedInitCode,
      callData: resolvedCallData,
      callGasLimit: callGasLimit ?? BigInt.zero,
      verificationGasLimit: verificationGasLimit ?? BigInt.zero,
      preVerificationGas: preVerificationGas ?? BigInt.zero,
      maxFeePerGas: fees.maxFeePerGas,
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
      signature: signature ?? account.getStubSignature(),
    );

    final stubData = await _paymasterStubData(userOp, resolvedContext);
    if (stubData != null) userOp = userOp.withPaymasterStubV06(stubData);

    final needsGasEstimate = callGasLimit == null ||
        verificationGasLimit == null ||
        preVerificationGas == null;

    if (needsGasEstimate) {
      final gasEstimate = await bundler.estimateUserOperationGas(
        userOp,
        stateOverride: stateOverride != null && stateOverride.isNotEmpty
            ? stateOverridesToJson(stateOverride)
            : null,
        entryPoint: account.entryPoint,
      );
      userOp = _applyGasEstimateV06(
        userOp,
        gasEstimate,
        preserveCallGasLimit: callGasLimit,
        preserveVerificationGasLimit: verificationGasLimit,
        preservePreVerificationGas: preVerificationGas,
      );
    }

    final finalData = await _finalPaymasterData(
      userOp,
      stubData,
      resolvedContext,
      skip: skipFinalPaymasterData,
    );
    if (finalData != null) userOp = userOp.withPaymasterDataV06(finalData);

    return userOp;
  }

  /// Signs a prepared UserOperation v0.6.
  ///
  /// Returns the UserOperation with the signature field populated.
  ///
  /// The account must implement [SmartAccountV06] to use this method.
  Future<UserOperationV06> signUserOperationV06(UserOperationV06 userOp) async {
    if (account is! SmartAccountV06) {
      throw StateError(
        'Account does not support v0.6 signing. '
        'Account must implement SmartAccountV06.',
      );
    }
    final signature =
        await (account as SmartAccountV06).signUserOperationV06(userOp);
    return userOp.copyWith(signature: signature);
  }

  /// Sends a signed UserOperation v0.6 to the bundler.
  ///
  /// Returns the UserOperation hash for tracking.
  Future<String> sendPreparedUserOperationV06(UserOperationV06 userOp) =>
      bundler.sendUserOperation(userOp, entryPoint: account.entryPoint);

  /// Prepares, signs, and sends a UserOperation v0.6 in one call.
  ///
  /// This is the primary method for sending transactions with v0.6 accounts.
  /// Returns the UserOperation hash.
  ///
  /// Example:
  /// ```dart
  /// final hash = await client.sendUserOperationV06(
  ///   calls: [
  ///     Call(
  ///       to: EthereumAddress.fromHex('0x...'),
  ///       value: BigInt.from(1000000000000000000), // 1 ETH
  ///     ),
  ///   ],
  ///   maxFeePerGas: BigInt.from(1000000000),
  ///   maxPriorityFeePerGas: BigInt.from(1000000000),
  /// );
  /// ```
  Future<String> sendUserOperationV06({
    List<Call>? calls,
    String? callData,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
    String? signature,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
  }) async {
    var userOp = await prepareUserOperationV06(
      calls: calls,
      callData: callData,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
      signature: signature,
      paymasterContext: paymasterContext,
      sender: sender,
    );

    if (signature == null) {
      userOp = await signUserOperationV06(userOp);
    }
    return sendPreparedUserOperationV06(userOp);
  }

  /// Sends a UserOperation v0.6 and waits for the receipt.
  ///
  /// Convenience method that combines [sendUserOperationV06] with
  /// [waitForReceipt].
  ///
  /// Throws [TimeoutException] if the receipt is not found within [timeout].
  Future<UserOperationReceipt> sendUserOperationV06AndWait({
    List<Call>? calls,
    String? callData,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    Duration timeout = defaultReceiptTimeout,
    Duration pollingInterval = defaultReceiptPollingInterval,
    EthereumAddress? sender,
    String? signature,
  }) async {
    final hash = await sendUserOperationV06(
      calls: calls,
      callData: callData,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
      signature: signature,
      paymasterContext: paymasterContext,
      sender: sender,
    );

    return waitForReceipt(
      hash,
      timeout: timeout,
      pollingInterval: pollingInterval,
    );
  }

  /// Applies gas estimates to a UserOperation with multipliers.
  ///
  /// For WebAuthn accounts, automatically applies minimum verification gas
  /// to account for expensive P256 on-chain signature verification (~800k gas).
  ///
  /// User-supplied gas fields ([preserveCallGasLimit] etc.) are kept and not
  /// overwritten by the estimate (viem `??` merge semantics).
  UserOperationV07 _applyGasEstimate(
    UserOperationV07 userOp,
    UserOperationGasEstimate estimate, {
    BigInt? preserveCallGasLimit,
    BigInt? preserveVerificationGasLimit,
    BigInt? preservePreVerificationGas,
  }) {
    var buffered = estimate.withMultipliers(gasMultipliers);

    // WebAuthn accounts require higher verification gas for P256 on-chain math
    // when the RIP-7212 precompile is not available (~800k gas).
    if (account.isWebAuthn) {
      buffered = buffered.withMinimumVerificationGas();
    }

    return userOp.copyWith(
      preVerificationGas:
          preservePreVerificationGas ?? buffered.preVerificationGas,
      verificationGasLimit:
          preserveVerificationGasLimit ?? buffered.verificationGasLimit,
      callGasLimit: preserveCallGasLimit ?? buffered.callGasLimit,
      // viem prepareUserOperation: the paymaster's own value, else the
      // estimate. The paymaster may have signed its gas fields.
      paymasterVerificationGasLimit: userOp.paymasterVerificationGasLimit ??
          buffered.paymasterVerificationGasLimit,
      paymasterPostOpGasLimit:
          userOp.paymasterPostOpGasLimit ?? buffered.paymasterPostOpGasLimit,
    );
  }

  /// Applies gas estimates to a UserOperation v0.6 with multipliers.
  ///
  /// User-supplied gas fields are preserved when provided.
  UserOperationV06 _applyGasEstimateV06(
    UserOperationV06 userOp,
    UserOperationGasEstimate estimate, {
    BigInt? preserveCallGasLimit,
    BigInt? preserveVerificationGasLimit,
    BigInt? preservePreVerificationGas,
  }) {
    final buffered = estimate.withMultipliers(gasMultipliers);
    return userOp.copyWith(
      preVerificationGas:
          preservePreVerificationGas ?? buffered.preVerificationGas,
      verificationGasLimit:
          preserveVerificationGasLimit ?? buffered.verificationGasLimit,
      callGasLimit: preserveCallGasLimit ?? buffered.callGasLimit,
    );
  }

  /// Closes the underlying clients.
  void close() {
    bundler.close();
    paymaster?.close();
  }
}

/// Creates a [SmartAccountClient] with the given configuration.
///
/// Example:
/// ```dart
/// final client = createSmartAccountClient(
///   account: safeAccount,
///   bundler: createBundlerClient(
///     url: 'https://bundler.example.com/rpc',
///     entryPoint: safeAccount.entryPoint,
///   ),
///   publicClient: createPublicClient(url: 'https://rpc.example.com'),
///   paymaster: createPaymasterClient(
///     url: 'https://paymaster.example.com/rpc',
///   ), // optional
/// );
/// ```
///
/// [publicClient] reads nonces and deployment state; for EIP-7702 accounts it
/// also detects whether the EOA is already delegated.
SmartAccountClient createSmartAccountClient({
  required SmartAccount account,
  required BundlerClient bundler,
  required PublicClient publicClient,
  PaymasterClient? paymaster,
  PaymasterContext? paymasterContext,
  EstimateFeesPerGas? estimateFeesPerGas,
  GasMultipliers gasMultipliers = GasMultipliers.standard,
}) =>
    SmartAccountClient(
      account: account,
      bundler: bundler,
      publicClient: publicClient,
      paymaster: paymaster,
      paymasterContext: paymasterContext,
      estimateFeesPerGas: estimateFeesPerGas,
      gasMultipliers: gasMultipliers,
    );
