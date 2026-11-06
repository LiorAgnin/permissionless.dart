import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  final token =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
  final spender =
      EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');

  // Expected calldata from Foundry 1.5.1, e.g.
  //   cast calldata "approve(address,uint256)" <spender> 1000000
  // (maxUint256 = `cast max-uint`).
  const approve1000000 = '0x095ea7b3'
      '000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd'
      '00000000000000000000000000000000000000000000000000000000000f4240';
  const approveMax = '0x095ea7b3'
      '000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd'
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

  // cast sig "transferFrom(address,address,uint256)"; no encoder in this
  // package builds it, so the constant is the only place it is checked.
  test('transferFrom selector is correct', () {
    expect(Erc20Selectors.transferFrom, equals('0x23b872dd'));
  });

  group('encodeErc20Approve', () {
    test('encodes approve(spender, amount) to the token', () {
      final call = encodeErc20Approve(
        token: token,
        spender: spender,
        amount: BigInt.from(1000000),
      );

      expect(call.to, equals(token));
      expect(call.value, equals(BigInt.zero));
      expect(call.data, equals(approve1000000));
    });

    test('encodes maxUint256 approval', () {
      final call = encodeErc20Approve(
        token: token,
        spender: spender,
        amount: maxUint256,
      );

      expect(call.data, equals(approveMax));
    });
  });

  group('encodeErc20Transfer', () {
    test('encodes transfer(to, amount) to the token', () {
      final call = encodeErc20Transfer(
        token: token,
        to: spender,
        amount: BigInt.from(1000000),
      );

      expect(call.to, equals(token));
      expect(call.value, equals(BigInt.zero));
      // cast calldata "transfer(address,uint256)" <spender> 1000000
      expect(
        call.data,
        equals(
          '0xa9059cbb'
          '000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd'
          '00000000000000000000000000000000000000000000000000000000000f4240',
        ),
      );
    });
  });

  group('encodeErc20AllowanceCall', () {
    test('encodes allowance(owner, spender)', () {
      // cast calldata "allowance(address,address)" <owner> <spender>
      expect(
        encodeErc20AllowanceCall(owner: token, spender: spender),
        equals(
          '0xdd62ed3e'
          '0000000000000000000000001234567890123456789012345678901234567890'
          '000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd',
        ),
      );
    });
  });

  group('encodeErc20BalanceOfCall', () {
    test('encodes balanceOf(account)', () {
      // cast calldata "balanceOf(address)" <account>
      expect(
        encodeErc20BalanceOfCall(account: token),
        equals(
          '0x70a08231'
          '0000000000000000000000001234567890123456789012345678901234567890',
        ),
      );
    });
  });

  group('decodeUint256Result', () {
    test('decodes hex result correctly', () {
      const hex =
          '0x0000000000000000000000000000000000000000000000000000000000000064';
      final result = decodeUint256Result(hex);
      expect(result, equals(BigInt.from(100)));
    });

    test('handles empty result', () {
      expect(decodeUint256Result('0x'), equals(BigInt.zero));
      expect(decodeUint256Result(''), equals(BigInt.zero));
    });

    test('handles large values', () {
      const hex =
          '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      final result = decodeUint256Result(hex);
      expect(result, equals(maxUint256));
    });
  });

  test('maxUint256 is 2^256 - 1', () {
    // cast max-uint
    expect(
      maxUint256,
      equals(
        BigInt.parse(
          '115792089237316195423570985008687907853269984665640564039457584007913129639935',
        ),
      ),
    );
  });

  group('createPaymasterApprovalCall', () {
    final paymaster = spender;

    test('approves the paymaster for maxUint256 by default', () {
      final call = createPaymasterApprovalCall(
        token: token,
        paymaster: paymaster,
      );

      expect(call.to, equals(token));
      expect(call.data, equals(approveMax));
    });

    test('approves the paymaster for a custom amount', () {
      final call = createPaymasterApprovalCall(
        token: token,
        paymaster: paymaster,
        amount: BigInt.from(1000000),
      );

      expect(call.to, equals(token));
      expect(call.data, equals(approve1000000));
    });
  });

  group('estimateTokenCost', () {
    test('estimates cost correctly', () {
      final quote = PimlicoTokenQuote(
        token: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        paymaster: EthereumAddress.fromHex(
          '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
        ),
        postOpGas: BigInt.from(75000),
        exchangeRate: BigInt.from(10).pow(18), // 1:1 rate for simplicity
        exchangeRateNativeToUsd:
            BigInt.from(2000000000), // $2000 with 6 decimals
      );

      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000), // 1 gwei
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      final tokenCost = estimateTokenCost(quote: quote, userOp: userOp);

      // Total gas = 50000 + 100000 + 100000 + 75000 = 325000
      // Cost in wei = 325000 * 1 gwei = 325000 * 10^9
      // With 1:1 exchange rate: tokenCost = 325000 * 10^9
      expect(tokenCost, equals(BigInt.from(325000) * BigInt.from(10).pow(9)));
    });

    test('charges the paymaster verification gas the EntryPoint prefunds', () {
      final quote = PimlicoTokenQuote(
        token: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        paymaster: EthereumAddress.fromHex(
          '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
        ),
        postOpGas: BigInt.from(75000),
        exchangeRate: BigInt.from(10).pow(18),
      );
      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
        paymaster: quote.paymaster,
        paymasterVerificationGasLimit: BigInt.from(40000),
        paymasterPostOpGasLimit: BigInt.from(30000),
      );

      // permissionless.js: (getRequiredPrefund(op) + postOpGas * maxFee)
      // * exchangeRate / 1e18, where the prefund covers both paymaster limits.
      const expectedGas = 50000 + 100000 + 100000 + 40000 + 30000 + 75000;
      expect(
        estimateTokenCost(quote: quote, userOp: userOp),
        BigInt.from(expectedGas) * BigInt.from(10).pow(9),
      );
    });
  });
}
