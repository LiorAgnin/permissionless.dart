import 'package:permissionless/permissionless.dart';
// Package-internal helper, tested directly.
import 'package:permissionless/src/clients/bundler/user_operation_request.dart';
import 'package:test/test.dart';

final _sender =
    EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
final _chainId = BigInt.from(11155111);
final _recipient =
    EthereumAddress.fromHex('0x70997970C51812dc3A010C7d01b75Ec5Bb3E7DcF');

void main() {
  group('userOperationRequestJson', () {
    final op = UserOperationV07(
      sender: _sender,
      nonce: BigInt.zero,
      factory: eip7702FactoryMarkerAddress,
      factoryData: '0x',
      callData: '0x',
      callGasLimit: BigInt.one,
      verificationGasLimit: BigInt.one,
      preVerificationGas: BigInt.one,
      maxFeePerGas: BigInt.one,
      maxPriorityFeePerGas: BigInt.one,
      signature: '0x',
    );

    test('adds eip7702Auth and shortens the factory marker', () {
      final auth = Eip7702Authorization(
        chainId: _chainId,
        address: _recipient,
        nonce: BigInt.from(5),
        v: 28,
        r: '0x${'01' * 32}',
        s: '0x${'02' * 32}',
      );

      final json = userOperationRequestJson(op, authorization: auth);

      // viem formatAuthorization (account-abstraction/utils/formatters/
      // userOperationRequest.ts): numberToHex(chainId) — `cast to-hex
      // 11155111` = 0xaa36a7 — numberToHex(nonce), r/s as 32-byte hex and
      // numberToHex(yParity, {size: 1}); v 28 is yParity 1.
      expect(json['eip7702Auth'], {
        'chainId': '0xaa36a7',
        'address': '0x70997970c51812dc3a010c7d01b75ec5bb3e7dcf',
        'nonce': '0x5',
        'yParity': '0x01',
        'r': '0x${'01' * 32}',
        's': '0x${'02' * 32}',
      });
      expect(json['factory'], '0x7702');
    });

    test('without authorization omits eip7702Auth', () {
      final json = userOperationRequestJson(op);

      expect(json.containsKey('eip7702Auth'), isFalse);
      expect(json['factory'], '0x7702');
    });
  });
}
