import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('CallsStatusType', () {
    test('has pending value', () {
      expect(CallsStatusType.pending.name, equals('pending'));
    });

    test('has success value', () {
      expect(CallsStatusType.success.name, equals('success'));
    });

    test('has failure value', () {
      expect(CallsStatusType.failure.name, equals('failure'));
    });
  });

  group('CallReceipt', () {
    test('creates with required fields', () {
      final receipt = CallReceipt(
        status: 'success',
        logs: [],
        blockHash: '0x1234',
        blockNumber: BigInt.from(12345),
        gasUsed: BigInt.from(21000),
        transactionHash: '0xabcd',
      );

      expect(receipt.status, equals('success'));
      expect(receipt.logs, isEmpty);
      expect(receipt.blockHash, equals('0x1234'));
      expect(receipt.blockNumber, equals(BigInt.from(12345)));
      expect(receipt.gasUsed, equals(BigInt.from(21000)));
      expect(receipt.transactionHash, equals('0xabcd'));
    });

    test('creates with logs', () {
      final receipt = CallReceipt(
        status: 'success',
        logs: [
          {
            'address': '0x1234',
            'topics': ['0xtopic1', '0xtopic2'],
            'data': '0xdata',
          },
        ],
        blockHash: '0x1234',
        blockNumber: BigInt.from(12345),
        gasUsed: BigInt.from(21000),
        transactionHash: '0xabcd',
      );

      expect(receipt.logs.length, equals(1));
      expect(receipt.logs.first['address'], equals('0x1234'));
    });

    test('fromJson parses complete JSON', () {
      final json = {
        'status': 'success',
        'logs': [
          {'address': '0x1234', 'topics': <String>[], 'data': '0x'},
        ],
        'blockHash':
            '0x1234567890123456789012345678901234567890123456789012345678901234',
        'blockNumber': '0x3039', // 12345 in hex
        'gasUsed': '0x5208', // 21000 in hex
        'transactionHash':
            '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
      };

      final receipt = CallReceipt.fromJson(json);

      expect(receipt.status, equals('success'));
      expect(receipt.logs.length, equals(1));
      expect(receipt.blockNumber, equals(BigInt.from(12345)));
      expect(receipt.gasUsed, equals(BigInt.from(21000)));
    });

    test('fromJson handles BigInt values', () {
      final json = {
        'status': 'success',
        'logs': <Map<String, dynamic>>[],
        'blockHash': '0x1234',
        'blockNumber': BigInt.from(12345),
        'gasUsed': BigInt.from(21000),
        'transactionHash': '0xabcd',
      };

      final receipt = CallReceipt.fromJson(json);

      expect(receipt.blockNumber, equals(BigInt.from(12345)));
      expect(receipt.gasUsed, equals(BigInt.from(21000)));
    });

    test('toJson produces correct output', () {
      final receipt = CallReceipt(
        status: 'success',
        logs: [],
        blockHash: '0x1234',
        blockNumber: BigInt.from(12345),
        gasUsed: BigInt.from(21000),
        transactionHash: '0xabcd',
      );

      final json = receipt.toJson();

      expect(json['status'], equals('success'));
      expect(json['blockNumber'], equals('0x3039'));
      expect(json['gasUsed'], equals('0x5208'));
    });
  });

  group('CallsStatus', () {
    test('creates pending status', () {
      final status = CallsStatus(
        id: '0x1234',
        version: '1.0',
        chainId: BigInt.from(1),
        status: CallsStatusType.pending,
        statusCode: 100,
        atomic: true,
      );

      expect(status.id, equals('0x1234'));
      expect(status.version, equals('1.0'));
      expect(status.chainId, equals(BigInt.one));
      expect(status.status, equals(CallsStatusType.pending));
      expect(status.statusCode, equals(100));
      expect(status.atomic, isTrue);
      expect(status.receipts, isNull);
    });

    test('creates success status with receipts', () {
      final receipt = CallReceipt(
        status: 'success',
        logs: [],
        blockHash: '0x1234',
        blockNumber: BigInt.from(12345),
        gasUsed: BigInt.from(21000),
        transactionHash: '0xabcd',
      );

      final status = CallsStatus(
        id: '0x1234',
        version: '1.0',
        chainId: BigInt.from(1),
        status: CallsStatusType.success,
        statusCode: 200,
        atomic: true,
        receipts: [receipt],
      );

      expect(status.status, equals(CallsStatusType.success));
      expect(status.statusCode, equals(200));
      expect(status.receipts?.length, equals(1));
    });

    test('creates failure status', () {
      final status = CallsStatus(
        id: '0x1234',
        version: '1.0',
        chainId: BigInt.from(1),
        status: CallsStatusType.failure,
        statusCode: 500,
        atomic: true,
      );

      expect(status.status, equals(CallsStatusType.failure));
      expect(status.statusCode, equals(500));
    });

    test('fromJson parses pending status', () {
      final json = {
        'id': '0x1234',
        'version': '1.0',
        'chainId': '0x1',
        'statusCode': 100,
        'atomic': true,
      };

      final status = CallsStatus.fromJson(json);

      expect(status.status, equals(CallsStatusType.pending));
      expect(status.statusCode, equals(100));
    });

    test('fromJson parses success status', () {
      final json = {
        'id': '0x1234',
        'version': '1.0',
        'chainId': BigInt.from(1),
        'statusCode': 200,
        'atomic': true,
        'receipts': [
          {
            'status': 'success',
            'logs': <Map<String, dynamic>>[],
            'blockHash': '0x1234',
            'blockNumber': '0x1',
            'gasUsed': '0x5208',
            'transactionHash': '0xabcd',
          },
        ],
      };

      final status = CallsStatus.fromJson(json);

      expect(status.status, equals(CallsStatusType.success));
      expect(status.receipts?.length, equals(1));
    });

    test('fromJson parses failure status', () {
      final json = {
        'id': '0x1234',
        'version': '1.0',
        'chainId': '0x1',
        'statusCode': 500,
        'atomic': true,
      };

      final status = CallsStatus.fromJson(json);

      expect(status.status, equals(CallsStatusType.failure));
    });

    test('fromJson maps status codes correctly', () {
      // 100-199 is pending
      expect(
        CallsStatus.fromJson({
          'id': '0x',
          'version': '1.0',
          'chainId': '0x1',
          'statusCode': 150,
          'atomic': true,
        }).status,
        equals(CallsStatusType.pending),
      );

      // 200-299 is success
      expect(
        CallsStatus.fromJson({
          'id': '0x',
          'version': '1.0',
          'chainId': '0x1',
          'statusCode': 201,
          'atomic': true,
        }).status,
        equals(CallsStatusType.success),
      );

      // 300+ is failure
      expect(
        CallsStatus.fromJson({
          'id': '0x',
          'version': '1.0',
          'chainId': '0x1',
          'statusCode': 400,
          'atomic': true,
        }).status,
        equals(CallsStatusType.failure),
      );
    });

    test('toJson produces correct output', () {
      final status = CallsStatus(
        id: '0x1234',
        version: '1.0',
        chainId: BigInt.from(137),
        status: CallsStatusType.success,
        statusCode: 200,
        atomic: true,
      );

      final json = status.toJson();

      expect(json['id'], equals('0x1234'));
      expect(json['version'], equals('1.0'));
      expect(json['chainId'], equals('0x89')); // 137 in hex
      expect(json['status'], equals('success'));
      expect(json['statusCode'], equals(200));
      expect(json['atomic'], isTrue);
      expect(json.containsKey('receipts'), isFalse);
    });

    test('toJson includes receipts when present', () {
      final status = CallsStatus(
        id: '0x1234',
        version: '1.0',
        chainId: BigInt.from(1),
        status: CallsStatusType.success,
        statusCode: 200,
        atomic: true,
        receipts: [
          CallReceipt(
            status: 'success',
            logs: [],
            blockHash: '0x1234',
            blockNumber: BigInt.from(1),
            gasUsed: BigInt.from(21000),
            transactionHash: '0xabcd',
          ),
        ],
      );

      final json = status.toJson();

      expect(json.containsKey('receipts'), isTrue);
      expect((json['receipts'] as List).length, equals(1));
    });
  });
}
