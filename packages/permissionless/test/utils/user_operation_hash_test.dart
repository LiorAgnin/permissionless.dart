import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

// Expected hashes from viem 2.44.4 `getUserOperationHash` (chainId 11155111)
// over the same user operations.
void main() {
  final chainId = BigInt.from(11155111);
  final delegation =
      EthereumAddress.fromHex('0xe6Cae83BdE06E4c305530e199D7217f42808555B');

  UserOperationV07 base({
    EthereumAddress? factory,
    String? factoryData,
    bool withPaymaster = false,
  }) =>
      UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.from(0x2a),
        factory: factory,
        factoryData: factoryData,
        callData: '0xb61d27f6000000000000000000000000',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(3000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
        paymaster: withPaymaster
            ? EthereumAddress.fromHex(
                '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              )
            : null,
        paymasterVerificationGasLimit:
            withPaymaster ? BigInt.from(50000) : null,
        paymasterPostOpGasLimit: withPaymaster ? BigInt.from(20000) : null,
        paymasterData: withPaymaster ? '0xdeadbeef' : null,
        signature: '0x',
      );

  final withFactoryPaymaster = base(
    factory:
        EthereumAddress.fromHex('0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985'),
    factoryData: '0x5fbfb9cf00ab',
    withPaymaster: true,
  );
  final eip7702 = base(
    factory: eip7702FactoryMarkerAddress,
    factoryData: '0x',
  );

  String hash(
    UserOperationV07 op,
    EntryPointVersion version, {
    EthereumAddress? delegationAddress,
  }) =>
      getUserOperationHash(
        userOperation: op,
        entryPointAddress: EntryPointAddresses.fromVersion(version),
        entryPointVersion: version,
        chainId: chainId,
        eip7702DelegationAddress: delegationAddress,
      );

  group('getUserOperationHash matches viem', () {
    test('v0.7 plain', () {
      expect(
        hash(base(), EntryPointVersion.v07),
        '0x4d54257066897f410407490241665bca61c04313b85bc688a119a3b611a8b278',
      );
    });

    test('v0.7 factory + paymaster', () {
      expect(
        hash(withFactoryPaymaster, EntryPointVersion.v07),
        '0x9683a1363aaedeeca45b9cb566acfb5d8428131003f894ea4eb3ff6262bea45c',
      );
    });

    test('v0.8 plain', () {
      expect(
        hash(base(), EntryPointVersion.v08),
        '0x563393a824d775ad91cbf6817dcd91b4305f38d1aea02c670609ef8571201418',
      );
    });

    test('v0.8 factory + paymaster', () {
      expect(
        hash(withFactoryPaymaster, EntryPointVersion.v08),
        '0xdbf18507bec2aa0bfe669d54b0d29359032e24cf620ece4994249f405604e6de',
      );
    });

    test('v0.8 EIP-7702 marker uses the delegation address', () {
      expect(
        hash(eip7702, EntryPointVersion.v08, delegationAddress: delegation),
        '0xb6fe3fd3f593d172fce7354d0a24dd47d7d82bfe4263d050d1d189bfb9b84a91',
      );
    });

    test('v0.8 EIP-7702 marker without delegation hashes the marker', () {
      expect(
        hash(eip7702, EntryPointVersion.v08),
        '0xdf5bde7a85e6ab1be988147823371e6e7e4e5a07f14fb02b6e8a93ad5db1b034',
      );
    });
  });

  test('v0.6 is rejected', () {
    expect(
      () => hash(base(), EntryPointVersion.v06),
      throwsArgumentError,
    );
  });

  test('entryPointVersionOf maps canonical addresses', () {
    for (final v in EntryPointVersion.values) {
      expect(entryPointVersionOf(EntryPointAddresses.fromVersion(v)), v);
    }
    expect(entryPointVersionOf(zeroAddress), isNull);
  });
}
