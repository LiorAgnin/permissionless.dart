import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('GasSpeed', () {
    test('has three speed tiers', () {
      expect(GasSpeed.values, hasLength(3));
      expect(GasSpeed.values, contains(GasSpeed.slow));
      expect(GasSpeed.values, contains(GasSpeed.standard));
      expect(GasSpeed.values, contains(GasSpeed.fast));
    });
  });

  group('GasMultipliers', () {
    test('default multipliers are 1.1x for most limits', () {
      const multipliers = GasMultipliers.standard;
      expect(multipliers.verificationGasLimit, equals(1.1));
      expect(multipliers.callGasLimit, equals(1.1));
      expect(multipliers.preVerificationGas, equals(1.0));
      expect(multipliers.paymasterVerificationGasLimit, equals(1.1));
      expect(multipliers.paymasterPostOpGasLimit, equals(1.1));
    });

    test('none preset has all 1.0x multipliers', () {
      expect(GasMultipliers.none.verificationGasLimit, equals(1.0));
      expect(GasMultipliers.none.callGasLimit, equals(1.0));
      expect(GasMultipliers.none.preVerificationGas, equals(1.0));
      expect(GasMultipliers.none.paymasterVerificationGasLimit, equals(1.0));
      expect(GasMultipliers.none.paymasterPostOpGasLimit, equals(1.0));
    });

    test('standard preset matches default', () {
      expect(GasMultipliers.standard.verificationGasLimit, equals(1.1));
      expect(GasMultipliers.standard.callGasLimit, equals(1.1));
    });

    test('conservative preset has larger buffers', () {
      expect(GasMultipliers.conservative.verificationGasLimit, equals(1.3));
      expect(GasMultipliers.conservative.callGasLimit, equals(1.2));
      expect(GasMultipliers.conservative.preVerificationGas, equals(1.1));
      expect(
        GasMultipliers.conservative.paymasterVerificationGasLimit,
        equals(1.3),
      );
      expect(GasMultipliers.conservative.paymasterPostOpGasLimit, equals(1.2));
    });

    test('can create custom multipliers', () {
      const custom = GasMultipliers(
        verificationGasLimit: 1.5,
        callGasLimit: 1.25,
        preVerificationGas: 1.15,
        paymasterVerificationGasLimit: 1.4,
        paymasterPostOpGasLimit: 1.35,
      );
      expect(custom.verificationGasLimit, equals(1.5));
      expect(custom.callGasLimit, equals(1.25));
      expect(custom.preVerificationGas, equals(1.15));
      expect(custom.paymasterVerificationGasLimit, equals(1.4));
      expect(custom.paymasterPostOpGasLimit, equals(1.35));
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
    test('stores maxFeePerGas and maxPriorityFeePerGas', () {
      final fees = FeeEstimate(
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      expect(fees.maxFeePerGas, equals(BigInt.from(50000000000)));
      expect(fees.maxPriorityFeePerGas, equals(BigInt.from(2000000000)));
    });

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

    test('toString returns readable format', () {
      final fees = FeeEstimate(
        maxFeePerGas: BigInt.from(50000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      expect(
        fees.toString(),
        equals('FeeEstimate(maxFee: 50000000000, maxPriority: 2000000000)'),
      );
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

    test('toString returns readable format', () {
      final cost = GasCostEstimate(
        totalGasLimit: BigInt.from(350000),
        maxGasCost: BigInt.from(17500000000000000),
      );

      expect(
        cost.toString(),
        equals('GasCostEstimate(totalGas: 350000, maxCost: 17500000000000000)'),
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

      // Should be approximately 15% more
      // 33333333333 * 1.15 ≈ 38333333333
      expect(boosted.maxFeePerGas, greaterThan(BigInt.from(38000000000)));
      expect(boosted.maxFeePerGas, lessThan(BigInt.from(39000000000)));
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

    test('extracts address from paymasterAndData', () {
      // Paymaster address + paymaster data
      const paymasterAndData = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
          'deadbeefcafe';

      final address =
          getAddressFromInitCodeOrPaymasterAndData(paymasterAndData);

      expect(address, isNotNull);
      expect(
        address!.hex.toLowerCase(),
        equals('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
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

    test('handles checksummed addresses', () {
      // Checksummed address with additional data
      const initCode = '0x5FbDB2315678afecb367f032d93F642f64180aa3'
          'aabbccdd';

      final address = getAddressFromInitCodeOrPaymasterAndData(initCode);

      expect(address, isNotNull);
      // EthereumAddress normalizes to lowercase
      expect(
        address!.hex.toLowerCase(),
        equals('0x5fbdb2315678afecb367f032d93f642f64180aa3'),
      );
    });

    test('works with real-world v0.6 initCode format', () {
      // v0.6 initCode: factory (20 bytes) + createAccount call data
      const initCode =
          '0x9406cc6185a346906296840746125a0e44976454' // Safe factory
          '1688f0b9' // createAccount selector
          '0000000000000000000000001234567890123456789012345678901234567890'; // owner

      final address = getAddressFromInitCodeOrPaymasterAndData(initCode);

      expect(address, isNotNull);
      expect(
        address!.hex.toLowerCase(),
        equals('0x9406cc6185a346906296840746125a0e44976454'),
      );
    });

    test('works with real-world v0.6 paymasterAndData format', () {
      // v0.6 paymasterAndData: paymaster (20 bytes) + verification + signature
      const paymasterAndData =
          '0x0000000071727de22e5e9d8baf0edac6f37da032' // Verifying paymaster
          '00000000000000000000000000000000000000000000000000000000669e9740' // valid until
          '00000000000000000000000000000000000000000000000000000000669e8740' // valid after
          'deadbeef'; // signature stub

      final address =
          getAddressFromInitCodeOrPaymasterAndData(paymasterAndData);

      expect(address, isNotNull);
      expect(
        address!.hex.toLowerCase(),
        equals('0x0000000071727de22e5e9d8baf0edac6f37da032'),
      );
    });
  });
}
