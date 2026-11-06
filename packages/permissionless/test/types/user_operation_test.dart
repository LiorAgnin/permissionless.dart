import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('UserOperationV07 JSON', () {
    test('an EIP-7702 operation survives a toJson/fromJson round trip', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.one,
        factory: eip7702FactoryMarkerAddress,
        factoryData: '0x',
        callData: '0xdeadbeef',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
      );

      final json = op.toJson();
      expect(json['factory'], '0x7702');

      final decoded = UserOperationV07.fromJson(json);
      expect(decoded.factory, eip7702FactoryMarkerAddress);
      expect(decoded.toJson(), json);
    });
  });
}
