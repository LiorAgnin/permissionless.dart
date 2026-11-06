import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('CallReceipt', () {
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

    // EIP-5792 / viem getCallsStatus: 100–199 pending, 200–299 success,
    // 300–699 failure; legacy strings are case-insensitive.
    test('fromJson maps status codes at the EIP-5792 range boundaries', () {
      CallsStatusType statusOf(Object code) => CallsStatus.fromJson({
            'id': '0x',
            'version': '1.0',
            'chainId': '0x1',
            'statusCode': code,
            'atomic': true,
          }).status;

      const pending = CallsStatusType.pending;
      const success = CallsStatusType.success;
      const failure = CallsStatusType.failure;
      <Object, CallsStatusType>{
        99: failure,
        100: pending,
        199: pending,
        200: success,
        299: success,
        300: failure,
        699: failure,
        '0xc8': success,
        'confirmed': success,
        'pending': pending,
      }.forEach((code, expected) {
        expect(statusOf(code), equals(expected), reason: 'statusCode $code');
      });
    });

    test('fromJson accepts wallet `status` field as numeric code', () {
      final status = CallsStatus.fromJson({
        'id': '0xdead',
        'version': '2.0.0',
        'chainId': '0x1',
        'status': 200,
        'atomic': true,
      });
      expect(status.status, equals(CallsStatusType.success));
      expect(status.statusCode, equals(200));
    });

    test('fromJson handles legacy string CONFIRMED and PENDING', () {
      final confirmed = CallsStatus.fromJson({
        'id': '0x1',
        'version': '1.0',
        'chainId': '0x1',
        'status': 'CONFIRMED',
        'atomic': true,
      });
      expect(confirmed.status, equals(CallsStatusType.success));
      expect(confirmed.statusCode, equals(200));

      final pending = CallsStatus.fromJson({
        'id': '0x1',
        'version': '1.0',
        'chainId': '0x1',
        'statusCode': 'PENDING',
        'atomic': true,
      });
      expect(pending.status, equals(CallsStatusType.pending));
      expect(pending.statusCode, equals(100));
    });

    test('fromJson accepts numeric status codes as strings', () {
      final status = CallsStatus.fromJson({
        'id': '0x1',
        'version': '1.0',
        'chainId': '0x1',
        'statusCode': '100',
        'atomic': true,
      });
      expect(status.status, equals(CallsStatusType.pending));
      expect(status.statusCode, equals(100));
    });

    test('parseCallsStatusCode accepts hex status strings', () {
      for (final raw in ['0xc8', '0XC8']) {
        expect(
          CallsStatus.parseCallsStatusCode(raw),
          equals((status: CallsStatusType.success, statusCode: 200)),
          reason: raw,
        );
      }
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
