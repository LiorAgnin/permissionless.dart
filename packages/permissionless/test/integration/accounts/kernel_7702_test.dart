@Tags(['integration'])
library;

import 'dart:io';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Kernel7702 on-chain checks.
///
/// Kernel7702 needs both a chain carrying the Kernel v4 stack (no public
/// deployments exist yet) *and* EIP-7702 semantics — a delegated EOA running
/// the implementation's code. Like the other Kernel v4 integration tests,
/// these run against an explicitly configured RPC (typically a local anvil
/// where the release recipe has been executed) and skip cleanly everywhere
/// else; the delegation itself is simulated with `anvil_setCode`, so a
/// non-anvil RPC also skips rather than fails.
///
/// Environment variables:
/// - `KERNEL_V4_RPC_URL`: RPC of a chain carrying the Kernel v4 stack
void main() {
  final rpcUrl = Platform.environment['KERNEL_V4_RPC_URL'];

  const skipNoRpc = 'Skipping: KERNEL_V4_RPC_URL not set '
      '(no public Kernel v4 deployments exist yet)';

  /// Hardhat account #2 — the same dedicated Kernel7702 EOA key the offline
  /// fixtures use; never used on live networks.
  final owner = PrivateKeyEip7702KernelOwner(
    '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
  );

  /// `isValidSignature(bytes32,bytes)` calldata.
  String erc1271CallData(String hash, String signature) => Hex.concat([
        '0x1626ba7e',
        AbiEncoder.encodeBytes32(hash),
        AbiEncoder.encodeUint256(BigInt.from(64)), // offset of `signature`
        AbiEncoder.encodeBytes(signature),
      ]);

  group('Kernel7702 ERC-1271 against delegated code', () {
    test(
      'raw and nested signatures verify on the delegated EOA',
      () async {
        final client = createPublicClient(url: rpcUrl!);
        try {
          final implementation = KernelV4Addresses.predicted.kernel7702!;
          if (!await client.isDeployed(implementation)) {
            markTestSkipped(
              'Skipping: Kernel7702 implementation not deployed at '
              '${implementation.hex} on this chain',
            );
            return;
          }

          // Simulate an active delegation: place the implementation's
          // runtime code at the EOA (`address(this)` becomes the EOA in
          // every call — the semantics the 7702 designator provides).
          final implementationCode = await client.getCode(implementation);
          try {
            await client.rpcClient.call(
              'anvil_setCode',
              [owner.address.hex, implementationCode],
            );
          } on Exception {
            markTestSkipped(
              'Skipping: anvil_setCode unavailable on this RPC '
              '(needed to simulate the EIP-7702 delegation)',
            );
            return;
          }

          final account = createKernel7702(
            owner: owner,
            chainId: await client.getChainId(),
            publicClient: client,
          );
          const message = 'Kernel7702 integration';
          final hash = hashMessage(message);

          // Raw path — Kernel7702-only: a bare 65-byte EOA signature over
          // the app hash, no prefix, no ERC-7739 wrap.
          final raw = await account.signErc1271Raw(hash);
          expect(
            await client.call(
              Call(to: owner.address, data: erc1271CallData(hash, raw)),
            ),
            startsWith('0x1626ba7e'),
          );

          // Nested path — the standard prefixed ERC-7739 PersonalSign flow
          // shared with the factory-deployed v4 accounts.
          final nested = await account.signMessage(message);
          expect(
            await client.call(
              Call(to: owner.address, data: erc1271CallData(hash, nested)),
            ),
            startsWith('0x1626ba7e'),
          );
        } finally {
          client.close();
        }
      },
      skip: rpcUrl == null || rpcUrl.isEmpty ? skipNoRpc : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
