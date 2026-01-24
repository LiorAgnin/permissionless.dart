import 'package:http/http.dart' as http;

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../bundler/rpc_client.dart';
import 'types.dart';

/// Client for interacting with ERC-4337 paymasters.
///
/// Paymasters are contracts that can sponsor gas fees for users,
/// enabling "gasless" transactions. This client supports the
/// standard paymaster API methods.
///
/// Example:
/// ```dart
/// final paymaster = createPaymasterClient(
///   url: 'https://paymaster.example.com/rpc',
/// );
///
/// // Get stub data for gas estimation
/// final stub = await paymaster.getPaymasterStubData(
///   userOp: userOp,
///   entryPoint: EntryPointAddresses.v07,
///   chainId: BigInt.from(1),
/// );
///
/// // Get actual paymaster data after gas estimation
/// final data = await paymaster.getPaymasterData(
///   userOp: estimatedUserOp,
///   entryPoint: EntryPointAddresses.v07,
///   chainId: BigInt.from(1),
/// );
/// ```
class PaymasterClient {
  /// Creates a paymaster client with the given RPC client.
  ///
  /// Prefer using [createPaymasterClient] factory function instead
  /// of calling this constructor directly.
  PaymasterClient({
    required this.rpcClient,
  });

  /// The underlying JSON-RPC client.
  final JsonRpcClient rpcClient;

  /// Gets stub paymaster data for gas estimation.
  ///
  /// Call this before estimating gas to include paymaster overhead
  /// in the estimation. The stub data is not valid for submission.
  ///
  /// If `isFinal` is true in the response, the stub data can be
  /// used directly for submission without calling `getPaymasterData`.
  Future<PaymasterStubData> getPaymasterStubData({
    required UserOperation userOp,
    required EthereumAddress entryPoint,
    required BigInt chainId,
    PaymasterContext? context,
  }) async {
    final params = <dynamic>[
      userOp.toJson(),
      entryPoint.hex,
      '0x${chainId.toRadixString(16)}',
      if (context != null) context.toJson(),
    ];

    final result = await rpcClient.call('pm_getPaymasterStubData', params);
    return PaymasterStubData.fromJson(result as Map<String, dynamic>);
  }

  /// Gets final paymaster data for UserOperation submission.
  ///
  /// Call this after gas estimation with the fully populated UserOperation.
  /// The returned data contains the paymaster signature.
  Future<PaymasterData> getPaymasterData({
    required UserOperation userOp,
    required EthereumAddress entryPoint,
    required BigInt chainId,
    PaymasterContext? context,
  }) async {
    final params = <dynamic>[
      userOp.toJson(),
      entryPoint.hex,
      '0x${chainId.toRadixString(16)}',
      if (context != null) context.toJson(),
    ];

    final result = await rpcClient.call('pm_getPaymasterData', params);
    return PaymasterData.fromJson(result as Map<String, dynamic>);
  }

  /// Sponsors a UserOperation in a single call.
  ///
  /// Some paymasters offer a combined endpoint that returns both
  /// gas estimates and paymaster data. This is more efficient than
  /// separate calls to stub + estimate + data.
  ///
  /// Not all paymasters support this method.
  Future<SponsorUserOperationResult> sponsorUserOperation({
    required UserOperation userOp,
    required EthereumAddress entryPoint,
    required BigInt chainId,
    PaymasterContext? context,
  }) async {
    final params = <dynamic>[
      userOp.toJson(),
      entryPoint.hex,
      if (context != null) context.toJson(),
    ];

    final result = await rpcClient.call('pm_sponsorUserOperation', params);
    return SponsorUserOperationResult.fromJson(result as Map<String, dynamic>);
  }

  /// Closes the underlying HTTP client.
  void close() => rpcClient.close();
}

/// Creates a [PaymasterClient] from a URL.
///
/// Example:
/// ```dart
/// final paymaster = createPaymasterClient(
///   url: 'https://paymaster.example.com/rpc',
/// );
/// ```
PaymasterClient createPaymasterClient({
  required String url,
  http.Client? httpClient,
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    PaymasterClient(
      rpcClient: JsonRpcClient(
        url: Uri.parse(url),
        httpClient: httpClient,
        headers: headers ?? {},
        timeout: timeout ?? const Duration(seconds: 30),
      ),
    );

/// Extension to apply paymaster data to UserOperations.
extension PaymasterUserOperationExtension on UserOperationV07 {
  /// Applies paymaster stub data for gas estimation.
  UserOperationV07 withPaymasterStub(PaymasterStubData stub) => copyWith(
        paymaster: stub.paymaster,
        paymasterData: stub.paymasterData,
        paymasterVerificationGasLimit: stub.paymasterVerificationGasLimit,
        paymasterPostOpGasLimit: stub.paymasterPostOpGasLimit,
      );

  /// Applies final paymaster data for submission.
  UserOperationV07 withPaymasterData(PaymasterData data) => copyWith(
        paymaster: data.paymaster,
        paymasterData: data.paymasterData,
        paymasterVerificationGasLimit: data.paymasterVerificationGasLimit,
        paymasterPostOpGasLimit: data.paymasterPostOpGasLimit,
      );

  /// Applies sponsored UserOperation result.
  UserOperationV07 withSponsorship(SponsorUserOperationResult result) =>
      copyWith(
        paymaster: result.paymaster,
        paymasterData: result.paymasterData,
        paymasterVerificationGasLimit: result.paymasterVerificationGasLimit,
        paymasterPostOpGasLimit: result.paymasterPostOpGasLimit,
        preVerificationGas: result.preVerificationGas,
        verificationGasLimit: result.verificationGasLimit,
        callGasLimit: result.callGasLimit,
      );
}

/// Extension to apply paymaster data to v0.6 UserOperations.
extension PaymasterUserOperationV06Extension on UserOperationV06 {
  /// Applies paymaster stub data for gas estimation.
  ///
  /// For v0.6, paymaster data is combined into a single `paymasterAndData` field
  /// that concatenates the paymaster address (20 bytes) with the paymaster data.
  UserOperationV06 withPaymasterStubV06(PaymasterStubData stub) {
    // v0.6 format: paymasterAndData = paymaster (20 bytes) + paymasterData
    final paymasterAndData =
        Hex.concat([stub.paymaster.hex, stub.paymasterData]);
    return copyWith(paymasterAndData: paymasterAndData);
  }

  /// Applies final paymaster data for submission.
  ///
  /// For v0.6, paymaster data is combined into a single `paymasterAndData` field
  /// that concatenates the paymaster address (20 bytes) with the paymaster data.
  UserOperationV06 withPaymasterDataV06(PaymasterData data) {
    // v0.6 format: paymasterAndData = paymaster (20 bytes) + paymasterData
    final paymasterAndData =
        Hex.concat([data.paymaster.hex, data.paymasterData]);
    return copyWith(paymasterAndData: paymasterAndData);
  }

  /// Applies sponsored UserOperation result.
  ///
  /// For v0.6, this applies the paymaster data and gas estimates from
  /// a sponsorUserOperation call.
  UserOperationV06 withSponsorshipV06(SponsorUserOperationResult result) {
    // v0.6 format: paymasterAndData = paymaster (20 bytes) + paymasterData
    final paymasterAndData =
        Hex.concat([result.paymaster.hex, result.paymasterData]);
    return copyWith(
      paymasterAndData: paymasterAndData,
      preVerificationGas: result.preVerificationGas ?? preVerificationGas,
      verificationGasLimit: result.verificationGasLimit ?? verificationGasLimit,
      callGasLimit: result.callGasLimit ?? callGasLimit,
    );
  }
}
