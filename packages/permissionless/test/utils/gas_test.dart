import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('GasMultipliers.standard', () {
    // Documented as a 10% buffer on every limit except preVerificationGas.
    test('adds 10% to every limit but preVerificationGas', () {
      final buffered = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
        paymasterVerificationGasLimit: BigInt.from(30000),
        paymasterPostOpGasLimit: BigInt.from(40000),
      ).withMultipliers(GasMultipliers.standard);

      expect(buffered.preVerificationGas, equals(BigInt.from(50000)));
      expect(buffered.verificationGasLimit, equals(BigInt.from(110000)));
      expect(buffered.callGasLimit, equals(BigInt.from(220000)));
      expect(
        buffered.paymasterVerificationGasLimit,
        equals(BigInt.from(33000)),
      );
      expect(buffered.paymasterPostOpGasLimit, equals(BigInt.from(44000)));
    });
  });

  group('UserOperationGasEstimate.withMultipliers', () {
    test('applies multipliers to all gas fields', () {
      final estimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        callGasLimit: BigInt.from(300000),
      );

      const multipliers = GasMultipliers(
        preVerificationGas: 1.2,
        verificationGasLimit: 1.3,
        callGasLimit: 1.1,
      );

      final buffered = estimate.withMultipliers(multipliers);

      expect(buffered.preVerificationGas, equals(BigInt.from(120000)));
      expect(buffered.verificationGasLimit, equals(BigInt.from(260000)));
      expect(buffered.callGasLimit, equals(BigInt.from(330000)));
    });

    test('applies multipliers to paymaster gas limits when present', () {
      final estimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
        paymasterVerificationGasLimit: BigInt.from(100000),
        paymasterPostOpGasLimit: BigInt.from(50000),
      );

      final buffered = estimate.withMultipliers(GasMultipliers.conservative);

      expect(
        buffered.paymasterVerificationGasLimit,
        equals(BigInt.from(130000)),
      );
      expect(buffered.paymasterPostOpGasLimit, equals(BigInt.from(60000)));
    });

    test('preserves null paymaster gas limits', () {
      final estimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
      );

      final buffered = estimate.withMultipliers(GasMultipliers.standard);

      expect(buffered.paymasterVerificationGasLimit, isNull);
      expect(buffered.paymasterPostOpGasLimit, isNull);
    });

    test('1.0x multiplier returns same value', () {
      final estimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
      );

      final buffered = estimate.withMultipliers(GasMultipliers.none);

      expect(buffered.preVerificationGas, equals(BigInt.from(50000)));
      expect(buffered.verificationGasLimit, equals(BigInt.from(100000)));
      expect(buffered.callGasLimit, equals(BigInt.from(200000)));
    });
  });

  // Deprecated (no longer used by SmartAccountClient), kept until removal.
  group('UserOperationGasEstimate.withMinimumVerificationGas', () {
    final estimate = UserOperationGasEstimate(
      preVerificationGas: BigInt.from(50000),
      verificationGasLimit: BigInt.from(135476),
      callGasLimit: BigInt.from(45619),
    );

    test('raises verificationGasLimit to 900k by default', () {
      // ignore: deprecated_member_use_from_same_package
      final floored = estimate.withMinimumVerificationGas();

      expect(floored.verificationGasLimit, equals(BigInt.from(900000)));
      expect(floored.preVerificationGas, equals(estimate.preVerificationGas));
      expect(floored.callGasLimit, equals(estimate.callGasLimit));
    });

    test('keeps a verificationGasLimit already at or above the minimum', () {
      final high = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(945021),
        callGasLimit: BigInt.from(45619),
      );

      expect(
        // ignore: deprecated_member_use_from_same_package
        high.withMinimumVerificationGas().verificationGasLimit,
        equals(BigInt.from(945021)),
      );
    });

    test('uses a custom minimum', () {
      expect(
        estimate
            // ignore: deprecated_member_use_from_same_package
            .withMinimumVerificationGas(minimum: BigInt.from(200000))
            .verificationGasLimit,
        equals(BigInt.from(200000)),
      );
    });
  });

  group('UserOperationGasEstimate.totalGasLimit', () {
    test('sums basic gas limits', () {
      final estimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
      );

      expect(estimate.totalGasLimit, equals(BigInt.from(350000)));
    });

    test('includes paymaster gas limits when present', () {
      final estimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
        paymasterVerificationGasLimit: BigInt.from(75000),
        paymasterPostOpGasLimit: BigInt.from(25000),
      );

      expect(estimate.totalGasLimit, equals(BigInt.from(450000)));
    });
  });

  group('FeeEstimate', () {
    test('withMultiplier applies to both fees', () {
      final fees = FeeEstimate(
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      final boosted = fees.withMultiplier(1.2);

      expect(boosted.maxFeePerGas, equals(BigInt.from(60000000000)));
      expect(boosted.maxPriorityFeePerGas, equals(BigInt.from(2400000000)));
    });

    test('withMultiplier with 1.0 returns same values', () {
      final fees = FeeEstimate(
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      final same = fees.withMultiplier(1);

      expect(same.maxFeePerGas, equals(fees.maxFeePerGas));
      expect(same.maxPriorityFeePerGas, equals(fees.maxPriorityFeePerGas));
    });
  });

  group('GasCostEstimate', () {
    test('calculate computes total gas and max cost', () {
      final gasEstimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
      );

      final maxFeePerGas = BigInt.from(50000000000); // 50 gwei

      final cost = GasCostEstimate.calculate(
        gasEstimate: gasEstimate,
        maxFeePerGas: maxFeePerGas,
      );

      expect(cost.totalGasLimit, equals(BigInt.from(350000)));
      expect(
        cost.maxGasCost,
        equals(BigInt.from(350000) * BigInt.from(50000000000)),
      );
    });

    test('calculate includes paymaster gas', () {
      final gasEstimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.from(50000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(200000),
        paymasterVerificationGasLimit: BigInt.from(75000),
        paymasterPostOpGasLimit: BigInt.from(25000),
      );

      final maxFeePerGas = BigInt.from(50000000000);

      final cost = GasCostEstimate.calculate(
        gasEstimate: gasEstimate,
        maxFeePerGas: maxFeePerGas,
      );

      expect(cost.totalGasLimit, equals(BigInt.from(450000)));
      expect(
        cost.maxGasCost,
        equals(BigInt.from(450000) * BigInt.from(50000000000)),
      );
    });
  });

  group('getRequiredPrefund (v0.7)', () {
    test('calculates prefund for basic UserOperation', () {
      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(50000000000), // 50 gwei
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      final prefund = getRequiredPrefund(userOp);

      // requiredGas = 200000 + 100000 + 50000 = 350000
      // prefund = 350000 * 50 gwei = 17,500,000,000,000,000 wei
      expect(prefund, equals(BigInt.from(350000) * BigInt.from(50000000000)));
    });

    test('includes paymaster gas limits when present', () {
      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
        paymaster: EthereumAddress.fromHex(
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        paymasterVerificationGasLimit: BigInt.from(75000),
        paymasterPostOpGasLimit: BigInt.from(25000),
      );

      final prefund = getRequiredPrefund(userOp);

      // requiredGas = 200000 + 100000 + 50000 + 75000 + 25000 = 450000
      expect(prefund, equals(BigInt.from(450000) * BigInt.from(50000000000)));
    });

    test('handles large gas values without overflow', () {
      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.parse('10000000000'),
        verificationGasLimit: BigInt.parse('5000000000'),
        preVerificationGas: BigInt.parse('1000000000'),
        maxFeePerGas: BigInt.parse('100000000000'), // 100 gwei
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      final prefund = getRequiredPrefund(userOp);

      // requiredGas = 16,000,000,000
      // prefund = 16,000,000,000 * 100 gwei = 1,600,000,000,000,000,000,000 wei
      expect(
        prefund,
        equals(BigInt.parse('16000000000') * BigInt.parse('100000000000')),
      );
    });
  });

  group('getRequiredPrefundV06 (v0.6)', () {
    test('calculates prefund without paymaster', () {
      final userOp = UserOperationV06(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      final prefund = getRequiredPrefundV06(userOp);

      // Without paymaster: multiplier = 1
      // requiredGas = 100000 + (200000 * 1) + 50000 = 350000
      expect(prefund, equals(BigInt.from(350000) * BigInt.from(50000000000)));
    });

    test('uses 3x multiplier with paymaster', () {
      final userOp = UserOperationV06(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
        paymasterAndData: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000',
      );

      final prefund = getRequiredPrefundV06(userOp);

      // With paymaster: multiplier = 3
      // requiredGas = 100000 + (200000 * 3) + 50000 = 750000
      expect(prefund, equals(BigInt.from(750000) * BigInt.from(50000000000)));
    });

    test('treats empty paymasterAndData as no paymaster', () {
      final userOp = UserOperationV06(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
        paymasterAndData: '0x', // Empty
      );

      final prefund = getRequiredPrefundV06(userOp);

      // Should use multiplier of 1 (no paymaster)
      expect(prefund, equals(BigInt.from(350000) * BigInt.from(50000000000)));
    });
  });

  group('Multiplier precision', () {
    test('handles large values without overflow', () {
      final estimate = UserOperationGasEstimate(
        preVerificationGas: BigInt.parse('1000000000000'),
        verificationGasLimit: BigInt.parse('2000000000000'),
        callGasLimit: BigInt.parse('3000000000000'),
      );

      final buffered = estimate.withMultipliers(GasMultipliers.conservative);

      expect(
        buffered.preVerificationGas,
        equals(BigInt.parse('1100000000000')),
      );
      expect(
        buffered.verificationGasLimit,
        equals(BigInt.parse('2600000000000')),
      );
      expect(
        buffered.callGasLimit,
        equals(BigInt.parse('3600000000000')),
      );
    });

    test('handles fractional multipliers accurately', () {
      final fees = FeeEstimate(
        maxFeePerGas: BigInt.from(33333333333),
        maxPriorityFeePerGas: BigInt.from(1111111111),
      );

      final boosted = fees.withMultiplier(1.15);

      // Whole wei, truncated: 33333333333 * 1.15 = 38333333332.95 and
      // 1111111111 * 1.15 = 1277777777.65.
      expect(boosted.maxFeePerGas, equals(BigInt.from(38333333332)));
      expect(boosted.maxPriorityFeePerGas, equals(BigInt.from(1277777777)));
    });
  });

  group('getAddressFromInitCodeOrPaymasterAndData', () {
    test('extracts address from initCode', () {
      // Factory address + factory data
      const initCode = '0x5fbfb9cf5de2e8c24a07e5c6a3e8d2a1bac56e7f'
          '1234567890abcdef';

      final address = getAddressFromInitCodeOrPaymasterAndData(initCode);

      expect(address, isNotNull);
      expect(
        address!.hex.toLowerCase(),
        equals('0x5fbfb9cf5de2e8c24a07e5c6a3e8d2a1bac56e7f'),
      );
    });

    test('extracts address from exact 20 bytes (address only)', () {
      const data = '0x1234567890123456789012345678901234567890';

      final address = getAddressFromInitCodeOrPaymasterAndData(data);

      expect(address, isNotNull);
      expect(
        address!.hex.toLowerCase(),
        equals('0x1234567890123456789012345678901234567890'),
      );
    });

    test('returns null for null data', () {
      final address = getAddressFromInitCodeOrPaymasterAndData(null);
      expect(address, isNull);
    });

    test('returns null for empty string', () {
      final address = getAddressFromInitCodeOrPaymasterAndData('');
      expect(address, isNull);
    });

    test('returns null for empty hex (0x)', () {
      final address = getAddressFromInitCodeOrPaymasterAndData('0x');
      expect(address, isNull);
    });

    test('returns null for data shorter than 20 bytes', () {
      // Only 19 bytes
      const shortData = '0x12345678901234567890123456789012345678';
      final address = getAddressFromInitCodeOrPaymasterAndData(shortData);
      expect(address, isNull);
    });

    test('returns null for invalid hex characters', () {
      // Contains invalid hex character 'z'
      const invalidHex = '0x123456789012345678901234567890123456789z';
      final address = getAddressFromInitCodeOrPaymasterAndData(invalidHex);
      expect(address, isNull);
    });
  });
}
