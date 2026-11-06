import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Top-level ERC-7579 reads (address only, no factory to fall back to).
///
/// An `eth_call` that returns `0x` means the target has no code. viem's
/// `readContract` throws `ContractFunctionZeroDataError` there, and the
/// permissionless.js actions retry through the factory and throw if that is
/// empty too; none of them read `0x` as `false` / `''`.
void main() {
  final account =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
  final module =
      EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');

  const boolTrue =
      '0x0000000000000000000000000000000000000000000000000000000000000001';
  // cast abi-encode "f(string)" "kernel.advanced.0.3.1"
  const accountIdResult = '0x'
      '0000000000000000000000000000000000000000000000000000000000000020'
      '0000000000000000000000000000000000000000000000000000000000000015'
      '6b65726e656c2e616476616e6365642e302e332e310000000000000000000000';

  PublicClient publicClientReturning(String result) => createPublicClient(
        url: 'http://localhost:8545',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
            200,
          );
        }),
      );

  Matcher noDataError(String function) => throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', contains(function))
            .having((e) => e.message, 'message', contains(account.checksummed)),
      );

  group('empty return data throws StateError', () {
    final empty = publicClientReturning('0x');

    test('isModuleInstalled', () {
      expect(
        isModuleInstalled(
          publicClient: empty,
          account: account,
          moduleType: Erc7579ModuleType.validator,
          module: module,
        ),
        noDataError('isModuleInstalled'),
      );
    });

    test('supportsModule', () {
      expect(
        supportsModule(
          publicClient: empty,
          account: account,
          moduleType: Erc7579ModuleType.hook,
        ),
        noDataError('supportsModule'),
      );
    });

    test('getAccountId', () {
      expect(
        getAccountId(publicClient: empty, account: account),
        noDataError('getAccountId'),
      );
    });

    test('getInstalledModulesOfType (through isModuleInstalled)', () {
      expect(
        getInstalledModulesOfType(
          publicClient: empty,
          account: account,
          moduleType: Erc7579ModuleType.validator,
          candidateModules: [module],
        ),
        noDataError('isModuleInstalled'),
      );
    });
  });

  group('non-empty return data still decodes', () {
    test('isModuleInstalled / supportsModule / getInstalledModulesOfType',
        () async {
      final client = publicClientReturning(boolTrue);
      expect(
        await isModuleInstalled(
          publicClient: client,
          account: account,
          moduleType: Erc7579ModuleType.validator,
          module: module,
        ),
        isTrue,
      );
      expect(
        await supportsModule(
          publicClient: client,
          account: account,
          moduleType: Erc7579ModuleType.hook,
        ),
        isTrue,
      );
      expect(
        await getInstalledModulesOfType(
          publicClient: client,
          account: account,
          moduleType: Erc7579ModuleType.validator,
          candidateModules: [module],
        ),
        equals([module]),
      );
    });

    test('getAccountId', () async {
      expect(
        await getAccountId(
          publicClient: publicClientReturning(accountIdResult),
          account: account,
        ),
        equals('kernel.advanced.0.3.1'),
      );
    });
  });
}
