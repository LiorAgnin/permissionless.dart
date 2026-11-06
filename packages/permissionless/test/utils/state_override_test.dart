import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

final _token =
    EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
final _alice =
    EthereumAddress.fromHex('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
final _bob =
    EthereumAddress.fromHex('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

// Storage slots from Foundry 1.5.1, independent of this package:
//   balances[owner]          = cast index address <owner> <slot>
//   allowances[owner][spend] = cast index address <spend> \
//                                $(cast index address <owner> <slot>)
const _aliceBalanceSlot0 =
    '0x1bfd945afb434ed902aa821149f45ebda8b1e3eba6797fc235eb1e3fb6674b2a';
const _aliceBalanceSlot9 =
    '0x222e204deb4b693f6284a34ba1eba80a25a9c759f1e49a2978a9cae49d1b2783';
const _bobBalanceSlot0 =
    '0xaedf8090423f7c23f181308bda87a46b7a0caa99e0bf89e87bc6ce10666b4a03';
const _aliceToBobAllowanceSlot1 =
    '0xc065bd67b9daab520af386be8b42f2153a1b04c0b9b83bc96784d0a31efc1a28';
const _bobToAliceAllowanceSlot1 =
    '0x1a35a49e4dc916415309719a322edcd2dcb1c7bbeff367f95c16fee52a8fd98e';
const _aliceToBobAllowanceSlot10 =
    '0x035b7c8d5cc070b87f6b43894d28cfd035dcd0cc305761e504cc0f30d7b20a73';

// 32-byte values: cast to-uint256 <value>.
const _uint1000000 =
    '0x00000000000000000000000000000000000000000000000000000000000f4240';
const _uint500000 =
    '0x000000000000000000000000000000000000000000000000000000000007a120';

/// The single stateDiff entry of a one-token override, as JSON.
Map<String, dynamic> _onlyOverride(List<StateOverride> overrides) {
  expect(overrides, hasLength(1));
  expect(overrides.single.address, _token);
  return overrides.single.toJson();
}

void main() {
  group('StateDiff', () {
    test('toJson returns slot-value map', () {
      const diff = StateDiff(slot: '0xabc123', value: '0xdef456');
      expect(diff.toJson(), equals({'0xabc123': '0xdef456'}));
    });
  });

  group('StateOverride', () {
    test('toJson hex-encodes every set field', () {
      final override = StateOverride(
        address: _token,
        balance: BigInt.from(1000),
        nonce: BigInt.from(42),
        code: '0x1234',
        stateDiff: [
          const StateDiff(slot: '0xaaa', value: '0x111'),
          const StateDiff(slot: '0xbbb', value: '0x222'),
        ],
      );

      expect(override.toJson(), {
        'balance': '0x3e8',
        'nonce': '0x2a',
        'code': '0x1234',
        'stateDiff': {'0xaaa': '0x111', '0xbbb': '0x222'},
      });
    });

    test('toJson excludes null fields', () {
      expect(StateOverride(address: _token).toJson(), isEmpty);
    });
  });

  group('erc20BalanceOverride', () {
    for (final (label, owner, slot, expectedSlot) in [
      ('alice, slot 0', _alice, BigInt.zero, _aliceBalanceSlot0),
      ('alice, slot 9 (USDC)', _alice, BigInt.from(9), _aliceBalanceSlot9),
      ('bob, slot 0', _bob, BigInt.zero, _bobBalanceSlot0),
    ]) {
      test('writes balances[owner] at the Solidity mapping slot: $label', () {
        final result = erc20BalanceOverride(
          token: _token,
          owner: owner,
          slot: slot,
          balance: BigInt.from(1000000),
        );
        expect(_onlyOverride(result), {
          'stateDiff': {expectedSlot: _uint1000000},
        });
      });
    }

    // Same default as permissionless.js erc20BalanceOverride.
    test('defaults the balance to 0x1000…00fff…ff', () {
      final result = erc20BalanceOverride(
        token: _token,
        owner: _alice,
        slot: BigInt.zero,
      );
      expect(_onlyOverride(result), {
        'stateDiff': {
          _aliceBalanceSlot0:
              '0x100000000000000000000000000fffffffffffffffffffffffffffffffffffff',
        },
      });
    });
  });

  group('erc20AllowanceOverride', () {
    for (final (label, owner, spender, slot, expectedSlot) in [
      (
        'alice -> bob, slot 1',
        _alice,
        _bob,
        BigInt.one,
        _aliceToBobAllowanceSlot1,
      ),
      (
        'bob -> alice, slot 1',
        _bob,
        _alice,
        BigInt.one,
        _bobToAliceAllowanceSlot1,
      ),
      (
        'alice -> bob, slot 10 (USDC)',
        _alice,
        _bob,
        BigInt.from(10),
        _aliceToBobAllowanceSlot10,
      ),
    ]) {
      test('writes allowances[owner][spender] at the nested slot: $label', () {
        final result = erc20AllowanceOverride(
          token: _token,
          owner: owner,
          spender: spender,
          slot: slot,
          amount: BigInt.from(1000000),
        );
        expect(_onlyOverride(result), {
          'stateDiff': {expectedSlot: _uint1000000},
        });
      });
    }

    // Same default as permissionless.js erc20AllowanceOverride.
    test('defaults the amount to 0x7fff…ff', () {
      final result = erc20AllowanceOverride(
        token: _token,
        owner: _alice,
        spender: _bob,
        slot: BigInt.one,
      );
      expect(_onlyOverride(result), {
        'stateDiff': {
          _aliceToBobAllowanceSlot1:
              '0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        },
      });
    });
  });

  group('erc20PaymasterOverride', () {
    test('writes the balance and the allowance into one token override', () {
      final result = erc20PaymasterOverride(
        token: _token,
        owner: _alice,
        spender: _bob,
        balanceSlot: BigInt.zero,
        allowanceSlot: BigInt.one,
        balance: BigInt.from(1000000),
        allowance: BigInt.from(500000),
      );
      expect(_onlyOverride(result), {
        'stateDiff': {
          _aliceBalanceSlot0: _uint1000000,
          _aliceToBobAllowanceSlot1: _uint500000,
        },
      });
    });
  });

  group('mergeStateOverrides', () {
    test('returns single override unchanged', () {
      final override =
          StateOverride(address: _token, balance: BigInt.from(100));
      expect(mergeStateOverrides([override]), [same(override)]);
    });

    test('keeps overrides for different addresses separate', () {
      final merged = mergeStateOverrides([
        StateOverride(address: _token, balance: BigInt.from(100)),
        StateOverride(address: _alice, balance: BigInt.from(200)),
      ]);

      expect(merged.map((o) => o.address), [_token, _alice]);
      expect(
        merged.map((o) => o.balance),
        [BigInt.from(100), BigInt.from(200)],
      );
    });

    test('merges stateDiffs for same address', () {
      final merged = mergeStateOverrides([
        ...erc20BalanceOverride(
          token: _token,
          owner: _alice,
          slot: BigInt.zero,
          balance: BigInt.from(1000000),
        ),
        ...erc20AllowanceOverride(
          token: _token,
          owner: _alice,
          spender: _bob,
          slot: BigInt.one,
          amount: BigInt.from(500000),
        ),
      ]);

      expect(_onlyOverride(merged), {
        'stateDiff': {
          _aliceBalanceSlot0: _uint1000000,
          _aliceToBobAllowanceSlot1: _uint500000,
        },
      });
    });

    test('later values override earlier ones for same slot', () {
      final merged = mergeStateOverrides([
        StateOverride(
          address: _token,
          stateDiff: [const StateDiff(slot: '0xabc', value: '0x111')],
        ),
        StateOverride(
          address: _token,
          stateDiff: [const StateDiff(slot: '0xabc', value: '0x999')],
        ),
      ]);

      expect(_onlyOverride(merged), {
        'stateDiff': {'0xabc': '0x999'},
      });
    });
  });

  group('stateOverridesToJson', () {
    test('keys each override by token address', () {
      final json = stateOverridesToJson([
        ...erc20BalanceOverride(
          token: _token,
          owner: _alice,
          slot: BigInt.zero,
          balance: BigInt.from(1000000),
        ),
        StateOverride(address: _alice, nonce: BigInt.from(10)),
      ]);

      expect(json, {
        '0x1234567890123456789012345678901234567890': {
          'stateDiff': {_aliceBalanceSlot0: _uint1000000},
        },
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa': {'nonce': '0xa'},
      });
    });

    test('keeps every slot when two overrides target the same token', () {
      final balance = erc20BalanceOverride(
        token: _token,
        owner: _alice,
        slot: BigInt.zero,
      );
      final allowance = erc20AllowanceOverride(
        token: _token,
        owner: _alice,
        spender: _bob,
        slot: BigInt.one,
      );

      final json = stateOverridesToJson([...balance, ...allowance]);
      final slots = (json[_token.hex] as Map<String, dynamic>)['stateDiff']
          as Map<String, String>;
      expect(slots.keys, {_aliceBalanceSlot0, _aliceToBobAllowanceSlot1});
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
