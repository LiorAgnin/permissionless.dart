import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// The one PrivateKeyOwner test: every signing mode against Foundry `cast`
/// 1.5.1 for a throwaway key (not a Hardhat/anvil default), so a regression
/// in key derivation, prefixing, EIP-712 hashing or `r‖s‖v` packing fails here.
///
/// Key: `cast keccak "permissionless.dart private_key_owner_test throwaway key"`
void main() {
  const privateKey =
      '0x4c335d435862cef4957f979164fd97950e198ea9156c68f84fa02700fdb68245';
  const hash =
      '0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63';

  final owner = PrivateKeyOwner(privateKey);

  test('address is the secp256k1 address of the key', () {
    // cast wallet address --private-key <key>
    expect(
      owner.address,
      equals(
        EthereumAddress.fromHex('0x7Bf08A44eD911CdB9B60b9C9E9Cc2Fd50e129442'),
      ),
    );
  });

  test('publicKey is the uncompressed key without the 04 prefix', () {
    // cast wallet public-key --private-key <key>
    expect(
      Hex.fromBytes(owner.publicKey),
      equals(
        '0x40931d19be65fbb2e25c8b10ea0858078f08685f6922022aaa1018c77c260ac2'
        'be666aa52e8d967f9c0ef260bf6786e12ff70e1c6d917f3eb4b43c5d2e2b01a4',
      ),
    );
  });

  test('signRawHash signs the 32 bytes with no prefix', () async {
    // cast wallet sign --no-hash --private-key <key> <hash>
    expect(
      await owner.signRawHash(hash),
      equals(
        '0xa9255fb4caf33f2540d8eede1c92a260d800c6a90520d981a8679fdf2b6ea3c8'
        '0b3bfbdcb51f74360ad045a5e16d8d1c134d57f3e001a8f12e3240f782dda301'
        '1c',
      ),
    );
  });

  test('signPersonalMessage EIP-191-signs the hash bytes', () async {
    // cast wallet sign --private-key <key> <hash>
    // (cast decodes 0x-hex messages to bytes; equal to
    // `cast wallet sign --no-hash` over
    // `cast keccak 0x19457468657265756d205369676e6564204d6573736167653a0a3332<hash>`)
    expect(
      await owner.signPersonalMessage(hash),
      equals(
        '0x53d44e265737f06a1d68e85d764caffb024f3dc9d4661cf303540c3bbbdb4d15'
        '0768c69383550ac3eb319fe691a994e84994d133d852c50ea38d238cb8bc3755'
        '1c',
      ),
    );
  });

  test('signTypedData signs the EIP-712 digest with no prefix', () async {
    // EIP-712 spec "Ether Mail" example (nested Person struct).
    // cast wallet sign --data --from-file --private-key <key> mail.json
    // where mail.json is this typed data with the EIP712Domain type listed.
    final typedData = TypedData(
      domain: TypedDataDomain(
        name: 'Ether Mail',
        version: '1',
        chainId: BigInt.one,
        verifyingContract: EthereumAddress.fromHex(
          '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
        ),
      ),
      types: {
        'Person': [
          const TypedDataField(name: 'name', type: 'string'),
          const TypedDataField(name: 'wallet', type: 'address'),
        ],
        'Mail': [
          const TypedDataField(name: 'from', type: 'Person'),
          const TypedDataField(name: 'to', type: 'Person'),
          const TypedDataField(name: 'contents', type: 'string'),
        ],
      },
      primaryType: 'Mail',
      message: {
        'from': {
          'name': 'Cow',
          'wallet': '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
        },
        'to': {
          'name': 'Bob',
          'wallet': '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
        },
        'contents': 'Hello, Bob!',
      },
    );

    expect(
      await owner.signTypedData(typedData),
      equals(
        '0x595ac0bce088d465a65240451067dce74b5275f734db6ee1efc621aec8519d77'
        '77340bb2889ef85d8a4d4d6bbd8d62efd79ee5e2d7fb9ba477204fe1353f39a4'
        '1c',
      ),
    );
  });
}
