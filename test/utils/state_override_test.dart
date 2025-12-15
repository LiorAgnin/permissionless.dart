import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('erc20BalanceOverride', () {
    test('returns correct structure for valid inputs', () {
      final token = EthAddress('0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF');
      final owner = EthAddress('0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE');
      final slot = BigInt.one;
      final balance = BigInt.from(1000);

      final result = erc20BalanceOverride(
        token: token,
        owner: owner,
        slot: slot,
        balance: balance,
      );

      expect(result.length, equals(1));
      expect(
        result[0].address.hex.toLowerCase(),
        equals(token.hex.toLowerCase()),
      );
      expect(result[0].stateDiff, isNotNull);
      expect(result[0].stateDiff!.length, equals(1));

      // Slot should be a 32-byte hex string (keccak256 hash)
      expect(
        result[0].stateDiff![0].slot.length,
        equals(66),
      ); // 0x + 64 hex chars
      expect(result[0].stateDiff![0].slot.startsWith('0x'), isTrue);

      // Value should be the balance as hex
      expect(
        result[0].stateDiff![0].value,
        equals(Hex.fromBigInt(balance, byteLength: 32)),
      );
    });

    test('uses default balance when none provided', () {
      final token = EthAddress('0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF');
      final owner = EthAddress('0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE');
      final slot = BigInt.one;

      final result = erc20BalanceOverride(
        token: token,
        owner: owner,
        slot: slot,
      );

      final expectedDefaultBalance = BigInt.parse(
        '100000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        radix: 16,
      );

      expect(result.length, equals(1));
      expect(
        result[0].stateDiff![0].value,
        equals(Hex.fromBigInt(expectedDefaultBalance, byteLength: 32)),
      );
    });

    test('computes deterministic storage slot', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner = EthAddress('0x1234567890123456789012345678901234567890');
      final slot = BigInt.zero;

      final result = erc20BalanceOverride(
        token: token,
        owner: owner,
        slot: slot,
      );

      // Verify the slot is deterministic
      final result2 = erc20BalanceOverride(
        token: token,
        owner: owner,
        slot: slot,
      );

      expect(
        result[0].stateDiff![0].slot,
        equals(result2[0].stateDiff![0].slot),
      );
    });

    test('different owners produce different slots', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner1 = EthAddress('0x1111111111111111111111111111111111111111');
      final owner2 = EthAddress('0x2222222222222222222222222222222222222222');
      final slot = BigInt.zero;

      final result1 = erc20BalanceOverride(
        token: token,
        owner: owner1,
        slot: slot,
      );

      final result2 = erc20BalanceOverride(
        token: token,
        owner: owner2,
        slot: slot,
      );

      expect(
        result1[0].stateDiff![0].slot,
        isNot(equals(result2[0].stateDiff![0].slot)),
      );
    });
  });

  group('erc20AllowanceOverride', () {
    test('returns correct structure for valid inputs', () {
      final token = EthAddress('0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF');
      final owner = EthAddress('0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE');
      final spender = EthAddress('0xDDdDddDdDdddDDddDDddDDDDdDdDDdDDdDDDDDDd');
      final slot = BigInt.one;
      final amount = BigInt.from(100);

      final result = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: spender,
        slot: slot,
        amount: amount,
      );

      expect(result.length, equals(1));
      expect(
        result[0].address.hex.toLowerCase(),
        equals(token.hex.toLowerCase()),
      );
      expect(result[0].stateDiff, isNotNull);
      expect(result[0].stateDiff!.length, equals(1));

      // Slot should be a 32-byte hex string (keccak256 hash)
      expect(
        result[0].stateDiff![0].slot.length,
        equals(66),
      ); // 0x + 64 hex chars
      expect(result[0].stateDiff![0].slot.startsWith('0x'), isTrue);

      // Value should be the amount as hex
      expect(
        result[0].stateDiff![0].value,
        equals(Hex.fromBigInt(amount, byteLength: 32)),
      );
    });

    test('uses default amount when none provided', () {
      final token = EthAddress('0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF');
      final owner = EthAddress('0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE');
      final spender = EthAddress('0xDDdDddDdDdddDDddDDddDDDDdDdDDdDDdDDDDDDd');
      final slot = BigInt.one;

      final result = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: spender,
        slot: slot,
      );

      final expectedDefaultAmount = BigInt.parse(
        '7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        radix: 16,
      );

      expect(result.length, equals(1));
      expect(
        result[0].stateDiff![0].value,
        equals(Hex.fromBigInt(expectedDefaultAmount, byteLength: 32)),
      );
    });

    test('computes deterministic storage slot for nested mapping', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner = EthAddress('0x1111111111111111111111111111111111111111');
      final spender = EthAddress('0x2222222222222222222222222222222222222222');
      final slot = BigInt.one;

      final result = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: spender,
        slot: slot,
      );

      // Verify slot is deterministic
      final result2 = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: spender,
        slot: slot,
      );

      expect(
        result[0].stateDiff![0].slot,
        equals(result2[0].stateDiff![0].slot),
      );
    });

    test('different spenders produce different slots', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner = EthAddress('0x1111111111111111111111111111111111111111');
      final spender1 = EthAddress('0x2222222222222222222222222222222222222222');
      final spender2 = EthAddress('0x3333333333333333333333333333333333333333');
      final slot = BigInt.one;

      final result1 = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: spender1,
        slot: slot,
      );

      final result2 = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: spender2,
        slot: slot,
      );

      expect(
        result1[0].stateDiff![0].slot,
        isNot(equals(result2[0].stateDiff![0].slot)),
      );
    });

    test('allowance slot differs from balance slot', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner = EthAddress('0x1111111111111111111111111111111111111111');
      final slot = BigInt.zero;

      final balanceResult = erc20BalanceOverride(
        token: token,
        owner: owner,
        slot: slot,
      );

      final allowanceResult = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: owner, // Same as owner for simplicity
        slot: slot,
      );

      // Even with same owner, balance and allowance slots should differ
      // because allowance uses nested hash
      expect(
        balanceResult[0].stateDiff![0].slot,
        isNot(equals(allowanceResult[0].stateDiff![0].slot)),
      );
    });
  });

  group('erc20PaymasterOverride', () {
    test('creates combined balance and allowance overrides', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner = EthAddress('0x1111111111111111111111111111111111111111');
      final spender = EthAddress('0x2222222222222222222222222222222222222222');
      final balanceSlot = BigInt.zero;
      final allowanceSlot = BigInt.one;

      final result = erc20PaymasterOverride(
        token: token,
        owner: owner,
        spender: spender,
        balanceSlot: balanceSlot,
        allowanceSlot: allowanceSlot,
      );

      expect(result.length, equals(1));
      expect(
        result[0].address.hex.toLowerCase(),
        equals(token.hex.toLowerCase()),
      );
      expect(result[0].stateDiff, isNotNull);
      expect(
        result[0].stateDiff!.length,
        equals(2),
      ); // Both balance and allowance

      // Both slots should be different
      expect(
        result[0].stateDiff![0].slot,
        isNot(equals(result[0].stateDiff![1].slot)),
      );
    });

    test('uses custom balance and allowance values', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner = EthAddress('0x1111111111111111111111111111111111111111');
      final spender = EthAddress('0x2222222222222222222222222222222222222222');
      final balance = BigInt.from(1000000);
      final allowance = BigInt.from(500000);

      final result = erc20PaymasterOverride(
        token: token,
        owner: owner,
        spender: spender,
        balanceSlot: BigInt.zero,
        allowanceSlot: BigInt.one,
        balance: balance,
        allowance: allowance,
      );

      // Verify both values are present (order may vary after merge)
      final values = result[0].stateDiff!.map((d) => d.value).toSet();
      expect(
        values.contains(Hex.fromBigInt(balance, byteLength: 32)),
        isTrue,
      );
      expect(
        values.contains(Hex.fromBigInt(allowance, byteLength: 32)),
        isTrue,
      );
    });
  });

  group('mergeStateOverrides', () {
    test('merges overrides for different addresses', () {
      final token1 = EthAddress('0x1111111111111111111111111111111111111111');
      final token2 = EthAddress('0x2222222222222222222222222222222222222222');
      final owner = EthAddress('0x3333333333333333333333333333333333333333');

      final override1 = erc20BalanceOverride(
        token: token1,
        owner: owner,
        slot: BigInt.zero,
        balance: BigInt.from(1000),
      );

      final override2 = erc20BalanceOverride(
        token: token2,
        owner: owner,
        slot: BigInt.zero,
        balance: BigInt.from(2000),
      );

      final merged = mergeStateOverrides([...override1, ...override2]);

      expect(merged.length, equals(2));
    });

    test('merges stateDiffs for same address', () {
      final token = EthAddress('0x1111111111111111111111111111111111111111');
      final owner = EthAddress('0x2222222222222222222222222222222222222222');
      final spender = EthAddress('0x3333333333333333333333333333333333333333');

      final balanceOverride = erc20BalanceOverride(
        token: token,
        owner: owner,
        slot: BigInt.zero,
      );

      final allowanceOverride = erc20AllowanceOverride(
        token: token,
        owner: owner,
        spender: spender,
        slot: BigInt.one,
      );

      final merged =
          mergeStateOverrides([...balanceOverride, ...allowanceOverride]);

      expect(merged.length, equals(1)); // Same token, merged into one
      expect(
        merged[0].stateDiff!.length,
        equals(2),
      ); // Both balance and allowance slots
    });
  });

  group('stateOverridesToJson', () {
    test('converts override to JSON format', () {
      final token = EthAddress('0x1234567890123456789012345678901234567890');
      final owner = EthAddress('0x1111111111111111111111111111111111111111');

      final override = erc20BalanceOverride(
        token: token,
        owner: owner,
        slot: BigInt.zero,
        balance: BigInt.from(1000),
      );

      final json = stateOverridesToJson(override);

      expect(json, isA<Map<String, dynamic>>());
      expect(json.containsKey(token.hex), isTrue);

      final tokenOverride = json[token.hex] as Map<String, dynamic>;
      expect(tokenOverride.containsKey('stateDiff'), isTrue);
    });
  });

  group('StateOverride', () {
    test('toJson includes all fields when set', () {
      final override = StateOverride(
        address: EthAddress('0x1234567890123456789012345678901234567890'),
        balance: BigInt.from(1000),
        nonce: BigInt.from(5),
        code: '0x1234',
        stateDiff: [
          const StateDiff(
            slot:
                '0x0000000000000000000000000000000000000000000000000000000000000000',
            value:
                '0x0000000000000000000000000000000000000000000000000000000000000001',
          ),
        ],
      );

      final json = override.toJson();

      expect(json['balance'], isNotNull);
      expect(json['nonce'], isNotNull);
      expect(json['code'], equals('0x1234'));
      expect(json['stateDiff'], isNotNull);
    });

    test('toJson excludes null fields', () {
      final override = StateOverride(
        address: EthAddress('0x1234567890123456789012345678901234567890'),
      );

      final json = override.toJson();

      expect(json.containsKey('balance'), isFalse);
      expect(json.containsKey('nonce'), isFalse);
      expect(json.containsKey('code'), isFalse);
      expect(json.containsKey('stateDiff'), isFalse);
    });
  });

  group('Erc20StorageSlots', () {
    test('has correct USDC slots', () {
      expect(Erc20StorageSlots.usdcBalance, equals(BigInt.from(9)));
      expect(Erc20StorageSlots.usdcAllowance, equals(BigInt.from(10)));
    });

    test('has correct USDT slots', () {
      expect(Erc20StorageSlots.usdtBalance, equals(BigInt.two));
      expect(Erc20StorageSlots.usdtAllowance, equals(BigInt.from(4)));
    });

    test('has correct DAI slots', () {
      expect(Erc20StorageSlots.daiBalance, equals(BigInt.two));
      expect(Erc20StorageSlots.daiAllowance, equals(BigInt.from(3)));
    });

    test('has correct OpenZeppelin slots', () {
      expect(Erc20StorageSlots.openzeppelinBalance, equals(BigInt.zero));
      expect(Erc20StorageSlots.openzeppelinAllowance, equals(BigInt.one));
    });
  });
}
