import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('ERC-7579 Utilities', () {
    final module =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    group('encode7579SingleCallData', () {
      // cast abi-encode --packed 'f(address,uint256,bytes)' \
      //   0x1234567890123456789012345678901234567890 1000 0xabcdef
      test('packs target (20 bytes), value (32 bytes) and data', () {
        expect(
          encode7579SingleCallData(
            Call(to: module, value: BigInt.from(1000), data: '0xabcdef'),
          ),
          equals(
            '0x1234567890123456789012345678901234567890'
            '00000000000000000000000000000000000000000000000000000000000003e8'
            'abcdef',
          ),
        );
      });
    });

    group('encode7579BatchCallData', () {
      test('throws on empty calls', () {
        expect(
          () => encode7579BatchCallData([]),
          throwsArgumentError,
        );
      });

      // cast abi-encode 'f((address,uint256,bytes)[])' \
      //   "[(0x1111111111111111111111111111111111111111,1000000000000000000,0xdeadbeef),(0x2222222222222222222222222222222222222222,0,0x)]"
      test('ABI-encodes the calls as (address,uint256,bytes)[]', () {
        expect(
          encode7579BatchCallData([
            Call(
              to: EthereumAddress.fromHex(
                '0x1111111111111111111111111111111111111111',
              ),
              value: BigInt.parse('1000000000000000000'),
              data: '0xdeadbeef',
            ),
            Call(
              to: EthereumAddress.fromHex(
                '0x2222222222222222222222222222222222222222',
              ),
            ),
          ]),
          equals(
            '0x'
            '0000000000000000000000000000000000000000000000000000000000000020'
            '0000000000000000000000000000000000000000000000000000000000000002'
            '0000000000000000000000000000000000000000000000000000000000000040'
            '00000000000000000000000000000000000000000000000000000000000000e0'
            '0000000000000000000000001111111111111111111111111111111111111111'
            '0000000000000000000000000000000000000000000000000de0b6b3a7640000'
            '0000000000000000000000000000000000000000000000000000000000000060'
            '0000000000000000000000000000000000000000000000000000000000000004'
            'deadbeef00000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000002222222222222222222222222222222222222222'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000060'
            '0000000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });
    });

    group('encode7579ExecuteBatch', () {
      test('throws on empty calls', () {
        expect(
          () => encode7579ExecuteBatch([]),
          throwsArgumentError,
        );
      });

      test('keeps batch mode for a single-element batch (no silent downgrade)',
          () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
        ];

        final batchEncoded = encode7579ExecuteBatch(calls);
        final singleEncoded = encode7579Execute(calls.first);

        // Mode byte 0 must stay batch (0x01), not collapse to call (0x00).
        final mode = batchEncoded.substring(10, 74);
        expect(mode.substring(0, 2), equals('01'));
        expect(batchEncoded, isNot(equals(singleEncoded)));

        final decoded = decode7579Calls(batchEncoded);
        expect(decoded.mode.type, equals(Erc7579CallKind.batchCall));
        expect(decoded.calls, hasLength(1));
        expect(
          decoded.calls[0].to.hex.toLowerCase(),
          equals(calls[0].to.hex.toLowerCase()),
        );
      });
    });

    group('encode7579ExecuteDelegateCall', () {
      test('round-trips through decode7579Calls', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(42),
          data: '0xdeadbeef',
        );

        final decoded = decode7579Calls(encode7579ExecuteDelegateCall(call));
        expect(decoded.mode.type, equals(Erc7579CallKind.delegateCall));
        expect(decoded.mode.revertOnError, isFalse);
        expect(decoded.calls, hasLength(1));
        expect(
          decoded.calls[0].to.hex.toLowerCase(),
          equals(call.to.hex.toLowerCase()),
        );
        expect(decoded.calls[0].value, equals(call.value));
        expect(
          decoded.calls[0].data.toLowerCase(),
          equals(call.data.toLowerCase()),
        );
      });
    });

    // cast sig '<signature>'
    test('Erc7579Selectors match the ERC-7579 signatures', () {
      expect(Erc7579Selectors.execute, '0xe9ae5c53');
      expect(Erc7579Selectors.installModule, '0x9517e29f');
      expect(Erc7579Selectors.uninstallModule, '0xa71763a8');
      expect(Erc7579Selectors.isModuleInstalled, '0x112d3a7d');
      expect(Erc7579Selectors.supportsModule, '0xf2dc691d');
      expect(Erc7579Selectors.accountId, '0x9cfd7cff');
      expect(Erc7579Selectors.supportsExecutionMode, '0xd03c7914');
    });

    // Expected calldata: cast calldata '<fn>(uint256,address,bytes)' \
    //   <typeId> 0x1234567890123456789012345678901234567890 <bytes>
    group('module management calldata (cast)', () {
      const moduleWord =
          '0000000000000000000000001234567890123456789012345678901234567890';
      const bytesOffset =
          '0000000000000000000000000000000000000000000000000000000000000060';
      const emptyBytes =
          '0000000000000000000000000000000000000000000000000000000000000000';
      String typeWord(int id) => id.toRadixString(16).padLeft(64, '0');

      test('encode7579InstallModule, validator, no init data', () {
        expect(
          encode7579InstallModule(
            moduleType: Erc7579ModuleType.validator,
            module: module,
          ),
          equals('0x9517e29f${typeWord(1)}$moduleWord$bytesOffset$emptyBytes'),
        );
      });

      test('encode7579InstallModule, executor, init data 0xabcdef', () {
        expect(
          encode7579InstallModule(
            moduleType: Erc7579ModuleType.executor,
            module: module,
            initData: '0xabcdef',
          ),
          equals(
            '0x9517e29f${typeWord(2)}$moduleWord$bytesOffset'
            '0000000000000000000000000000000000000000000000000000000000000003'
            'abcdef0000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('encode7579UninstallModule, validator, no de-init data', () {
        expect(
          encode7579UninstallModule(
            moduleType: Erc7579ModuleType.validator,
            module: module,
          ),
          equals('0xa71763a8${typeWord(1)}$moduleWord$bytesOffset$emptyBytes'),
        );
      });

      test('encode7579UninstallModule, hook, de-init data 0xaabbccdd', () {
        expect(
          encode7579UninstallModule(
            moduleType: Erc7579ModuleType.hook,
            module: module,
            deInitData: '0xaabbccdd',
          ),
          equals(
            '0xa71763a8${typeWord(4)}$moduleWord$bytesOffset'
            '0000000000000000000000000000000000000000000000000000000000000004'
            'aabbccdd00000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('encode7579IsModuleInstalled, no additional context', () {
        expect(
          encode7579IsModuleInstalled(
            moduleType: Erc7579ModuleType.validator,
            module: module,
          ),
          equals('0x112d3a7d${typeWord(1)}$moduleWord$bytesOffset$emptyBytes'),
        );
      });

      test('encode7579IsModuleInstalled, additional context 0xabcd', () {
        expect(
          encode7579IsModuleInstalled(
            moduleType: Erc7579ModuleType.validator,
            module: module,
            additionalContext: '0xabcd',
          ),
          equals(
            '0x112d3a7d${typeWord(1)}$moduleWord$bytesOffset'
            '0000000000000000000000000000000000000000000000000000000000000002'
            'abcd000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      // cast calldata 'supportsModule(uint256)' <typeId>; ERC-7579 type ids
      // validator 1, executor 2, fallback 3, hook 4.
      test('encode7579SupportsModule for every module type', () {
        for (final (type, id) in [
          (Erc7579ModuleType.validator, 1),
          (Erc7579ModuleType.executor, 2),
          (Erc7579ModuleType.fallback, 3),
          (Erc7579ModuleType.hook, 4),
        ]) {
          expect(
            encode7579SupportsModule(type),
            equals('0xf2dc691d${typeWord(id)}'),
            reason: '$type',
          );
        }
      });

      // cast sig 'accountId()'
      test('encode7579AccountId is the bare accountId() selector', () {
        expect(encode7579AccountId(), equals('0x9cfd7cff'));
      });
    });

    group('decode7579BoolResult', () {
      test('decodes true result', () {
        const hex =
            '0x0000000000000000000000000000000000000000000000000000000000000001';
        expect(decode7579BoolResult(hex), isTrue);
      });

      test('decodes false result', () {
        const hex =
            '0x0000000000000000000000000000000000000000000000000000000000000000';
        expect(decode7579BoolResult(hex), isFalse);
      });

      test('handles empty result as false', () {
        expect(decode7579BoolResult('0x'), isFalse);
        expect(decode7579BoolResult(''), isFalse);
      });

      test('treats any non-zero as true', () {
        const hex =
            '0x00000000000000000000000000000000000000000000000000000000000000ff';
        expect(decode7579BoolResult(hex), isTrue);
      });
    });

    group('decode7579StringResult', () {
      test('decodes simple string', () {
        // ABI-encoded string "hello"
        // offset (32) = 0x20
        // length (5) = 0x05
        // data = "hello" hex = 0x68656c6c6f
        const hex = '0x'
            '0000000000000000000000000000000000000000000000000000000000000020' // offset to string
            '0000000000000000000000000000000000000000000000000000000000000005' // length
            '68656c6c6f000000000000000000000000000000000000000000000000000000'; // "hello" padded

        final result = decode7579StringResult(hex);
        expect(result, equals('hello'));
      });

      test('decodes a recorded Nexus accountId() result', () {
        // ABI-encoded string "rhinestone.nexus.1.0.0" (22 bytes, length 0x16)
        const recordedAccountId = '0x'
            '0000000000000000000000000000000000000000000000000000000000000020'
            '0000000000000000000000000000000000000000000000000000000000000016'
            '7268696e6573746f6e652e6e657875732e312e302e3000000000000000000000';
        expect(
          decode7579StringResult(recordedAccountId),
          equals('rhinestone.nexus.1.0.0'),
        );
      });

      test('decodes UTF-8 (non-ASCII) account ids', () {
        // cast abi-encode "f(string)" "kernel.advanced.0.3.1-ñ✓"
        const hex = '0x'
            '0000000000000000000000000000000000000000000000000000000000000020'
            '000000000000000000000000000000000000000000000000000000000000001b'
            '6b65726e656c2e616476616e6365642e302e332e312dc3b1e29c930000000000';

        expect(decode7579StringResult(hex), 'kernel.advanced.0.3.1-ñ✓');
      });

      test('handles empty result', () {
        expect(decode7579StringResult('0x'), equals(''));
        expect(decode7579StringResult(''), equals(''));
      });

      test('handles empty string in result', () {
        const hex = '0x'
            '0000000000000000000000000000000000000000000000000000000000000020' // offset
            '0000000000000000000000000000000000000000000000000000000000000000'; // length = 0

        final result = decode7579StringResult(hex);
        expect(result, equals(''));
      });
    });

    group('Erc7579CallKind', () {
      test('fromValue returns correct enum', () {
        expect(Erc7579CallKind.fromValue(0x00), equals(Erc7579CallKind.call));
        expect(
          Erc7579CallKind.fromValue(0x01),
          equals(Erc7579CallKind.batchCall),
        );
        expect(
          Erc7579CallKind.fromValue(0xff),
          equals(Erc7579CallKind.delegateCall),
        );
      });

      test('fromValue throws for unknown value', () {
        expect(
          () => Erc7579CallKind.fromValue(0x02),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('ExecutionMode.encode', () {
      // permissionless.js: revertOnError undefined -> falsy -> execType 0x00.
      test('defaults revertOnError to false (execType 0x00)', () {
        expect(
          const ExecutionMode(type: Erc7579CallKind.call).encode(),
          equals('0x${'00' * 32}'),
        );
      });

      // viem 2.21.55 encodePacked, as in permissionless.js encodeExecutionMode:
      //   /Users/liorag/.claude/jobs/037f9518/tmp/t1/viem/erc7579.ts
      test('right-pads a short selector into bytes 6-9', () {
        expect(
          const ExecutionMode(
            type: Erc7579CallKind.call,
            selector: '0xaabbccdd',
          ).encode(),
          equals('0x${'00' * 6}aabbccdd${'00' * 22}'),
        );
      });

      test('right-pads a short context into bytes 10-31', () {
        expect(
          const ExecutionMode(
            type: Erc7579CallKind.call,
            context: '0x1122334455',
          ).encode(),
          equals('0x${'00' * 10}1122334455${'00' * 17}'),
        );
      });
    });

    group('decodeNonce', () {
      test('decodes zero nonce', () {
        final decoded = decodeNonce(BigInt.zero);

        expect(decoded.key, equals(BigInt.zero));
        expect(decoded.sequence, equals(BigInt.zero));
      });

      test('decodes nonce with only sequence', () {
        final decoded = decodeNonce(BigInt.from(42));

        expect(decoded.key, equals(BigInt.zero));
        expect(decoded.sequence, equals(BigInt.from(42)));
      });

      test('decodes nonce with key and sequence', () {
        // Key = 1, Sequence = 5
        // nonce = (1 << 64) + 5
        final nonce = (BigInt.one << 64) + BigInt.from(5);
        final decoded = decodeNonce(nonce);

        expect(decoded.key, equals(BigInt.one));
        expect(decoded.sequence, equals(BigInt.from(5)));
      });

      test('decodes large key values', () {
        // Key = 0xdeadbeef, Sequence = 0x1234
        final key = BigInt.parse('deadbeef', radix: 16);
        final sequence = BigInt.parse('1234', radix: 16);
        final nonce = (key << 64) + sequence;
        final decoded = decodeNonce(nonce);

        expect(decoded.key, equals(key));
        expect(decoded.sequence, equals(sequence));
      });

      test('handles max 64-bit sequence', () {
        final maxSequence = BigInt.parse('ffffffffffffffff', radix: 16);
        final decoded = decodeNonce(maxSequence);

        expect(decoded.key, equals(BigInt.zero));
        expect(decoded.sequence, equals(maxSequence));
      });

      test('handles 192-bit key', () {
        // Maximum 192-bit key (fills all 192 bits)
        final maxKey = BigInt.parse(
          'ffffffffffffffffffffffffffffffffffffffffffffffff',
          radix: 16,
        );
        final sequence = BigInt.from(1);
        final nonce = (maxKey << 64) + sequence;
        final decoded = decodeNonce(nonce);

        expect(decoded.key, equals(maxKey));
        expect(decoded.sequence, equals(sequence));
      });
    });

    group('encodeNonce', () {
      test('encodes zero key and sequence', () {
        final nonce = encodeNonce(key: BigInt.zero, sequence: BigInt.zero);
        expect(nonce, equals(BigInt.zero));
      });

      test('encodes sequence only', () {
        final nonce = encodeNonce(key: BigInt.zero, sequence: BigInt.from(100));
        expect(nonce, equals(BigInt.from(100)));
      });

      test('encodes key and sequence', () {
        final nonce =
            encodeNonce(key: BigInt.from(5), sequence: BigInt.from(10));
        // key 0x5 in the upper 192 bits, sequence 0xa in the lower 64.
        expect(nonce, equals(BigInt.parse('0x5000000000000000a')));
      });

      test('roundtrips with decodeNonce', () {
        final originalKey = BigInt.parse('abcdef123456', radix: 16);
        final originalSequence = BigInt.from(999);

        final encoded =
            encodeNonce(key: originalKey, sequence: originalSequence);
        final decoded = decodeNonce(encoded);

        expect(decoded.key, equals(originalKey));
        expect(decoded.sequence, equals(originalSequence));
      });

      test('masks sequence that exceeds 64 bits', () {
        // 2^64 + 1 should be masked to 1
        final tooBig = BigInt.parse('10000000000000001', radix: 16);
        final nonce = encodeNonce(key: BigInt.zero, sequence: tooBig);
        final decoded = decodeNonce(nonce);

        // Only lowest 64 bits are kept
        expect(decoded.sequence, equals(BigInt.one));
      });

      test('masks key that exceeds 192 bits', () {
        // 2^192 + 1 should be masked to 1
        final tooBig = (BigInt.one << 192) + BigInt.one;
        final nonce = encodeNonce(key: tooBig, sequence: BigInt.zero);
        final decoded = decodeNonce(nonce);

        // Only lowest 192 bits are kept
        expect(decoded.key, equals(BigInt.one));
      });
    });

    group('decode7579Calls', () {
      test('round-trips ExecutionMode with explicit revertOnError true', () {
        // Build execute calldata whose mode has execType 0x01 (JS true).
        const mode = ExecutionMode(
          type: Erc7579CallKind.call,
          revertOnError: true,
          selector: '0xaabbccdd',
          context: '0x11223344556677889900112233445566778899001122',
        );
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(7),
          data: '0xabcdef',
        );
        final executionData = encode7579SingleCallData(call);
        const executionDataOffset = 2 * 32;
        final encoded = Hex.concat([
          Erc7579Selectors.execute,
          Hex.strip0x(mode.encode()),
          AbiEncoder.encodeUint256(BigInt.from(executionDataOffset)),
          Hex.strip0x(AbiEncoder.encodeBytes(executionData)),
        ]);

        final decoded = decode7579Calls(encoded);

        expect(decoded.mode.type, equals(Erc7579CallKind.call));
        expect(decoded.mode.revertOnError, isTrue);
        // Spec-aligned offsets (bytes 6-9 / 10-31), not JS's lossy 3-6 / 7-31.
        expect(decoded.mode.selector?.toLowerCase(), equals('0xaabbccdd'));
        expect(
          decoded.mode.context?.toLowerCase(),
          equals('0x11223344556677889900112233445566778899001122'),
        );
        expect(decoded.calls, hasLength(1));
        expect(decoded.calls[0].value, equals(BigInt.from(7)));
      });

      test('decodes single call execution', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000),
          data: '0xabcdef',
        );
        final encoded = encode7579Execute(call);

        final decoded = decode7579Calls(encoded);

        expect(decoded.mode.type, equals(Erc7579CallKind.call));
        expect(decoded.mode.revertOnError, isFalse);
        expect(decoded.calls, hasLength(1));
        expect(
          decoded.calls[0].to.hex.toLowerCase(),
          equals(call.to.hex.toLowerCase()),
        );
        expect(decoded.calls[0].value, equals(call.value));
        expect(
          decoded.calls[0].data.toLowerCase(),
          equals(call.data.toLowerCase()),
        );
      });

      test('decodes call with large data payload', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0x${'ab' * 256}', // 256 bytes of data
        );
        final encoded = encode7579Execute(call);

        final decoded = decode7579Calls(encoded);

        expect(
          decoded.calls[0].data.toLowerCase(),
          equals(call.data.toLowerCase()),
        );
      });

      test('roundtrips multiple calls', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
            value: BigInt.from(1000000000000000000), // 1 ETH
            data: '0x12345678',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0xcccccccccccccccccccccccccccccccccccccccc',
            ),
            value: BigInt.from(5000),
            data: '0xdeadbeefcafe',
          ),
        ];
        final encoded = encode7579ExecuteBatch(calls);

        final decoded = decode7579Calls(encoded);

        expect(decoded.calls, hasLength(3));
        for (var i = 0; i < calls.length; i++) {
          expect(
            decoded.calls[i].to.hex.toLowerCase(),
            equals(calls[i].to.hex.toLowerCase()),
          );
          expect(decoded.calls[i].value, equals(calls[i].value));
          expect(
            decoded.calls[i].data.toLowerCase(),
            equals(calls[i].data.toLowerCase()),
          );
        }
      });

      test('throws for invalid selector', () {
        // Random calldata that doesn't start with execute selector
        const invalidCallData = '0x12345678aabbccdd';

        expect(
          () => decode7579Calls(invalidCallData),
          throwsArgumentError,
        );
      });

      test('accepts an upper-case selector', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(5),
          data: '0xabcdef',
        );
        final encoded = encode7579Execute(call);
        final upper = '0xE9AE5C53${encoded.substring(10)}';

        final decoded = decode7579Calls(upper);

        expect(decoded.calls.single.to, equals(call.to));
        expect(decoded.calls.single.value, equals(call.value));
        expect(decoded.calls.single.data, equals(call.data));
      });

      test('throws for a truncated batch payload', () {
        // Batch mode whose executionCalldata holds only the array offset.
        const truncated = '0xe9ae5c53'
            '0100000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000040'
            '0000000000000000000000000000000000000000000000000000000000000020'
            '0000000000000000000000000000000000000000000000000000000000000020';

        expect(() => decode7579Calls(truncated), throwsArgumentError);
      });

      test('throws for invalid call type', () {
        // Valid selector but invalid call type (0x02)
        const invalidCallData = '0xe9ae5c53' // execute selector
            '0200000000000000000000000000000000000000000000000000000000000000' // invalid mode
            '0000000000000000000000000000000000000000000000000000000000000040'
            '0000000000000000000000000000000000000000000000000000000000000000';

        expect(
          () => decode7579Calls(invalidCallData),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    // Independent vectors from Foundry cast 1.5.1, ERC-7579 mode layout
    // callType(1) execType(1) unused(4) selector(4) payload(22):
    //   cast abi-encode --packed 'f(bytes1,bytes1,bytes4,bytes4,bytes22)' \
    //     <callType> <execType> 0x00000000 <selector> <payload>
    group('mode word characterization (cast)', () {
      const modeWords = <(Erc7579CallKind, int, String)>[
        (
          Erc7579CallKind.call,
          Erc7579ExecType.defaultExec,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
        ),
        (
          Erc7579CallKind.call,
          Erc7579ExecType.tryExec,
          '0x0001000000000000000000000000000000000000000000000000000000000000',
        ),
        (
          Erc7579CallKind.batchCall,
          Erc7579ExecType.defaultExec,
          '0x0100000000000000000000000000000000000000000000000000000000000000',
        ),
        (
          Erc7579CallKind.batchCall,
          Erc7579ExecType.tryExec,
          '0x0101000000000000000000000000000000000000000000000000000000000000',
        ),
        (
          Erc7579CallKind.delegateCall,
          Erc7579ExecType.defaultExec,
          '0xff00000000000000000000000000000000000000000000000000000000000000',
        ),
        (
          Erc7579CallKind.delegateCall,
          Erc7579ExecType.tryExec,
          '0xff01000000000000000000000000000000000000000000000000000000000000',
        ),
      ];

      test('encode7579ExecuteMode matches every (callType, execType)', () {
        for (final (kind, execType, expected) in modeWords) {
          expect(
            encode7579ExecuteMode(callType: kind.value, execType: execType),
            equals(expected),
            reason: '$kind execType=$execType',
          );
        }
      });

      test('ExecutionMode.encode matches every (callType, execType)', () {
        for (final (kind, execType, expected) in modeWords) {
          expect(
            ExecutionMode(
              type: kind,
              revertOnError: execType == Erc7579ExecType.tryExec,
            ).encode(),
            equals(expected),
            reason: '$kind execType=$execType',
          );
        }
      });

      test('ExecutionMode.encode places selector and payload', () {
        // cast abi-encode --packed 'f(bytes1,bytes1,bytes4,bytes4,bytes22)' \
        //   0x01 0x01 0x00000000 0xaabbccdd \
        //   0x11223344556677889900112233445566778899001122
        expect(
          const ExecutionMode(
            type: Erc7579CallKind.batchCall,
            revertOnError: true,
            selector: '0xaabbccdd',
            context: '0x11223344556677889900112233445566778899001122',
          ).encode(),
          equals(
            '0x010100000000aabbccdd11223344556677889900112233445566778899001122',
          ),
        );
      });

      // permissionless.js `encodeExecutionMode` throws (viem SizeOverflowError)
      // for a selector over 4 bytes or a context over 22 bytes.
      test('ExecutionMode.encode rejects a selector over 4 bytes', () {
        expect(
          () => const ExecutionMode(
            type: Erc7579CallKind.call,
            selector: '0xaabbccddee',
          ).encode(),
          throwsArgumentError,
        );
      });

      test('ExecutionMode.encode rejects a context over 22 bytes', () {
        expect(
          () => ExecutionMode(
            type: Erc7579CallKind.call,
            context: '0x${'11' * 23}',
          ).encode(),
          throwsArgumentError,
        );
      });

      test('encode7579ExecuteMode rejects a callType or execType over 1 byte',
          () {
        expect(
          () => encode7579ExecuteMode(callType: 0x100),
          throwsArgumentError,
        );
        expect(() => encode7579ExecuteMode(callType: -1), throwsArgumentError);
        expect(
          () => encode7579ExecuteMode(execType: 0x101),
          throwsArgumentError,
        );
      });

      test('Erc7579CallKind and Erc7579CallType carry the same bytes', () {
        expect(Erc7579CallKind.call.value, Erc7579CallType.call);
        expect(Erc7579CallKind.batchCall.value, Erc7579CallType.batchCall);
        expect(
          Erc7579CallKind.delegateCall.value,
          Erc7579CallType.delegateCall,
        );
      });
    });

    group('execute calldata characterization (cast)', () {
      final to = EthereumAddress.fromHex(
        '0x1111111111111111111111111111111111111111',
      );
      final to2 = EthereumAddress.fromHex(
        '0x2222222222222222222222222222222222222222',
      );
      final single = Call(
        to: to,
        value: BigInt.parse('1000000000000000000'),
        data: '0xdeadbeef',
      );

      // SINGLE=$(cast abi-encode --packed 'f(address,uint256,bytes)' \
      //   0x1111111111111111111111111111111111111111 1000000000000000000 \
      //   0xdeadbeef)
      // cast calldata 'execute(bytes32,bytes)' <mode 0x00..00> $SINGLE
      test('encode7579Execute', () {
        expect(
          encode7579Execute(single),
          equals(
            '0xe9ae5c53'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000040'
            '0000000000000000000000000000000000000000000000000000000000000038'
            '1111111111111111111111111111111111111111'
            '0000000000000000000000000000000000000000000000000de0b6b3a7640000'
            'deadbeef0000000000000000',
          ),
        );
      });

      // cast calldata 'execute(bytes32,bytes)' <mode 0xff00..00> $SINGLE
      test('encode7579ExecuteDelegateCall', () {
        expect(
          encode7579ExecuteDelegateCall(single),
          equals(
            '0xe9ae5c53'
            'ff00000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000040'
            '0000000000000000000000000000000000000000000000000000000000000038'
            '1111111111111111111111111111111111111111'
            '0000000000000000000000000000000000000000000000000de0b6b3a7640000'
            'deadbeef0000000000000000',
          ),
        );
      });

      // BATCH=$(cast abi-encode 'f((address,uint256,bytes)[])' \
      //   "[(0x1111111111111111111111111111111111111111,1000000000000000000,0xdeadbeef),(0x2222222222222222222222222222222222222222,0,0x)]")
      // cast calldata 'execute(bytes32,bytes)' <mode 0x0100..00> $BATCH
      test('encode7579ExecuteBatch', () {
        expect(
          encode7579ExecuteBatch([single, Call(to: to2)]),
          equals(
            '0xe9ae5c53'
            '0100000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000040'
            '00000000000000000000000000000000000000000000000000000000000001a0'
            '0000000000000000000000000000000000000000000000000000000000000020'
            '0000000000000000000000000000000000000000000000000000000000000002'
            '0000000000000000000000000000000000000000000000000000000000000040'
            '00000000000000000000000000000000000000000000000000000000000000e0'
            '0000000000000000000000001111111111111111111111111111111111111111'
            '0000000000000000000000000000000000000000000000000de0b6b3a7640000'
            '0000000000000000000000000000000000000000000000000000000000000060'
            '0000000000000000000000000000000000000000000000000000000000000004'
            'deadbeef00000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000002222222222222222222222222222222222222222'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000060'
            '0000000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      // cast calldata 'supportsExecutionMode(bytes32)' \
      //   0x0101000000000000000000000000000000000000000000000000000000000000
      test('encode7579SupportsExecutionMode', () {
        expect(
          encode7579SupportsExecutionMode(
            const ExecutionMode(
              type: Erc7579CallKind.batchCall,
              revertOnError: true,
            ),
          ),
          equals(
            '0xd03c7914'
            '0101000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });
    });
  });
}
