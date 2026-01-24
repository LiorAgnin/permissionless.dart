import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('ERC-20 Selectors', () {
    test('approve selector is correct', () {
      // keccak256('approve(address,uint256)')[0:4] = 0x095ea7b3
      expect(Erc20Selectors.approve, equals('0x095ea7b3'));
    });

    test('allowance selector is correct', () {
      // keccak256('allowance(address,address)')[0:4] = 0xdd62ed3e
      expect(Erc20Selectors.allowance, equals('0xdd62ed3e'));
    });

    test('balanceOf selector is correct', () {
      // keccak256('balanceOf(address)')[0:4] = 0x70a08231
      expect(Erc20Selectors.balanceOf, equals('0x70a08231'));
    });

    test('transfer selector is correct', () {
      // keccak256('transfer(address,uint256)')[0:4] = 0xa9059cbb
      expect(Erc20Selectors.transfer, equals('0xa9059cbb'));
    });

    test('transferFrom selector is correct', () {
      // keccak256('transferFrom(address,address,uint256)')[0:4] = 0x23b872dd
      expect(Erc20Selectors.transferFrom, equals('0x23b872dd'));
    });
  });

  group('encodeErc20Approve', () {
    test('encodes approve call correctly', () {
      final token =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final spender =
          EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');
      final amount = BigInt.from(1000000);

      final call = encodeErc20Approve(
        token: token,
        spender: spender,
        amount: amount,
      );

      expect(call.to.hex, equals(token.hex));
      expect(call.value, equals(BigInt.zero));

      // Check selector
      expect(call.data.substring(0, 10), equals(Erc20Selectors.approve));

      // Check it's the right length (selector + address + uint256)
      // 4 bytes selector + 32 bytes address + 32 bytes amount = 68 bytes = 138 hex chars with 0x
      expect(call.data.length, equals(2 + 8 + 64 + 64));
    });

    test('encodes maxUint256 approval', () {
      final token =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final spender =
          EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');

      final call = encodeErc20Approve(
        token: token,
        spender: spender,
        amount: maxUint256,
      );

      // Amount should be all f's (max uint256)
      expect(
        call.data.substring(74), // Last 64 chars (32 bytes)
        equals('f' * 64),
      );
    });
  });

  group('encodeErc20Transfer', () {
    test('encodes transfer call correctly', () {
      final token =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final to =
          EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');
      final amount = BigInt.from(1000000);

      final call = encodeErc20Transfer(
        token: token,
        to: to,
        amount: amount,
      );

      expect(call.to.hex, equals(token.hex));
      expect(call.value, equals(BigInt.zero));
      expect(call.data.substring(0, 10), equals(Erc20Selectors.transfer));
    });
  });

  group('encodeErc20AllowanceCall', () {
    test('encodes allowance call correctly', () {
      final owner =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final spender =
          EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');

      final callData = encodeErc20AllowanceCall(
        owner: owner,
        spender: spender,
      );

      expect(callData.substring(0, 10), equals(Erc20Selectors.allowance));
      // selector + address + address = 4 + 32 + 32 = 68 bytes
      expect(callData.length, equals(2 + 8 + 64 + 64));
    });
  });

  group('encodeErc20BalanceOfCall', () {
    test('encodes balanceOf call correctly', () {
      final account =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

      final callData = encodeErc20BalanceOfCall(account: account);

      expect(callData.substring(0, 10), equals(Erc20Selectors.balanceOf));
      // selector + address = 4 + 32 = 36 bytes
      expect(callData.length, equals(2 + 8 + 64));
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

  group('maxUint256', () {
    test('is correct value', () {
      expect(maxUint256, equals((BigInt.one << 256) - BigInt.one));
    });

    test('is maximum 256-bit value', () {
      expect(maxUint256.bitLength, equals(256));
    });
  });

  group('createPaymasterApprovalCall', () {
    test('creates approval with default maxUint256', () {
      final token =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final paymaster =
          EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');

      final call = createPaymasterApprovalCall(
        token: token,
        paymaster: paymaster,
      );

      expect(call.to.hex, equals(token.hex));
      expect(call.data.substring(0, 10), equals(Erc20Selectors.approve));
      // Last 64 chars should be maxUint256
      expect(call.data.substring(74), equals('f' * 64));
    });

    test('creates approval with custom amount', () {
      final token =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final paymaster =
          EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');
      final amount = BigInt.from(1000000);

      final call = createPaymasterApprovalCall(
        token: token,
        paymaster: paymaster,
        amount: amount,
      );

      expect(call.to.hex, equals(token.hex));
      expect(call.data.substring(0, 10), equals(Erc20Selectors.approve));
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
  });

  // =========================================================================
  // State Override Utilities Tests
  // =========================================================================

  group('ERC-20 State Override Utilities', () {
    final tokenAddress =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
    final ownerAddress =
        EthereumAddress.fromHex('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final spenderAddress =
        EthereumAddress.fromHex('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

    group('StateDiff', () {
      test('creates with slot and value', () {
        final diff = StateDiff(
          slot: '0x${'00' * 32}',
          value: '0x${'01' * 32}',
        );

        expect(diff.slot, equals('0x${'00' * 32}'));
        expect(diff.value, equals('0x${'01' * 32}'));
      });

      test('toJson returns slot-value map', () {
        const diff = StateDiff(
          slot: '0xabc123',
          value: '0xdef456',
        );

        final json = diff.toJson();
        expect(json, equals({'0xabc123': '0xdef456'}));
      });
    });

    group('StateOverride', () {
      test('creates with address only', () {
        final override = StateOverride(address: tokenAddress);

        expect(override.address, equals(tokenAddress));
        expect(override.balance, isNull);
        expect(override.nonce, isNull);
        expect(override.code, isNull);
        expect(override.stateDiff, isNull);
      });

      test('creates with all fields', () {
        final override = StateOverride(
          address: tokenAddress,
          balance: BigInt.from(1000),
          nonce: BigInt.from(5),
          code: '0x1234',
          stateDiff: [
            const StateDiff(slot: '0xabc', value: '0xdef'),
          ],
        );

        expect(override.balance, equals(BigInt.from(1000)));
        expect(override.nonce, equals(BigInt.from(5)));
        expect(override.code, equals('0x1234'));
        expect(override.stateDiff, hasLength(1));
      });

      test('toJson excludes null fields', () {
        final override = StateOverride(address: tokenAddress);
        final json = override.toJson();

        expect(json, isEmpty);
      });

      test('toJson includes balance as hex', () {
        final override = StateOverride(
          address: tokenAddress,
          balance: BigInt.from(1000), // 0x3e8
        );

        final json = override.toJson();
        expect(json['balance'], equals('0x3e8'));
      });

      test('toJson includes nonce as hex', () {
        final override = StateOverride(
          address: tokenAddress,
          nonce: BigInt.from(42), // 0x2a
        );

        final json = override.toJson();
        expect(json['nonce'], equals('0x2a'));
      });

      test('toJson includes code', () {
        final override = StateOverride(
          address: tokenAddress,
          code: '0xdeadbeef',
        );

        final json = override.toJson();
        expect(json['code'], equals('0xdeadbeef'));
      });

      test('toJson includes stateDiff as slot-value map', () {
        final override = StateOverride(
          address: tokenAddress,
          stateDiff: [
            const StateDiff(slot: '0xaaa', value: '0x111'),
            const StateDiff(slot: '0xbbb', value: '0x222'),
          ],
        );

        final json = override.toJson();
        expect(json['stateDiff'], equals({'0xaaa': '0x111', '0xbbb': '0x222'}));
      });
    });

    group('stateOverridesToJson', () {
      test('converts single override', () {
        final overrides = [
          StateOverride(
            address: tokenAddress,
            balance: BigInt.from(100),
          ),
        ];

        final json = stateOverridesToJson(overrides);

        expect(json.keys, contains(tokenAddress.hex));
        expect(json[tokenAddress.hex]['balance'], equals('0x64'));
      });

      test('converts multiple overrides', () {
        final overrides = [
          StateOverride(
            address: tokenAddress,
            balance: BigInt.from(100),
          ),
          StateOverride(
            address: ownerAddress,
            nonce: BigInt.from(10),
          ),
        ];

        final json = stateOverridesToJson(overrides);

        expect(json.keys, hasLength(2));
        expect(json.keys, contains(tokenAddress.hex));
        expect(json.keys, contains(ownerAddress.hex));
      });
    });

    group('erc20BalanceOverride', () {
      test('creates override for standard slot', () {
        final overrides = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.zero,
          balance: BigInt.from(1000000),
        );

        expect(overrides, hasLength(1));
        expect(overrides[0].address, equals(tokenAddress));
        expect(overrides[0].stateDiff, hasLength(1));
      });

      test('uses default large balance when not specified', () {
        final overrides = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.zero,
        );

        expect(overrides[0].stateDiff![0].value, startsWith('0x'));
        // Default balance is very large (32 bytes)
        final balanceHex = overrides[0].stateDiff![0].value;
        expect(balanceHex.length, equals(66)); // 0x + 64 hex chars
      });

      test('calculates different slots for different owners', () {
        final override1 = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.zero,
        );

        final override2 = erc20BalanceOverride(
          token: tokenAddress,
          owner: spenderAddress,
          slot: BigInt.zero,
        );

        expect(
          override1[0].stateDiff![0].slot,
          isNot(equals(override2[0].stateDiff![0].slot)),
        );
      });

      test('calculates different slots for different storage slots', () {
        final override1 = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.zero,
        );

        final override2 = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.one,
        );

        expect(
          override1[0].stateDiff![0].slot,
          isNot(equals(override2[0].stateDiff![0].slot)),
        );
      });

      test('same inputs produce same slot (deterministic)', () {
        final override1 = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.from(9),
          balance: BigInt.from(1000),
        );

        final override2 = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.from(9),
          balance: BigInt.from(1000),
        );

        expect(
          override1[0].stateDiff![0].slot,
          equals(override2[0].stateDiff![0].slot),
        );
        expect(
          override1[0].stateDiff![0].value,
          equals(override2[0].stateDiff![0].value),
        );
      });
    });

    group('erc20AllowanceOverride', () {
      test('creates override for allowance', () {
        final overrides = erc20AllowanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          spender: spenderAddress,
          slot: BigInt.one,
          amount: BigInt.from(1000000),
        );

        expect(overrides, hasLength(1));
        expect(overrides[0].address, equals(tokenAddress));
        expect(overrides[0].stateDiff, hasLength(1));
      });

      test('uses default max amount when not specified', () {
        final overrides = erc20AllowanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          spender: spenderAddress,
          slot: BigInt.one,
        );

        expect(overrides[0].stateDiff![0].value, startsWith('0x'));
        // Max amount is large (32 bytes)
        final amountHex = overrides[0].stateDiff![0].value;
        expect(amountHex.length, equals(66)); // 0x + 64 hex chars
      });

      test('calculates different slots for different owner/spender pairs', () {
        final override1 = erc20AllowanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          spender: spenderAddress,
          slot: BigInt.one,
        );

        final override2 = erc20AllowanceOverride(
          token: tokenAddress,
          owner: spenderAddress,
          spender: ownerAddress,
          slot: BigInt.one,
        );

        // Swapping owner and spender should produce different slots
        expect(
          override1[0].stateDiff![0].slot,
          isNot(equals(override2[0].stateDiff![0].slot)),
        );
      });

      test('same inputs produce same slot (deterministic)', () {
        final override1 = erc20AllowanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          spender: spenderAddress,
          slot: BigInt.from(10),
          amount: BigInt.from(5000),
        );

        final override2 = erc20AllowanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          spender: spenderAddress,
          slot: BigInt.from(10),
          amount: BigInt.from(5000),
        );

        expect(
          override1[0].stateDiff![0].slot,
          equals(override2[0].stateDiff![0].slot),
        );
      });
    });

    group('mergeStateOverrides', () {
      test('returns single override unchanged', () {
        final override = StateOverride(
          address: tokenAddress,
          balance: BigInt.from(100),
        );

        final merged = mergeStateOverrides([override]);

        expect(merged, hasLength(1));
        expect(merged[0].balance, equals(BigInt.from(100)));
      });

      test('merges multiple overrides for same address', () {
        final balanceOverride = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: BigInt.zero,
          balance: BigInt.from(1000),
        );

        final allowanceOverride = erc20AllowanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          spender: spenderAddress,
          slot: BigInt.one,
          amount: BigInt.from(500),
        );

        final merged = mergeStateOverrides([
          ...balanceOverride,
          ...allowanceOverride,
        ]);

        expect(merged, hasLength(1));
        expect(merged[0].address, equals(tokenAddress));
        expect(merged[0].stateDiff, hasLength(2));
      });

      test('keeps overrides for different addresses separate', () {
        final override1 = StateOverride(
          address: tokenAddress,
          balance: BigInt.from(100),
        );

        final override2 = StateOverride(
          address: ownerAddress,
          balance: BigInt.from(200),
        );

        final merged = mergeStateOverrides([override1, override2]);

        expect(merged, hasLength(2));
      });

      test('later values override earlier ones for same slot', () {
        final override1 = StateOverride(
          address: tokenAddress,
          stateDiff: [const StateDiff(slot: '0xabc', value: '0x111')],
        );

        final override2 = StateOverride(
          address: tokenAddress,
          stateDiff: [const StateDiff(slot: '0xabc', value: '0x999')],
        );

        final merged = mergeStateOverrides([override1, override2]);

        expect(merged, hasLength(1));
        expect(merged[0].stateDiff, hasLength(1));
        expect(merged[0].stateDiff![0].value, equals('0x999'));
      });
    });

    group('Erc20StorageSlots', () {
      test('provides USDC balance slot', () {
        expect(Erc20StorageSlots.usdcBalance, equals(BigInt.from(9)));
      });

      test('provides USDC allowance slot', () {
        expect(Erc20StorageSlots.usdcAllowance, equals(BigInt.from(10)));
      });

      test('provides OpenZeppelin standard slots', () {
        expect(Erc20StorageSlots.openzeppelinBalance, equals(BigInt.zero));
        expect(Erc20StorageSlots.openzeppelinAllowance, equals(BigInt.one));
      });

      test('provides USDT slots', () {
        expect(Erc20StorageSlots.usdtBalance, equals(BigInt.two));
        expect(Erc20StorageSlots.usdtAllowance, equals(BigInt.from(4)));
      });

      test('provides DAI slots', () {
        expect(Erc20StorageSlots.daiBalance, equals(BigInt.two));
        expect(Erc20StorageSlots.daiAllowance, equals(BigInt.from(3)));
      });
    });

    group('Integration with stateOverridesToJson', () {
      test('produces valid JSON for gas estimation', () {
        final balanceOverride = erc20BalanceOverride(
          token: tokenAddress,
          owner: ownerAddress,
          slot: Erc20StorageSlots.usdcBalance,
          balance: BigInt.from(1000000000), // 1000 USDC (6 decimals)
        );

        final json = stateOverridesToJson(balanceOverride);

        // Should have the token address as key
        expect(json.containsKey(tokenAddress.hex), isTrue);

        // Should have stateDiff
        final tokenOverride = json[tokenAddress.hex] as Map<String, dynamic>;
        expect(tokenOverride.containsKey('stateDiff'), isTrue);

        // stateDiff should be a map of slot -> value
        final stateDiff = tokenOverride['stateDiff'] as Map<String, String>;
        expect(stateDiff.keys, hasLength(1));

        // Slot should be 32-byte hex
        final slot = stateDiff.keys.first;
        expect(slot, startsWith('0x'));
        expect(slot.length, equals(66));

        // Value should be 32-byte hex
        final value = stateDiff.values.first;
        expect(value, startsWith('0x'));
        expect(value.length, equals(66));
      });
    });
  });
}
