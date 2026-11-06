import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

const _ownerKey =
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
final _sender =
    EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
final _chainId = BigInt.from(11155111);
final _recipient =
    EthereumAddress.fromHex('0x70997970C51812dc3A010C7d01b75Ec5Bb3E7DcF');

Map<String, dynamic> _receiptJson({bool success = true}) => {
      'userOpHash': '0x${'ab' * 32}',
      'sender': _sender.hex,
      'nonce': '0x0',
      'success': success,
      'actualGasCost': '0x1234',
      'actualGasUsed': '0x5678',
      'logs': <dynamic>[],
    };

http.Response _rpcResult(Map<String, dynamic> body, Object? result) =>
    http.Response(
      jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
      200,
    );

http.Response _rpcError(
  Map<String, dynamic> body, {
  required int code,
  String message = '',
  Object? data,
}) =>
    http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'error': {
          'code': code,
          'message': message,
          if (data != null) 'data': data,
        },
      }),
      200,
    );

class _Rig {
  _Rig({
    required Future<http.Response> Function(Map<String, dynamic> body) sendNow,
    List<Map<String, dynamic>?> receipts = const [],
    EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  }) {
    final receiptQueue = [...receipts];
    final bundlerHttp = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      switch (body['method']) {
        case 'pimlico_sendUserOperationNow':
          return sendNow(body);
        case 'eth_getUserOperationReceipt':
          receiptPolls++;
          return _rpcResult(
            body,
            receiptQueue.isEmpty ? null : receiptQueue.removeAt(0),
          );
        default:
          return _rpcResult(body, null);
      }
    });
    final publicHttp = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final result = switch (body['method']) {
        'eth_getCode' => '0x6080604052', // deployed: no factory
        'eth_call' => '0x${'0' * 64}', // nonce 0
        _ => null,
      };
      return _rpcResult(body, result);
    });

    account = createSimpleSmartAccount(
      owner: PrivateKeyOwner(_ownerKey),
      chainId: _chainId,
      entryPointVersion: entryPointVersion,
      address: _sender,
    );
    client = SmartAccountClient(
      account: account,
      bundler: createBundlerClient(
        url: 'http://localhost:4337',
        entryPoint: account.entryPoint,
        httpClient: bundlerHttp,
      ),
      publicClient: PublicClient(
        rpcClient: JsonRpcClient(
          url: Uri.parse('http://localhost:8545'),
          httpClient: publicHttp,
        ),
      ),
    );
  }

  late final SimpleSmartAccount account;
  late final SmartAccountClient client;
  final requests = <Map<String, dynamic>>[];
  int receiptPolls = 0;

  Map<String, dynamic> get sendNowRequest =>
      requests.firstWhere((r) => r['method'] == 'pimlico_sendUserOperationNow');

  /// Hash of the sent user operation, recomputed from the wire JSON.
  String get sentHash {
    final op = UserOperationV07.fromJson(
      sendNowRequest['params'][0] as Map<String, dynamic>,
    );
    return getUserOperationHash(
      userOperation: op,
      entryPointAddress: account.entryPoint,
      entryPointVersion: entryPointVersionOf(account.entryPoint)!,
      chainId: _chainId,
    );
  }

  /// Sends with all gas and fee fields set, so the only bundler traffic is
  /// send-now and receipt polls.
  Future<UserOperationReceipt> send({
    Duration timeout = const Duration(milliseconds: 300),
  }) =>
      client.sendUserOperationSync(
        calls: [Call(to: _recipient, value: BigInt.one)],
        maxFeePerGas: BigInt.from(3000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        timeout: timeout,
        pollingInterval: const Duration(milliseconds: 10),
      );
}

TypeMatcher<SendUserOperationSyncError> _syncError(
  SendUserOperationSyncErrorKind kind, {
  required bool canResend,
}) =>
    isA<SendUserOperationSyncError>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.canResend, 'canResend', canResend);

void main() {
  group('sendUserOperationSync', () {
    test('returns the receipt from pimlico_sendUserOperationNow', () async {
      final rig = _Rig(sendNow: (b) async => _rpcResult(b, _receiptJson()));

      final receipt = await rig.send();

      expect(receipt.success, isTrue);
      expect(receipt.sender.hex, _sender.hex);
      final params = rig.sendNowRequest['params'] as List<dynamic>;
      expect(params[1], EntryPointAddresses.v07.hex);
      final sentOp = params[0] as Map<String, dynamic>;
      expect(sentOp['sender'], _sender.hex);
      expect(sentOp['signature'], isNot(rig.account.getStubSignature()));
      expect(rig.receiptPolls, 0);
    });

    test('returns a reverted receipt instead of throwing', () async {
      final rig = _Rig(
        sendNow: (b) async => _rpcResult(b, _receiptJson(success: false)),
      );

      final receipt = await rig.send();

      expect(receipt.success, isFalse);
    });

    test('-32521 is bundle_reverted with the bundler message', () async {
      final rig = _Rig(
        sendNow: (b) async =>
            _rpcError(b, code: -32521, message: 'bundle reverted: AA95'),
      );

      final error = await rig.send().then<Object>(
            (_) => fail('expected an error'),
            onError: (Object e) => e,
          );

      expect(
        error,
        _syncError(
          SendUserOperationSyncErrorKind.bundleReverted,
          canResend: true,
        ),
      );
      error as SendUserOperationSyncError;
      expect(error.message, 'bundle reverted: AA95');
      expect(error.userOperationHash, rig.sentHash);
      expect(error.kind.value, 'bundle_reverted');
    });

    test('-32521 with an empty message uses the default message', () async {
      final rig = _Rig(sendNow: (b) async => _rpcError(b, code: -32521));

      await expectLater(
        rig.send(),
        throwsA(
          isA<SendUserOperationSyncError>().having(
            (e) => e.message,
            'message',
            startsWith('Bundle transaction reverted onchain'),
          ),
        ),
      );
    });

    test('JSON-RPC error without a tx hash is rejected, no polling', () async {
      final rig = _Rig(
        sendNow: (b) async =>
            _rpcError(b, code: -32602, message: 'AA25 invalid account nonce'),
      );

      await expectLater(
        rig.send(),
        throwsA(
          _syncError(SendUserOperationSyncErrorKind.rejected, canResend: false)
              .having(
            (e) => (e.cause! as BundlerRpcError).aaErrorCode,
            'cause.aaErrorCode',
            'AA25',
          ),
        ),
      );
      expect(rig.receiptPolls, 0);
    });

    test('error with a tx hash polls and returns a late receipt', () async {
      final rig = _Rig(
        sendNow: (b) async => _rpcError(
          b,
          code: -32602,
          data: {'transactionHash': '0x${'cd' * 32}'},
        ),
        receipts: [null, _receiptJson()],
      );

      final receipt = await rig.send();

      expect(receipt.success, isTrue);
      expect(rig.receiptPolls, 2);
    });

    test('error with a tx hash and no receipt is pending', () async {
      final rig = _Rig(
        sendNow: (b) async => _rpcError(
          b,
          code: -32602,
          data: {'transactionHash': '0x${'cd' * 32}'},
        ),
      );

      await expectLater(
        rig.send(timeout: const Duration(milliseconds: 100)),
        throwsA(
          _syncError(SendUserOperationSyncErrorKind.pending, canResend: false),
        ),
      );
      expect(rig.receiptPolls, greaterThan(0));
    });

    test('-32603 without a tx hash is not_found', () async {
      final rig = _Rig(sendNow: (b) async => _rpcError(b, code: -32603));

      await expectLater(
        rig.send(timeout: const Duration(milliseconds: 100)),
        throwsA(
          _syncError(SendUserOperationSyncErrorKind.notFound, canResend: true),
        ),
      );
      expect(rig.receiptPolls, greaterThan(0));
    });

    test('-32603 with a tx hash is pending', () async {
      final rig = _Rig(
        sendNow: (b) async => _rpcError(
          b,
          code: -32603,
          data: {'transactionHash': '0x${'cd' * 32}'},
        ),
      );

      await expectLater(
        rig.send(timeout: const Duration(milliseconds: 100)),
        throwsA(
          _syncError(SendUserOperationSyncErrorKind.pending, canResend: false),
        ),
      );
    });

    test('HTTP 502 is no answer: polls, then pending', () async {
      final rig = _Rig(
        sendNow: (b) async => http.Response('bad gateway', 502),
      );

      await expectLater(
        rig.send(timeout: const Duration(milliseconds: 100)),
        throwsA(
          _syncError(SendUserOperationSyncErrorKind.pending, canResend: false)
              .having((e) => e.cause, 'cause', isA<BundlerHttpError>()),
        ),
      );
      expect(rig.receiptPolls, greaterThan(0));
    });

    test('HTTP 502 then a receipt returns the receipt', () async {
      final rig = _Rig(
        sendNow: (b) async => http.Response('bad gateway', 502),
        receipts: [_receiptJson()],
      );

      final receipt = await rig.send();

      expect(receipt.success, isTrue);
    });

    test('null result is unclear: polls for the receipt', () async {
      final rig = _Rig(
        sendNow: (b) async => _rpcResult(b, null),
        receipts: [_receiptJson()],
      );

      final receipt = await rig.send();

      expect(receipt.success, isTrue);
      expect(rig.receiptPolls, 1);
    });

    test('no answer before the timeout is pending, without polling', () async {
      final rig = _Rig(
        sendNow: (b) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _rpcResult(b, _receiptJson());
        },
      );

      await expectLater(
        rig.send(timeout: const Duration(milliseconds: 50)),
        throwsA(
          _syncError(SendUserOperationSyncErrorKind.pending, canResend: false)
              .having((e) => e.cause, 'cause', isNull),
        ),
      );
      expect(rig.receiptPolls, 0);
    });

    test('v0.8 sends to the v0.8 EntryPoint and hashes with EIP-712', () async {
      final rig = _Rig(
        sendNow: (b) async => _rpcError(b, code: -32602),
        entryPointVersion: EntryPointVersion.v08,
      );

      final error = await rig.send().then<Object>(
            (_) => fail('expected an error'),
            onError: (Object e) => e,
          );

      expect(
        (rig.sendNowRequest['params'] as List<dynamic>)[1],
        EntryPointAddresses.v08.hex,
      );
      expect(
        (error as SendUserOperationSyncError).userOperationHash,
        rig.sentHash,
      );
    });

    test('v0.6 accounts are unsupported', () async {
      final rig = _Rig(
        sendNow: (b) async => _rpcResult(b, _receiptJson()),
        entryPointVersion: EntryPointVersion.v06,
      );

      await expectLater(rig.send(), throwsUnsupportedError);
      expect(rig.requests, isEmpty);
    });
  });
}
