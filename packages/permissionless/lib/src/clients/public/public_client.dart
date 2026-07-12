import 'package:http/http.dart' as http;

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../../utils/parsing.dart';
import '../bundler/rpc_client.dart';
import 'types.dart';

/// Client for read-only Ethereum JSON-RPC operations.
///
/// Provides access to standard Ethereum RPC methods for reading
/// chain state, checking balances, and querying contracts.
///
/// Example:
/// ```dart
/// final public = createPublicClient(
///   url: 'https://eth.llamarpc.com',
/// );
///
/// // Check if account is deployed
/// final isDeployed = await public.isDeployed(accountAddress);
///
/// // Get balance
/// final balance = await public.getBalance(accountAddress);
///
/// // Get gas prices
/// final feeData = await public.getFeeData();
/// ```
class PublicClient {
  /// Creates a public client with the given RPC client.
  ///
  /// Prefer using [createPublicClient] factory function instead of
  /// calling this constructor directly, as it handles RPC client setup.
  PublicClient({
    required this.rpcClient,
  });

  /// The underlying JSON-RPC client.
  final JsonRpcClient rpcClient;

  /// Gets the bytecode at an address.
  ///
  /// Returns '0x' if no code is deployed at the address.
  Future<String> getCode(
    EthereumAddress address, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_getCode',
      [address.hex, blockTag],
    );
    return result as String;
  }

  /// Checks if an account is deployed (has code).
  ///
  /// Returns true if the address has bytecode, false otherwise.
  Future<bool> isDeployed(EthereumAddress address) async {
    final code = await getCode(address);
    return code != '0x' && code.length > 2;
  }

  /// Gets the ETH balance of an address in wei.
  Future<BigInt> getBalance(
    EthereumAddress address, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_getBalance',
      [address.hex, blockTag],
    );
    return parseBigInt(result);
  }

  /// Executes a read-only call to a contract.
  ///
  /// Returns the encoded result data.
  Future<String> call(
    Call call, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_call',
      [
        {
          'to': call.to.hex,
          'data': call.data,
          if (call.value != BigInt.zero) 'value': Hex.fromBigInt(call.value),
        },
        blockTag,
      ],
    );
    return result as String;
  }

  /// Gets the transaction count (nonce) for an EOA.
  ///
  /// Note: For smart account nonces, use [getAccountNonce] instead.
  Future<BigInt> getTransactionCount(
    EthereumAddress address, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_getTransactionCount',
      [address.hex, blockTag],
    );
    return parseBigInt(result);
  }

  /// Gets the current gas price.
  Future<BigInt> getGasPrice() async {
    final result = await rpcClient.call('eth_gasPrice');
    return parseBigInt(result);
  }

  /// Gets the current max priority fee per gas (EIP-1559).
  ///
  /// Throws if the network doesn't support EIP-1559.
  Future<BigInt> getMaxPriorityFeePerGas() async {
    final result = await rpcClient.call('eth_maxPriorityFeePerGas');
    return parseBigInt(result);
  }

  /// Gets the chain ID.
  Future<BigInt> getChainId() async {
    final result = await rpcClient.call('eth_chainId');
    return parseBigInt(result);
  }

  /// Gets gas price data for fee estimation.
  ///
  /// Returns both legacy gas price and EIP-1559 priority fee
  /// (if supported by the network).
  Future<FeeData> getFeeData() async {
    final gasPrice = await getGasPrice();

    BigInt? maxPriorityFee;
    try {
      maxPriorityFee = await getMaxPriorityFeePerGas();
    } on Exception {
      // Network might not support EIP-1559
    }

    return FeeData(
      gasPrice: gasPrice,
      maxPriorityFeePerGas: maxPriorityFee,
    );
  }

  /// Gets the ERC-4337 nonce for a smart account from the EntryPoint.
  ///
  /// The [nonceKey] parameter supports parallel nonces (defaults to 0
  /// for sequential transactions).
  ///
  /// Example:
  /// ```dart
  /// final nonce = await public.getAccountNonce(
  ///   accountAddress,
  ///   EntryPointAddresses.v07,
  /// );
  /// ```
  Future<BigInt> getAccountNonce(
    EthereumAddress account,
    EthereumAddress entryPoint, {
    BigInt? nonceKey,
  }) async {
    final key = nonceKey ?? BigInt.zero;

    // EntryPoint.getNonce(address, uint192) selector: 0x35567e1a
    final callData = Hex.concat([
      '0x35567e1a',
      _abiEncodeAddress(account),
      Hex.padLeft(Hex.fromBigInt(key), 32),
    ]);

    final result = await call(Call(to: entryPoint, data: callData));
    return parseBigInt(result);
  }

  /// Gets the counterfactual address for a smart account before deployment.
  ///
  /// Uses the Pimlico [GetSenderAddressHelper] deploy-bytecode trick (same as
  /// permissionless.js): `eth_call`s the helper **without a `to` address** so
  /// the constructor runs EntryPoint.getSenderAddress, catches the
  /// `SenderAddressResult` revert, and returns the address as normal return
  /// data. This is more node-robust than decoding revert payloads.
  ///
  /// The [initCode] is the concatenation of factory address + factory calldata.
  /// It's the same value used in UserOperation.initCode.
  ///
  /// Example:
  /// ```dart
  /// final address = await public.getSenderAddress(
  ///   initCode: factoryAddress.hex + factoryCalldata.substring(2),
  ///   entryPoint: EntryPointAddresses.v07,
  /// );
  /// print('Account will be deployed at: ${address.checksummed}');
  /// ```
  ///
  /// Throws [PublicRpcError] if the helper does not return an address.
  Future<EthereumAddress> getSenderAddress({
    required String initCode,
    required EthereumAddress entryPoint,
  }) async {
    // encodeDeployData(helperBytecode, [entryPoint, initCode])
    final deployData = Hex.concat([
      _getSenderAddressHelperBytecode,
      _encodeConstructorArgs(entryPoint, initCode),
    ]);

    // eth_call with no `to` — executes creation bytecode
    final result = await rpcClient.call(
      'eth_call',
      [
        {'data': deployData},
        'latest',
      ],
    );

    final data = result as String?;
    if (data == null || data == '0x' || Hex.strip0x(data).length < 64) {
      throw PublicRpcError(
        code: -1,
        message: 'Failed to get sender address: helper returned no data for '
            'entryPoint ${entryPoint.hex}',
      );
    }

    // decodeAbiParameters([{type: 'address'}], data)
    final clean = Hex.strip0x(data);
    final addressHex = '0x${clean.substring(clean.length - 40)}';
    return EthereumAddress.fromHex(addressHex);
  }

  /// Closes the underlying HTTP client.
  void close() => rpcClient.close();
}

/// Pimlico GetSenderAddressHelper creation bytecode.
///
/// Source: https://github.com/pimlicolabs/contracts (GetSenderAddressHelper.sol)
/// Used by permissionless.js `getSenderAddress` to convert the EntryPoint
/// `SenderAddressResult` revert into a normal eth_call return value.
const _getSenderAddressHelperBytecode =
    '0x60806040526102a28038038091610015826100ae565b6080396040816080019112610093576080516001600160a01b03811681036100935760a0516001600160401b0381116100935782609f82011215610093578060800151610061816100fc565b9361006f60405195866100d9565b81855260a082840101116100935761008e9160a0602086019101610117565b610196565b600080fd5b634e487b7160e01b600052604160045260246000fd5b6080601f91909101601f19168101906001600160401b038211908210176100d457604052565b610098565b601f909101601f19168101906001600160401b038211908210176100d457604052565b6001600160401b0381116100d457601f01601f191660200190565b60005b83811061012a5750506000910152565b818101518382015260200161011a565b6040916020825261015a8151809281602086015260208686019101610117565b601f01601f1916010190565b3d15610191573d90610177826100fc565b9161018560405193846100d9565b82523d6000602084013e565b606090565b600091908291826040516101cd816101bf6020820195639b249f6960e01b87526024830161013a565b03601f1981018352826100d9565b51925af16101d9610166565b906102485760048151116000146101f7576024015160005260206000f35b60405162461bcd60e51b8152602060048201526024808201527f67657453656e64657241646472657373206661696c656420776974686f7574206044820152636461746160e01b6064820152608490fd5b60405162461bcd60e51b815260206004820152602b60248201527f67657453656e6465724164647265737320646964206e6f74207265766572742060448201526a185cc8195e1c1958dd195960aa1b6064820152608490fdfe';

/// ABI-encodes constructor args `(address entryPoint, bytes initCode)`.
String _encodeConstructorArgs(EthereumAddress entryPoint, String initCode) {
  final initCodeHex = Hex.strip0x(initCode);
  final initCodeLength = initCodeHex.length ~/ 2;

  // Head: address (static) + offset to bytes (0x40)
  // Tail: length + data padded to 32-byte boundary
  return Hex.concat([
    _abiEncodeAddress(entryPoint),
    Hex.padLeft(Hex.fromBigInt(BigInt.from(0x40)), 32),
    Hex.padLeft(Hex.fromBigInt(BigInt.from(initCodeLength)), 32),
    '0x${_padToWordBoundary(initCodeHex)}',
  ]);
}

/// Creates a [PublicClient] from a URL.
///
/// Example:
/// ```dart
/// final public = createPublicClient(
///   url: 'https://eth.llamarpc.com',
/// );
/// ```
PublicClient createPublicClient({
  required String url,
  http.Client? httpClient,
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    PublicClient(
      rpcClient: JsonRpcClient(
        url: Uri.parse(url),
        httpClient: httpClient,
        headers: headers ?? {},
        timeout: timeout ?? const Duration(seconds: 30),
      ),
    );

/// ABI-encodes an address (left-padded to 32 bytes).
String _abiEncodeAddress(EthereumAddress address) =>
    Hex.padLeft(address.hex.substring(2), 32);

/// Pads hex data to a 32-byte (64 char) word boundary.
String _padToWordBoundary(String hexWithout0x) {
  final remainder = hexWithout0x.length % 64;
  if (remainder == 0) return hexWithout0x;
  return hexWithout0x.padRight(hexWithout0x.length + (64 - remainder), '0');
}
