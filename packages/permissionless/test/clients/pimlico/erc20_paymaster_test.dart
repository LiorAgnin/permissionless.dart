import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// ERC-20 reads against an address with no code. viem's `readContract`
/// throws `ContractFunctionZeroDataError` when `eth_call` returns `0x`;
/// a wrong-chain or mistyped token must not read as a zero balance.
void main() {
  final token =
      EthereumAddress.fromHex('0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48');
  final owner =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
  final spender =
      EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');

  // cast abi-encode "f(uint256)" 1000000
  const oneMillion =
      '0x00000000000000000000000000000000000000000000000000000000000f4240';

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
            .having((e) => e.message, 'message', contains(token.checksummed)),
      );

  group('empty return data throws StateError', () {
    final empty = publicClientReturning('0x');

    test('getTokenAllowance', () {
      expect(
        getTokenAllowance(
          publicClient: empty,
          token: token,
          owner: owner,
          spender: spender,
        ),
        noDataError('getTokenAllowance'),
      );
    });

    test('getTokenBalance', () {
      expect(
        getTokenBalance(publicClient: empty, token: token, account: owner),
        noDataError('getTokenBalance'),
      );
    });

    test('getApprovalCallIfNeeded (through getTokenAllowance)', () {
      expect(
        getApprovalCallIfNeeded(
          publicClient: empty,
          token: token,
          owner: owner,
          spender: spender,
          requiredAmount: BigInt.one,
        ),
        noDataError('getTokenAllowance'),
      );
    });
  });

  group('non-empty return data still decodes', () {
    final client = publicClientReturning(oneMillion);

    test('getTokenAllowance / getTokenBalance', () async {
      expect(
        await getTokenAllowance(
          publicClient: client,
          token: token,
          owner: owner,
          spender: spender,
        ),
        equals(BigInt.from(1000000)),
      );
      expect(
        await getTokenBalance(
          publicClient: client,
          token: token,
          account: owner,
        ),
        equals(BigInt.from(1000000)),
      );
    });

    test('getApprovalCallIfNeeded skips approval when allowance suffices',
        () async {
      expect(
        await getApprovalCallIfNeeded(
          publicClient: client,
          token: token,
          owner: owner,
          spender: spender,
          requiredAmount: BigInt.from(1000000),
        ),
        isNull,
      );
    });
  });
}
