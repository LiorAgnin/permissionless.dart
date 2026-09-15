import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../helpers/kernel_v4_vectors.dart';

/// Encoding-level tests for the Kernel v4 module-management client actions:
/// each action must produce a **self-call** UserOperation whose inner call
/// carries the oracle-proven module-management calldata. No network — the
/// bundler and public client are mocked, and the UserOperation the client
/// would submit is captured from the mock transport.
void main() {
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
  final accountAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  final vectors = loadKernelV4Vectors();
  final mm = vectors['moduleManagement'] as Map<String, dynamic>;
  final installs =
      (mm['installs'] as List<dynamic>).cast<Map<String, dynamic>>();
  final uninstalls =
      (mm['uninstalls'] as List<dynamic>).cast<Map<String, dynamic>>();
  final executeSelector = mm['executeSelector'] as String;

  late List<Map<String, dynamic>> bundlerRequests;

  SmartAccountClient createClient() {
    bundlerRequests = [];
    final account = createKernelImmutableECDSA(
      owner: PrivateKeyOwner(testPrivateKey),
      chainId: BigInt.one,
      address: accountAddress,
    );

    final bundlerMock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bundlerRequests.add(body);
      final result = switch (body['method'] as String) {
        'eth_estimateUserOperationGas' => {
            'preVerificationGas': '0x5208',
            'verificationGasLimit': '0x186a0',
            'callGasLimit': '0x186a0',
          },
        'eth_sendUserOperation' => '0xabcdef1234567890',
        _ => null,
      };
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
        200,
      );
    });

    final publicMock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final result = switch (body['method'] as String) {
        // Deployed account: no factory data in the operation.
        'eth_getCode' => '0x6080604052',
        // getAccountNonce
        'eth_call' =>
          '0x0000000000000000000000000000000000000000000000000000000000000000',
        _ => null,
      };
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
        200,
      );
    });

    return SmartAccountClient(
      account: account,
      bundler: createBundlerClient(
        url: 'http://localhost:4337',
        entryPoint: EntryPointAddresses.v09,
        httpClient: bundlerMock,
      ),
      publicClient: PublicClient(
        rpcClient: JsonRpcClient(
          url: Uri.parse('http://localhost:8545'),
          httpClient: publicMock,
        ),
      ),
    );
  }

  /// Runs [action] and returns the inner call decoded from the submitted
  /// UserOperation, asserting it is a single self-call.
  Future<Call> captureSelfCall(
    Future<String> Function(SmartAccountClient client) action,
  ) async {
    final client = createClient();
    final hash = await action(client);
    expect(hash, '0xabcdef1234567890');

    final sendRequest = bundlerRequests
        .singleWhere((r) => r['method'] == 'eth_sendUserOperation');
    final userOp =
        (sendRequest['params'] as List<dynamic>)[0] as Map<String, dynamic>;
    expect(
      (userOp['sender'] as String).toLowerCase(),
      accountAddress.hex.toLowerCase(),
    );

    final decoded = decode7579Calls(userOp['callData'] as String);
    expect(decoded.calls, hasLength(1));
    final call = decoded.calls.single;
    expect(call.to.hex.toLowerCase(), accountAddress.hex.toLowerCase());
    expect(call.value, BigInt.zero);
    return call;
  }

  Map<String, dynamic> fixtureCase(
    List<Map<String, dynamic>> cases,
    String name,
  ) =>
      cases.singleWhere((c) => c['name'] == name);

  group('KernelV4ModuleActions', () {
    test('installKernelV4Module sends the install as a self-call', () async {
      final c = fixtureCase(installs, 'validatorSentinelHook');
      final call = await captureSelfCall(
        (client) => client.installKernelV4Module(
          KernelV4Install.validator(
            module: EthereumAddress.fromHex(c['module'] as String),
            moduleData: c['moduleData'] as String,
            hook: KernelV4HookSentinels.installedNoHook,
            allowedSelectors: [executeSelector],
          ),
          maxFeePerGas: BigInt.from(2000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
      );
      expect(call.data, c['callData']);
    });

    test('installKernelV4Modules sends the batch install as a self-call',
        () async {
      final batch = mm['batchInstall'] as Map<String, dynamic>;
      final call = await captureSelfCall(
        (client) => client.installKernelV4Modules(
          kernelV4PackagesFromCase(batch),
          maxFeePerGas: BigInt.from(2000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
      );
      expect(call.data, batch['callData']);
    });

    test('uninstallKernelV4Module sends the uninstall as a self-call',
        () async {
      final c = fixtureCase(uninstalls, 'policy');
      final call = await captureSelfCall(
        (client) => client.uninstallKernelV4Module(
          moduleType: BigInt.from(c['moduleType'] as int),
          module: EthereumAddress.fromHex(c['module'] as String),
          internalData: c['internalData'] as String,
          maxFeePerGas: BigInt.from(2000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
      );
      expect(call.data, c['callData']);
    });

    test(
        'uninstallKernelV4Permission batches policy-then-signer self-calls '
        'in contract order', () async {
      final policyCase = fixtureCase(uninstalls, 'policy');
      final signerCase = fixtureCase(uninstalls, 'signer');
      final client = createClient();
      final hash = await client.uninstallKernelV4Permission(
        permissionId: mm['permissionId'] as String,
        policies: [
          EthereumAddress.fromHex(policyCase['module'] as String),
        ],
        signer: EthereumAddress.fromHex(signerCase['module'] as String),
        maxFeePerGas: BigInt.from(2000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );
      expect(hash, '0xabcdef1234567890');

      final sendRequest = bundlerRequests
          .singleWhere((r) => r['method'] == 'eth_sendUserOperation');
      final userOp =
          (sendRequest['params'] as List<dynamic>)[0] as Map<String, dynamic>;
      final decoded = decode7579Calls(userOp['callData'] as String);
      expect(decoded.calls, hasLength(2));
      for (final call in decoded.calls) {
        expect(call.to.hex.toLowerCase(), accountAddress.hex.toLowerCase());
      }
      // The exact oracle-executed order: the permission's policy first,
      // its signer last.
      expect(decoded.calls[0].data, policyCase['callData']);
      expect(decoded.calls[1].data, signerCase['callData']);
    });

    test('setKernelV4Root sends the rotation as a self-call', () async {
      final c = mm['setRootRotate'] as Map<String, dynamic>;
      final call = await captureSelfCall(
        (client) => client.setKernelV4Root(
          packages: kernelV4PackagesFromCase(c),
          removeCurrent: c['removeCurrent'] as bool,
          uninstallData: c['uninstallData'] as String,
          maxFeePerGas: BigInt.from(2000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
      );
      expect(call.data, c['callData']);
    });

    test('setKernelV4RootValidation sends setRoot(vId) as a self-call',
        () async {
      final c = mm['setRootVId'] as Map<String, dynamic>;
      final validator = EthereumAddress.fromHex(
        '0x${Hex.strip0x(c['vId'] as String).substring(2)}',
      );
      final call = await captureSelfCall(
        (client) => client.setKernelV4RootValidation(
          KernelV4Validation.validator(validator),
          maxFeePerGas: BigInt.from(2000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
      );
      expect(call.data, c['callData']);
    });

    test('grantKernelV4Access sends grantAccess as a self-call', () async {
      final c = mm['grantAccess'] as Map<String, dynamic>;
      final validator = EthereumAddress.fromHex(
        '0x${Hex.strip0x(c['vId'] as String).substring(2)}',
      );
      final call = await captureSelfCall(
        (client) => client.grantKernelV4Access(
          validation: KernelV4Validation.validator(validator),
          selectors: [executeSelector],
          maxFeePerGas: BigInt.from(2000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
      );
      expect(call.data, c['callData']);
    });
  });
}
