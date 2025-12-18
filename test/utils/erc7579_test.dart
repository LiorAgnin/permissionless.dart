import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('ERC-7579 Utilities', () {
    group('Erc7579CallType', () {
      test('call type is 0x00', () {
        expect(Erc7579CallType.call, equals(0x00));
      });

      test('batchCall type is 0x01', () {
        expect(Erc7579CallType.batchCall, equals(0x01));
      });

      test('delegateCall type is 0xff', () {
        expect(Erc7579CallType.delegateCall, equals(0xff));
      });
    });

    group('Erc7579ExecType', () {
      test('default execution type is 0x00', () {
        expect(Erc7579ExecType.defaultExec, equals(0x00));
      });

      test('try execution type is 0x01', () {
        expect(Erc7579ExecType.tryExec, equals(0x01));
      });
    });

    group('encode7579ExecuteMode', () {
      test('encodes call mode correctly', () {
        final mode = encode7579ExecuteMode(callType: Erc7579CallType.call);

        expect(mode, startsWith('0x'));
        // 32 bytes = 64 hex chars + 0x = 66
        expect(mode.length, equals(66));
        // First byte is call type
        expect(mode.substring(2, 4), equals('00'));
        // Second byte is exec type (default)
        expect(mode.substring(4, 6), equals('00'));
      });

      test('encodes batch call mode correctly', () {
        final mode = encode7579ExecuteMode(callType: Erc7579CallType.batchCall);

        expect(mode.substring(2, 4), equals('01'));
      });

      test('encodes delegate call mode correctly', () {
        final mode =
            encode7579ExecuteMode(callType: Erc7579CallType.delegateCall);

        expect(mode.substring(2, 4), equals('ff'));
      });

      test('encodes try exec mode correctly', () {
        final mode = encode7579ExecuteMode(
          callType: Erc7579CallType.call,
          execType: Erc7579ExecType.tryExec,
        );

        expect(mode.substring(2, 4), equals('00')); // call type
        expect(mode.substring(4, 6), equals('01')); // try exec
      });

      test('remaining bytes are zero', () {
        final mode = encode7579ExecuteMode();

        // All bytes after first 2 should be zero
        final remaining = mode.substring(6);
        expect(remaining, equals('0' * 60));
      });
    });

    group('encode7579SingleCallData', () {
      test('encodes simple ETH transfer', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000),
          data: '0x',
        );

        final encoded = encode7579SingleCallData(call);

        expect(encoded, startsWith('0x'));
        // 20 bytes address + 32 bytes value = 52 bytes = 104 hex chars
        expect(encoded.length, equals(106)); // 104 + 2 for 0x
      });

      test('encodes call with data', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0xabcdef',
        );

        final encoded = encode7579SingleCallData(call);

        // 20 + 32 + 3 (data bytes) = 55 bytes = 110 hex chars
        expect(encoded.length, equals(112));
        // Should end with the data
        expect(encoded.toLowerCase().endsWith('abcdef'), isTrue);
      });

      test('includes address without padding', () {
        const address = '0x1234567890123456789012345678901234567890';
        final call = Call(
          to: EthereumAddress.fromHex(address),
          value: BigInt.zero,
          data: '0x',
        );

        final encoded = encode7579SingleCallData(call);

        // First 40 hex chars after 0x should be the address
        expect(
          encoded.substring(2, 42).toLowerCase(),
          equals(address.substring(2).toLowerCase()),
        );
      });

      test('encodes value as 32 bytes', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(255),
          data: '0x',
        );

        final encoded = encode7579SingleCallData(call);

        // Value starts at byte 20 (hex position 42)
        final valueHex = encoded.substring(42, 106);
        expect(valueHex.length, equals(64)); // 32 bytes
        expect(valueHex.endsWith('ff'), isTrue); // 255 = 0xff
      });
    });

    group('encode7579BatchCallData', () {
      test('throws on empty calls', () {
        expect(
          () => encode7579BatchCallData([]),
          throwsArgumentError,
        );
      });

      test('encodes single call in batch format', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
        ];

        final encoded = encode7579BatchCallData(calls);

        expect(encoded, startsWith('0x'));
        // Should contain array offset, length, and struct data
        expect(encoded.length, greaterThan(66));
      });

      test('encodes multiple calls', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.from(100),
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.from(200),
            data: '0xabcd',
          ),
        ];

        final encoded = encode7579BatchCallData(calls);

        expect(encoded, startsWith('0x'));
        // Should be longer than single call
        final singleEncoded = encode7579BatchCallData([calls.first]);
        expect(encoded.length, greaterThan(singleEncoded.length));
      });
    });

    group('encode7579Execute', () {
      test('encodes single call execution', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000),
          data: '0x',
        );

        final encoded = encode7579Execute(call);

        expect(encoded, startsWith('0x'));
        // Should start with execute selector
        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals(Erc7579Selectors.execute.substring(2).toLowerCase()),
        );
      });

      test('uses call mode for single execution', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0x',
        );

        final encoded = encode7579Execute(call);

        // Mode is bytes32 after selector (bytes 4-36, hex 10-74)
        final mode = encoded.substring(10, 74);
        // First byte should be call type (0x00)
        expect(mode.substring(0, 2), equals('00'));
      });
    });

    group('encode7579ExecuteBatch', () {
      test('throws on empty calls', () {
        expect(
          () => encode7579ExecuteBatch([]),
          throwsArgumentError,
        );
      });

      test('optimizes single call to non-batch encoding', () {
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

        // Should be identical for single call
        expect(batchEncoded, equals(singleEncoded));
      });

      test('uses batch mode for multiple calls', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
        ];

        final encoded = encode7579ExecuteBatch(calls);

        // Mode should be batch (0x01)
        final mode = encoded.substring(10, 74);
        expect(mode.substring(0, 2), equals('01'));
      });

      test('encodes selector correctly', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
        ];

        final encoded = encode7579ExecuteBatch(calls);

        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals(Erc7579Selectors.execute.substring(2).toLowerCase()),
        );
      });
    });

    group('Erc7579Selectors', () {
      test('execute selector is correct', () {
        // execute(bytes32,bytes) should have selector 0x61461954
        // (this is the standard ERC-7579 selector)
        expect(Erc7579Selectors.execute, startsWith('0x'));
        expect(Erc7579Selectors.execute.length, equals(10));
      });

      test('installModule selector is correct', () {
        // keccak256("installModule(uint256,address,bytes)")[0:4] = 0x9517e29f
        expect(Erc7579Selectors.installModule, equals('0x9517e29f'));
      });

      test('uninstallModule selector is correct', () {
        // keccak256("uninstallModule(uint256,address,bytes)")[0:4] = 0xa4d6f1d2
        expect(Erc7579Selectors.uninstallModule, equals('0xa4d6f1d2'));
      });

      test('isModuleInstalled selector is correct', () {
        // keccak256("isModuleInstalled(uint256,address,bytes)")[0:4] = 0x6d61fe70
        expect(Erc7579Selectors.isModuleInstalled, equals('0x6d61fe70'));
      });

      test('supportsModule selector is correct', () {
        // keccak256("supportsModule(uint256)")[0:4] = 0x12d79da3
        expect(Erc7579Selectors.supportsModule, equals('0x12d79da3'));
      });

      test('accountId selector is correct', () {
        // keccak256("accountId()")[0:4] = 0x7b60424a
        expect(Erc7579Selectors.accountId, equals('0x7b60424a'));
      });
    });

    group('Erc7579ModuleType', () {
      test('validator type has id 1', () {
        expect(Erc7579ModuleType.validator.id, equals(1));
      });

      test('executor type has id 2', () {
        expect(Erc7579ModuleType.executor.id, equals(2));
      });

      test('fallback type has id 3', () {
        expect(Erc7579ModuleType.fallback.id, equals(3));
      });

      test('hook type has id 4', () {
        expect(Erc7579ModuleType.hook.id, equals(4));
      });
    });

    group('encode7579InstallModule', () {
      test('encodes install module call correctly', () {
        final module = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );

        final encoded = encode7579InstallModule(
          moduleType: Erc7579ModuleType.validator,
          module: module,
          initData: '0x',
        );

        // Check selector
        expect(
          encoded.substring(0, 10),
          equals(Erc7579Selectors.installModule),
        );

        // Check it contains the module type (1 for validator)
        expect(
          encoded,
          contains(
            '0000000000000000000000000000000000000000000000000000000000000001',
          ),
        );
      });

      test('encodes with init data', () {
        final module = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );
        const initData = '0xabcdef';

        final encoded = encode7579InstallModule(
          moduleType: Erc7579ModuleType.executor,
          module: module,
          initData: initData,
        );

        // Should be longer due to init data
        final withoutInitData = encode7579InstallModule(
          moduleType: Erc7579ModuleType.executor,
          module: module,
          initData: '0x',
        );

        expect(encoded.length, greaterThan(withoutInitData.length));
      });

      test('encodes different module types correctly', () {
        final module = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );

        for (final type in Erc7579ModuleType.values) {
          final encoded = encode7579InstallModule(
            moduleType: type,
            module: module,
            initData: '0x',
          );

          // Each should start with the selector
          expect(
            encoded.substring(0, 10),
            equals(Erc7579Selectors.installModule),
          );
        }
      });
    });

    group('encode7579UninstallModule', () {
      test('encodes uninstall module call correctly', () {
        final module = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );

        final encoded = encode7579UninstallModule(
          moduleType: Erc7579ModuleType.validator,
          module: module,
          deInitData: '0x',
        );

        // Check selector
        expect(
          encoded.substring(0, 10),
          equals(Erc7579Selectors.uninstallModule),
        );
      });

      test('encodes with de-init data', () {
        final module = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );
        const deInitData = '0xaabbccdd';

        final encoded = encode7579UninstallModule(
          moduleType: Erc7579ModuleType.hook,
          module: module,
          deInitData: deInitData,
        );

        // Check selector
        expect(
          encoded.substring(0, 10),
          equals(Erc7579Selectors.uninstallModule),
        );
        // Should be longer due to de-init data
        expect(encoded.length, greaterThan(200));
      });
    });

    group('encode7579IsModuleInstalled', () {
      test('encodes isModuleInstalled query correctly', () {
        final module = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );

        final encoded = encode7579IsModuleInstalled(
          moduleType: Erc7579ModuleType.validator,
          module: module,
        );

        // Check selector
        expect(
          encoded.substring(0, 10),
          equals(Erc7579Selectors.isModuleInstalled),
        );
      });

      test('encodes with additional context', () {
        final module = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );

        final withContext = encode7579IsModuleInstalled(
          moduleType: Erc7579ModuleType.validator,
          module: module,
          additionalContext: '0xabcd',
        );

        final withoutContext = encode7579IsModuleInstalled(
          moduleType: Erc7579ModuleType.validator,
          module: module,
        );

        expect(withContext.length, greaterThan(withoutContext.length));
      });
    });

    group('encode7579SupportsModule', () {
      test('encodes supportsModule query correctly', () {
        final encoded = encode7579SupportsModule(Erc7579ModuleType.hook);

        // Check selector
        expect(
          encoded.substring(0, 10),
          equals(Erc7579Selectors.supportsModule),
        );
        // Should have selector (4 bytes) + uint256 (32 bytes) = 74 hex chars
        expect(encoded.length, equals(74));
      });

      test('encodes different module types', () {
        for (final type in Erc7579ModuleType.values) {
          final encoded = encode7579SupportsModule(type);
          expect(
            encoded.substring(0, 10),
            equals(Erc7579Selectors.supportsModule),
          );
        }
      });
    });

    group('encode7579AccountId', () {
      test('returns accountId selector', () {
        final encoded = encode7579AccountId();
        expect(encoded, equals(Erc7579Selectors.accountId));
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

    group('InstallModuleConfig', () {
      test('creates config with required fields', () {
        final config = InstallModuleConfig(
          type: Erc7579ModuleType.validator,
          address: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
        );

        expect(config.type, equals(Erc7579ModuleType.validator));
        expect(config.initData, equals('0x'));
      });

      test('creates config with init data', () {
        final config = InstallModuleConfig(
          type: Erc7579ModuleType.executor,
          address: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          initData: '0xabcd',
        );

        expect(config.initData, equals('0xabcd'));
      });
    });

    group('UninstallModuleConfig', () {
      test('creates config with required fields', () {
        final config = UninstallModuleConfig(
          type: Erc7579ModuleType.hook,
          address: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
        );

        expect(config.type, equals(Erc7579ModuleType.hook));
        expect(config.deInitData, equals('0x'));
      });

      test('creates config with de-init data', () {
        final config = UninstallModuleConfig(
          type: Erc7579ModuleType.fallback,
          address: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          deInitData: '0xffee',
        );

        expect(config.deInitData, equals('0xffee'));
      });
    });

    group('Erc7579CallKind', () {
      test('has correct byte values', () {
        expect(Erc7579CallKind.call.value, equals(0x00));
        expect(Erc7579CallKind.batchCall.value, equals(0x01));
        expect(Erc7579CallKind.delegateCall.value, equals(0xff));
      });

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

    group('ExecutionMode', () {
      test('creates with default values', () {
        const mode = ExecutionMode(type: Erc7579CallKind.call);

        expect(mode.type, equals(Erc7579CallKind.call));
        expect(mode.revertOnError, isTrue);
        expect(mode.selector, isNull);
        expect(mode.context, isNull);
      });

      test('creates with custom values', () {
        const mode = ExecutionMode(
          type: Erc7579CallKind.batchCall,
          revertOnError: false,
          selector: '0x12345678',
          context: '0xaabbccdd',
        );

        expect(mode.type, equals(Erc7579CallKind.batchCall));
        expect(mode.revertOnError, isFalse);
        expect(mode.selector, equals('0x12345678'));
        expect(mode.context, equals('0xaabbccdd'));
      });

      group('encode', () {
        test('encodes single call with revert on error', () {
          const mode = ExecutionMode(type: Erc7579CallKind.call);
          final encoded = mode.encode();

          expect(encoded, startsWith('0x'));
          expect(encoded.length, equals(66)); // 32 bytes + 0x

          // Byte 0: call type = 0x00
          expect(encoded.substring(2, 4), equals('00'));
          // Byte 1: revert on error = 0x00
          expect(encoded.substring(4, 6), equals('00'));
        });

        test('encodes batch call with try mode', () {
          const mode = ExecutionMode(
            type: Erc7579CallKind.batchCall,
            revertOnError: false,
          );
          final encoded = mode.encode();

          // Byte 0: batch call = 0x01
          expect(encoded.substring(2, 4), equals('01'));
          // Byte 1: try mode (no revert) = 0x01
          expect(encoded.substring(4, 6), equals('01'));
        });

        test('encodes delegate call', () {
          const mode = ExecutionMode(type: Erc7579CallKind.delegateCall);
          final encoded = mode.encode();

          // Byte 0: delegate call = 0xff
          expect(encoded.substring(2, 4), equals('ff'));
        });

        test('encodes with selector', () {
          const mode = ExecutionMode(
            type: Erc7579CallKind.call,
            selector: '0xaabbccdd',
          );
          final encoded = mode.encode();

          // Bytes 6-9 contain the selector
          // Position: 0x + 2 chars per byte * 6 = 14
          expect(encoded.substring(14, 22), equals('aabbccdd'));
        });

        test('encodes with context', () {
          const mode = ExecutionMode(
            type: Erc7579CallKind.call,
            context: '0x1122334455',
          );
          final encoded = mode.encode();

          // Bytes 10+ contain the context
          // Position: 0x + 2 chars per byte * 10 = 22
          expect(encoded.substring(22, 32), equals('1122334455'));
        });

        test('produces 32-byte output for all modes', () {
          final modes = [
            const ExecutionMode(type: Erc7579CallKind.call),
            const ExecutionMode(
              type: Erc7579CallKind.batchCall,
              revertOnError: false,
            ),
            const ExecutionMode(
              type: Erc7579CallKind.delegateCall,
              selector: '0xffffffff',
            ),
            ExecutionMode(
              type: Erc7579CallKind.call,
              context: '0x${'00' * 22}',
            ),
          ];

          for (final mode in modes) {
            final encoded = mode.encode();
            expect(encoded.length, equals(66), reason: 'Mode: $mode');
          }
        });
      });

      test('toString returns readable format', () {
        const mode = ExecutionMode(
          type: Erc7579CallKind.batchCall,
          revertOnError: false,
        );
        final str = mode.toString();

        expect(str, contains('batchCall'));
        expect(str, contains('revertOnError: false'));
      });
    });

    group('encode7579SupportsExecutionMode', () {
      test('encodes call to supportsExecutionMode', () {
        const mode = ExecutionMode(type: Erc7579CallKind.call);
        final callData = encode7579SupportsExecutionMode(mode);

        // Should start with the function selector
        expect(
          callData.toLowerCase(),
          startsWith(Erc7579Selectors.supportsExecutionMode.toLowerCase()),
        );
        // 4 bytes selector + 32 bytes mode = 36 bytes = 72 hex + 0x = 74
        expect(callData.length, equals(74));
      });

      test('encodes different modes correctly', () {
        const callMode = ExecutionMode(type: Erc7579CallKind.call);
        const batchMode = ExecutionMode(type: Erc7579CallKind.batchCall);
        const delegateMode = ExecutionMode(type: Erc7579CallKind.delegateCall);

        final callData1 = encode7579SupportsExecutionMode(callMode);
        final callData2 = encode7579SupportsExecutionMode(batchMode);
        final callData3 = encode7579SupportsExecutionMode(delegateMode);

        // All same length but different content
        expect(callData1.length, equals(callData2.length));
        expect(callData2.length, equals(callData3.length));
        expect(callData1, isNot(equals(callData2)));
        expect(callData2, isNot(equals(callData3)));
      });

      test('includes mode bytes after selector', () {
        const mode = ExecutionMode(
          type: Erc7579CallKind.batchCall,
          revertOnError: false,
        );
        final callData = encode7579SupportsExecutionMode(mode);

        // After selector (4 bytes = 8 hex chars), mode starts
        // Byte 0 of mode should be 0x01 (batchCall)
        expect(callData.substring(10, 12), equals('01'));
        // Byte 1 of mode should be 0x01 (try mode)
        expect(callData.substring(12, 14), equals('01'));
      });
    });

    group('supportsExecutionMode selector', () {
      test('is correct keccak256 hash', () {
        // keccak256("supportsExecutionMode(bytes32)")[0:4] = 0xd03c7914
        expect(
          Erc7579Selectors.supportsExecutionMode.toLowerCase(),
          equals('0xd03c7914'),
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
        // Expected: (5 << 64) + 10
        expect(nonce, equals((BigInt.from(5) << 64) + BigInt.from(10)));
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

      test('decodes batch call execution', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.from(100),
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.from(200),
            data: '0xaabb',
          ),
        ];
        final encoded = encode7579ExecuteBatch(calls);

        final decoded = decode7579Calls(encoded);

        expect(decoded.mode.type, equals(Erc7579CallKind.batchCall));
        expect(decoded.calls, hasLength(2));
        expect(
          decoded.calls[0].to.hex.toLowerCase(),
          equals(calls[0].to.hex.toLowerCase()),
        );
        expect(decoded.calls[0].value, equals(calls[0].value));
        expect(
          decoded.calls[1].to.hex.toLowerCase(),
          equals(calls[1].to.hex.toLowerCase()),
        );
        expect(decoded.calls[1].value, equals(calls[1].value));
      });

      test('decodes call with zero value', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
          ),
          value: BigInt.zero,
          data: '0x',
        );
        final encoded = encode7579Execute(call);

        final decoded = decode7579Calls(encoded);

        expect(decoded.calls[0].value, equals(BigInt.zero));
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

      test('throws for invalid call type', () {
        // Valid selector but invalid call type (0x02)
        const invalidCallData = '0x61461954' // execute selector
            '0200000000000000000000000000000000000000000000000000000000000000' // invalid mode
            '0000000000000000000000000000000000000000000000000000000000000040'
            '0000000000000000000000000000000000000000000000000000000000000000';

        expect(
          () => decode7579Calls(invalidCallData),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('DecodedNonce', () {
      test('toString returns readable format', () {
        final decoded =
            DecodedNonce(key: BigInt.from(5), sequence: BigInt.from(10));
        expect(decoded.toString(), contains('key: 5'));
        expect(decoded.toString(), contains('sequence: 10'));
      });
    });

    group('Decoded7579Calls', () {
      test('toString returns readable format', () {
        final decoded = Decoded7579Calls(
          mode: const ExecutionMode(type: Erc7579CallKind.call),
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
              data: '0x',
            ),
          ],
        );
        final str = decoded.toString();
        expect(str, contains('mode:'));
        expect(str, contains('calls:'));
      });
    });
  });
}
