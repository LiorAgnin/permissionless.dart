import '../../accounts/safe/safe_account.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/user_operation.dart';
import '../../utils/erc20.dart';
import '../bundler/bundler_client.dart';
import '../bundler/types.dart';
import '../paymaster/paymaster_client.dart';
import '../paymaster/types.dart';
import '../public/public_client.dart';
import 'smart_account_interface.dart';

/// A prepared UserOperation ready for signing and submission.
///
/// For EIP-7702 accounts, this may include an authorization that must be
/// submitted alongside the UserOperation.
class PreparedUserOperation {
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
  SmartAccountClient({
    required this.account,
    required this.bundler,
    required this.publicClient,
    this.paymaster,
  });

  /// The smart account to use for operations.
  final SmartAccount account;

  /// The bundler client for gas estimation and submission.
  final BundlerClient bundler;

  /// Optional paymaster client for sponsored transactions.
  final PaymasterClient? paymaster;

  /// Optional public client for EIP-7702 delegation status checks.
  ///
  /// Required for EIP-7702 accounts to check if delegation is active
  /// and to retrieve the EOA nonce for authorization creation.
  final PublicClient publicClient;

  /// Gets the address of the smart account.
  Future<EthereumAddress> getAddress() => account.getAddress();

  /// Creates an EIP-7702 authorization if needed.
  ///
  /// Returns null if authorization is not needed (non-EIP-7702 account,
  /// no public client, or delegation already active).
  Future<Eip7702Authorization?> _createAuthorizationIfNeeded() async {
    if (account is! Eip7702SmartAccount) {
      return null;
    }

    final address = await account.getAddress();
    final isDeployed = await publicClient.isDeployed(address);
    if (isDeployed) {
      return null;
    }

    // Get EOA nonce for authorization
    final eoaNonce = await publicClient.getTransactionCount(address);
    return (account as Eip7702SmartAccount).getAuthorization(nonce: eoaNonce);
  }

  /// EIP-7702 factory marker address.
  ///
  /// Used to signal to the bundler that this UserOperation requires
  /// EIP-7702 authorization handling.
  static final _eip7702FactoryMarker =
      EthereumAddress.fromHex('0x7702000000000000000000000000000000000000');

  /// Prepares a UserOperation without signing.
  ///
  /// This builds the UserOperation, applies paymaster stub data (if using),
  /// estimates gas, and applies final paymaster data. The returned UserOp
  /// is ready for signing.
  ///
  /// Use this for advanced workflows where you need to inspect or modify
  /// the UserOperation before signing.
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
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
  }) async {
    final prepared = await prepareUserOperationWithAuth(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
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
  /// [stateOverride] can be provided to override contract state during gas
  /// estimation. This is useful for ERC-20 paymaster scenarios where you need
  /// to simulate having sufficient token balance before the account is funded.
  ///
  /// Example:
  /// ```dart
  /// final prepared = await client.prepareUserOperationWithAuth(
  ///   calls: [Call(to: recipient, value: amount)],
  ///   maxFeePerGas: gasPrices.fast.maxFeePerGas,
  ///   maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
  /// );
  ///
  /// // Sign and send with authorization handling
  /// final signedOp = await client.signUserOperation(prepared.userOp);
  /// final hash = await client.sendPreparedUserOperationWithAuth(
  ///   signedOp,
  ///   prepared.authorization,
  /// );
  /// ```
  Future<PreparedUserOperation> prepareUserOperationWithAuth({
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
  }) async {
    sender ??= await account.getAddress();

    // Check if we need EIP-7702 authorization
    final authorization = await _createAuthorizationIfNeeded();
    final needsAuth = authorization != null;

    // Check if account is already deployed (requires publicClient)
    var isDeployed = false;
    isDeployed = await publicClient.isDeployed(sender);

    // Auto-fetch nonce if not provided and publicClient is available
    BigInt accountNonce;
    if (nonce != null) {
      accountNonce = nonce;
    } else {
      accountNonce = await publicClient.getAccountNonce(
        sender,
        account.entryPoint,
      );
    }

    // Get factory data if account is not yet deployed
    EthereumAddress? factory;
    String? factoryData;
    if (!isDeployed) {
      if (needsAuth) {
        // EIP-7702: Use marker factory address to signal authorization needed
        factory = _eip7702FactoryMarker;
        factoryData = '0x';
      } else {
        final data = await account.getFactoryData();
        if (data != null) {
          factory = data.factory;
          factoryData = data.factoryData;
        }
      }
    }

    // Encode calls - use deployment encoding for ERC-7579 Safe first UserOp
    final isDeployment = factory != null;
    String callData;
    if (isDeployment &&
        account is SafeSmartAccount &&
        (account as SafeSmartAccount).isErc7579Enabled) {
      callData = (account as SafeSmartAccount).encodeCallsForDeployment(calls);
    } else {
      callData = account.encodeCalls(calls);
    }

    // Build initial UserOperation with stub signature
    var userOp = UserOperationV07(
      sender: sender,
      nonce: accountNonce,
      factory: factory,
      factoryData: factoryData,
      callData: callData,
      callGasLimit: BigInt.zero,
      verificationGasLimit: BigInt.zero,
      preVerificationGas: BigInt.zero,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      signature: account.getStubSignature(),
    );

    // Apply paymaster stub data if using paymaster
    PaymasterStubData? stubData;
    if (paymaster != null) {
      stubData = await paymaster!.getPaymasterStubData(
        userOp: userOp,
        entryPoint: account.entryPoint,
        chainId: account.chainId,
        context: paymasterContext,
      );
      userOp = userOp.withPaymasterStub(stubData);
    }

    // Estimate gas - use authorization-aware estimation if needed
    // Convert state overrides to JSON format for RPC call
    final stateOverrideJson = stateOverride != null && stateOverride.isNotEmpty
        ? stateOverridesToJson(stateOverride)
        : null;

    UserOperationGasEstimate gasEstimate;
    if (needsAuth) {
      gasEstimate = await bundler.estimateUserOperationGasWithAuthorization(
        userOp,
        [authorization],
        stateOverride: stateOverrideJson,
      );
    } else {
      gasEstimate = await bundler.estimateUserOperationGas(
        userOp,
        stateOverride: stateOverrideJson,
      );
    }
    userOp = _applyGasEstimate(userOp, gasEstimate);

    // Get final paymaster data if using paymaster and not final
    if (paymaster != null && stubData != null && !stubData.isFinal) {
      final finalData = await paymaster!.getPaymasterData(
        userOp: userOp,
        entryPoint: account.entryPoint,
        chainId: account.chainId,
        context: paymasterContext,
      );
      userOp = userOp.withPaymasterData(finalData);
    }

    return PreparedUserOperation(
      userOp: userOp,
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
  /// Returns the UserOperation hash for tracking.
  ///
  /// **Note:** For EIP-7702 accounts with first-time delegation, use
  /// [sendPreparedUserOperationWithAuth] instead to include the authorization.
  Future<String> sendPreparedUserOperation(UserOperationV07 userOp) =>
      bundler.sendUserOperation(userOp);

  /// Sends a signed UserOperation with optional EIP-7702 authorization.
  ///
  /// If [authorization] is provided, uses the authorization-aware bundler
  /// method. Otherwise, falls back to standard submission.
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
  ) {
    if (authorization != null) {
      return bundler
          .sendUserOperationWithAuthorization(userOp, [authorization]);
    }
    return bundler.sendUserOperation(userOp);
  }

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
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
  }) async {
    final prepared = await prepareUserOperationWithAuth(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
      paymasterContext: paymasterContext,
      sender: sender,
      stateOverride: stateOverride,
    );

    final signedOp = await signUserOperation(prepared.userOp);
    return sendPreparedUserOperationWithAuth(signedOp, prepared.authorization);
  }

  /// Sends a UserOperation and waits for the receipt.
  ///
  /// Convenience method that combines [sendUserOperation] with
  /// [waitForReceipt].
  ///
  /// For EIP-7702 accounts, this automatically handles authorization
  /// creation and submission when the publicClient is available.
  ///
  /// [stateOverride] can be provided to override contract state during gas
  /// estimation. This is useful for ERC-20 paymaster scenarios where you need
  /// to simulate having sufficient token balance before the account is funded.
  Future<UserOperationReceipt?> sendUserOperationAndWait({
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    Duration timeout = const Duration(seconds: 60),
    Duration pollingInterval = const Duration(seconds: 2),
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
  }) async {
    final hash = await sendUserOperation(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
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
  Future<UserOperationReceipt?> waitForReceipt(
    String userOpHash, {
    Duration timeout = const Duration(seconds: 60),
    Duration pollingInterval = const Duration(seconds: 2),
  }) =>
      bundler.waitForUserOperationReceipt(
        userOpHash,
        timeout: timeout,
        pollingInterval: pollingInterval,
      );

  /// Prepares a UserOperation v0.6 without signing.
  ///
  /// This builds the UserOperation, applies paymaster stub data (if using),
  /// estimates gas, and applies final paymaster data. The returned UserOp
  /// is ready for signing.
  ///
  /// Use this for advanced workflows where you need to inspect or modify
  /// the UserOperation before signing.
  ///
  /// [sender] can be provided to override the account's computed address.
  /// This is useful when the local address computation doesn't match
  /// the factory's CREATE2 calculation (use getSenderAddress to get the
  /// correct address from the EntryPoint).
  Future<UserOperationV06> prepareUserOperationV06({
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
  }) async {
    sender ??= await account.getAddress();

    // Check if account is already deployed (requires publicClient)
    var isDeployed = false;
    isDeployed = await publicClient.isDeployed(sender);

    // Get initCode if account is not yet deployed
    var initCode = '0x';
    if (!isDeployed) {
      initCode = await account.getInitCode();
    }

    // Build initial UserOperation with stub signature
    var userOp = UserOperationV06(
      sender: sender,
      nonce: nonce ?? BigInt.zero,
      initCode: initCode,
      callData: account.encodeCalls(calls),
      callGasLimit: BigInt.zero,
      verificationGasLimit: BigInt.zero,
      preVerificationGas: BigInt.zero,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      signature: account.getStubSignature(),
    );

    // For v0.6, use sponsorUserOperation which returns both paymaster data and gas estimates
    if (paymaster != null) {
      final sponsorResult = await paymaster!.sponsorUserOperation(
        userOp: userOp,
        entryPoint: account.entryPoint,
        chainId: account.chainId,
        context: paymasterContext,
      );
      // Apply sponsorship result (includes paymaster data and gas estimates)
      userOp = userOp.withSponsorshipV06(sponsorResult);
    } else {
      // Estimate gas if no paymaster
      final gasEstimate = await bundler.estimateUserOperationGas(userOp);
      userOp = _applyGasEstimateV06(userOp, gasEstimate);
    }

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
      bundler.sendUserOperation(userOp);

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
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
  }) async {
    var userOp = await prepareUserOperationV06(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
      paymasterContext: paymasterContext,
      sender: sender,
    );

    userOp = await signUserOperationV06(userOp);
    return sendPreparedUserOperationV06(userOp);
  }

  /// Sends a UserOperation v0.6 and waits for the receipt.
  ///
  /// Convenience method that combines [sendUserOperationV06] with
  /// [waitForReceipt].
  Future<UserOperationReceipt?> sendUserOperationV06AndWait({
    required List<Call> calls,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    BigInt? nonce,
    PaymasterContext? paymasterContext,
    Duration timeout = const Duration(seconds: 60),
    Duration pollingInterval = const Duration(seconds: 2),
    EthereumAddress? sender,
  }) async {
    final hash = await sendUserOperationV06(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
      paymasterContext: paymasterContext,
      sender: sender,
    );

    return waitForReceipt(
      hash,
      timeout: timeout,
      pollingInterval: pollingInterval,
    );
  }

  /// Applies gas estimates to a UserOperation.
  UserOperationV07 _applyGasEstimate(
    UserOperationV07 userOp,
    UserOperationGasEstimate estimate,
  ) =>
      userOp.copyWith(
        preVerificationGas: estimate.preVerificationGas,
        verificationGasLimit: estimate.verificationGasLimit,
        callGasLimit: estimate.callGasLimit,
        paymasterVerificationGasLimit: estimate.paymasterVerificationGasLimit,
        paymasterPostOpGasLimit: estimate.paymasterPostOpGasLimit,
      );

  /// Applies gas estimates to a UserOperation v0.6.
  UserOperationV06 _applyGasEstimateV06(
    UserOperationV06 userOp,
    UserOperationGasEstimate estimate,
  ) =>
      userOp.copyWith(
        preVerificationGas: estimate.preVerificationGas,
        verificationGasLimit: estimate.verificationGasLimit,
        callGasLimit: estimate.callGasLimit,
      );

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
///   bundlerUrl: 'https://bundler.example.com/rpc',
///   paymasterUrl: 'https://paymaster.example.com/rpc', // optional
/// );
/// ```
///
/// For EIP-7702 accounts, provide a [publicClient] to enable automatic
/// delegation detection and authorization handling:
/// ```dart
/// final client = createSmartAccountClient(
///   account: eip7702Account,
///   bundler: bundlerClient,
///   publicClient: publicClient, // required for EIP-7702
/// );
/// ```
SmartAccountClient createSmartAccountClient({
  required SmartAccount account,
  required BundlerClient bundler,
  required PublicClient publicClient,
  PaymasterClient? paymaster,
}) =>
    SmartAccountClient(
      account: account,
      bundler: bundler,
      publicClient: publicClient,
      paymaster: paymaster,
    );
