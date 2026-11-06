import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

const _privateKey =
    '0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318';
final _delegate =
    EthereumAddress.fromHex('0xe6Cdaa14C4d8a1f0dd8bb2c0b1B4d8E0Bff4E8F6');

void main() {
  // Expected values from Foundry 1.5.1:
  // `cast wallet sign-auth <_delegate> --private-key <_privateKey>
  //   --chain <chainId> --nonce <nonce>`, decoded from the signed RLP.
  // The nonces straddle the RLP single-byte rule (127 / 128) and the
  // 5-byte integer case; chain 0 is the chain-agnostic authorization.
  final vectors = [
    (
      chainId: 0,
      nonce: BigInt.zero,
      yParity: '0x00',
      r: '0x0a495836b612b305702fae1f3601e629a10bae89bd5931087679d8451b3fe09c',
      s: '0x17e4968d0d812d4e899c13ed1d9d39227aea2e4e85c9ea6c5c1ab30e7341e85b',
    ),
    (
      chainId: 1,
      nonce: BigInt.zero,
      yParity: '0x01',
      r: '0x11098421b3a095fd6f3b612908609d5c4acbc884ed0704f36b3bbfe8084b2ee5',
      s: '0x76faaab5e4ed246f07e86445542e842bac2904dfec6e19c63ed794a6f086d8c5',
    ),
    (
      chainId: 1,
      nonce: BigInt.from(127),
      yParity: '0x01',
      r: '0x8b74f0f42bfdd6da5351f2b1592e5a8cd239ce32bd79f375cb46adeb0bd9289d',
      s: '0x3b73e0139ed635855bb5133fb19577faf1d8ff5bdfc8e1eeb7a6b4e5c5e2ba5e',
    ),
    (
      chainId: 1,
      nonce: BigInt.from(128),
      yParity: '0x01',
      r: '0x03fecfdc20e0fce92202d9e7cf27136b53282d97fb8f435a05006a0a6c799e80',
      s: '0x3ea99e20469047f0e42f9832445dce1ddd0bbdd05989b5dcbe16b84cc78d8a05',
    ),
    (
      chainId: 11155111,
      nonce: BigInt.from(7),
      yParity: '0x01',
      r: '0x3b2b6acca22510172cc25c4fbf2c4cb6ba144a6dc7f37c540d4ac52e80196074',
      s: '0x7b4d91349cc279ae4e91ff67f11d27435cfec4ff532d521e79d85363899cfdf4',
    ),
    (
      chainId: 1,
      nonce: BigInt.parse('1099511627776'),
      yParity: '0x00',
      r: '0x07d98aca3aa92d69d38c211dd0589c90f272bc9e7c936e9c191297697523d0be',
      s: '0x79899b174d4232cff9c48bc53c7552a7f16e7da19a5d2a86a96cf05263609eb9',
    ),
  ];

  group('Eip7702Authorization.sign matches cast wallet sign-auth', () {
    for (final v in vectors) {
      test('chain ${v.chainId}, nonce ${v.nonce}', () async {
        final auth = await Eip7702Authorization.sign(
          chainId: BigInt.from(v.chainId),
          contractAddress: _delegate,
          nonce: v.nonce,
          privateKey: _privateKey,
        );
        final rpc = auth.toRpcFormat();
        expect(rpc['yParity'], v.yParity);
        expect(rpc['r'], v.r);
        expect(rpc['s'], v.s);
      });
    }
  });

  // viem serializes a signed authorization with `yParity`, never `v`
  // (account-abstraction/utils/formatters/userOperationRequest.ts
  // formatAuthorization; utils/formatters/transactionRequest.ts falls back
  // to `v` only when yParity is absent). chainId: `cast to-hex 11155111`.
  test('toJson uses the yParity wire shape, not v', () async {
    final auth = await Eip7702Authorization.sign(
      chainId: BigInt.from(11155111),
      contractAddress: _delegate,
      nonce: BigInt.from(7),
      privateKey: _privateKey,
    );
    expect(auth.toJson(), {
      'chainId': '0xaa36a7',
      'address': '0xe6cdaa14c4d8a1f0dd8bb2c0b1b4d8e0bff4e8f6',
      'nonce': '0x7',
      'yParity': vectors[4].yParity,
      'r': vectors[4].r,
      's': vectors[4].s,
    });
  });

  group('toRpcFormat', () {
    // Wallets (viem signAuthorization, eth_signAuthorization) report the
    // recovery id as yParity 0/1; the constructor documents v as the
    // recovery id, so both forms must serialize the same yParity.
    for (final (v, yParity) in [(0, '0x00'), (1, '0x01'), (27, '0x00')]) {
      test('v = $v serializes yParity $yParity', () {
        final auth = Eip7702Authorization(
          chainId: BigInt.one,
          address: _delegate,
          nonce: BigInt.zero,
          v: v,
          r: vectors[1].r,
          s: vectors[1].s,
        );
        expect(auth.toRpcFormat()['yParity'], yParity);
      });
    }
  });
}
