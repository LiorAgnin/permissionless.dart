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
  ///
  /// When [factory] and [factoryData] are both provided, performs a
  /// **deployless call via factory** (viem `call({ factory, factoryData })`):
  /// runs creation bytecode that deploys the account via the factory and then
  /// executes [call] against the counterfactual address. Used for ERC-7579
  /// queries against undeployed accounts.
  Future<String> call(
    Call call, {
    String blockTag = 'latest',
    EthereumAddress? factory,
    String? factoryData,
  }) async {
    final Map<String, dynamic> tx;
    if (factory != null && factoryData != null) {
      // encodeDeployData(deploylessCallViaFactoryBytecode, [to, data, factory, factoryData])
      final deployData = Hex.concat([
        _deploylessCallViaFactoryBytecode,
        _encodeFactoryCallConstructorArgs(
          to: call.to,
          data: call.data,
          factory: factory,
          factoryData: factoryData,
        ),
      ]);
      // No `to` — executes creation bytecode (deployless eth_call).
      tx = {
        'data': deployData,
        if (call.value != BigInt.zero) 'value': Hex.fromBigInt(call.value),
      };
    } else {
      tx = {
        'to': call.to.hex,
        'data': call.data,
        if (call.value != BigInt.zero) 'value': Hex.fromBigInt(call.value),
      };
    }

    final result = await rpcClient.call(
      'eth_call',
      [tx, blockTag],
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

/// viem `deploylessCallViaFactoryBytecode` — constructor
/// `(address to, bytes data, address factory, bytes factoryData)`.
///
/// Source: https://github.com/wevm/viem (`src/constants/contracts.ts`)
const _deploylessCallViaFactoryBytecode =
    '0x608060405234801561001057600080fd5b506040516102c03803806102c083398101604081905261002f916101e6565b836001600160a01b03163b6000036100e457600080836001600160a01b03168360405161005c9190610270565b6000604051808303816000865af19150503d8060008114610099576040519150601f19603f3d011682016040523d82523d6000602084013e61009e565b606091505b50915091508115806100b857506001600160a01b0386163b155b156100e1578060405163101bb98d60e01b81526004016100d8919061028c565b60405180910390fd5b50505b6000808451602086016000885af16040513d6000823e81610103573d81fd5b3d81f35b80516001600160a01b038116811461011e57600080fd5b919050565b634e487b7160e01b600052604160045260246000fd5b60005b8381101561015457818101518382015260200161013c565b50506000910152565b600082601f83011261016e57600080fd5b81516001600160401b0381111561018757610187610123565b604051601f8201601f19908116603f011681016001600160401b03811182821017156101b5576101b5610123565b6040528181528382016020018510156101cd57600080fd5b6101de826020830160208701610139565b949350505050565b600080600080608085870312156101fc57600080fd5b61020585610107565b60208601519094506001600160401b0381111561022157600080fd5b61022d8782880161015d565b93505061023c60408601610107565b60608601519092506001600160401b0381111561025857600080fd5b6102648782880161015d565b91505092959194509250565b60008251610282818460208701610139565b9190910192915050565b60208152600082518060208401526102ab816040850160208701610139565b601f01601f1916919091016040019291505056fe';

/// ABI-encodes constructor args `(address to, bytes data, address factory, bytes factoryData)`.
String _encodeFactoryCallConstructorArgs({
  required EthereumAddress to,
  required String data,
  required EthereumAddress factory,
  required String factoryData,
}) {
  final dataHex = Hex.strip0x(data);
  final factoryDataHex = Hex.strip0x(factoryData);
  final dataLen = dataHex.length ~/ 2;
  final factoryDataLen = factoryDataHex.length ~/ 2;

  // Head: 4 × 32 bytes = 0x80
  // [to][offset data=0x80][factory][offset factoryData]
  const dataOffset = 0x80;
  final dataPadded = _padToWordBoundary(dataHex);
  // data section = length word (32) + padded payload
  final dataSectionBytes = 32 + (dataPadded.length ~/ 2);
  final factoryDataOffset = dataOffset + dataSectionBytes;

  final parts = <String>[
    _abiEncodeAddress(to),
    Hex.padLeft(Hex.fromBigInt(BigInt.from(dataOffset)), 32),
    _abiEncodeAddress(factory),
    Hex.padLeft(Hex.fromBigInt(BigInt.from(factoryDataOffset)), 32),
    Hex.padLeft(Hex.fromBigInt(BigInt.from(dataLen)), 32),
  ];
  if (dataPadded.isNotEmpty) {
    parts.add('0x$dataPadded');
  }
  parts.add(Hex.padLeft(Hex.fromBigInt(BigInt.from(factoryDataLen)), 32));
  if (factoryDataHex.isNotEmpty) {
    parts.add('0x${_padToWordBoundary(factoryDataHex)}');
  }
  return Hex.concat(parts);
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
