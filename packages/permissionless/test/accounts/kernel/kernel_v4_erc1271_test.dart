import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../../helpers/kernel_v4_vectors.dart';

/// Hardhat account #0 — the root/fallback signer of every fixture account.
/// Fixed offline unit-test key, never used on live networks.
const String _rootPrivateKey =
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

/// Hardhat account #1 — the validator/permission module owner in the
/// fixture scenarios, deliberately distinct from the root.
const String _modulePrivateKey =
    '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

/// Account-level ERC-1271 / ERC-7739 signing on Kernel v4 (ticket 08):
/// `signMessage` / `signTypedData` / `sign` produce, byte for byte, the
/// signatures the pinned Kernel v4.0 contracts accepted via
/// `isValidSignature` (`tool/kernel_v4_vectors`) — for root, validator, and
/// permission selection, chain-specific and replayable nested EIP-712, and
/// the stateless enable-mode view path.
void main() {
  final vectors = loadKernelV4Vectors();
  final chainId = BigInt.from(vectors['chainId'] as int);
  final erc1271 = vectors['erc1271'] as Map<String, dynamic>;
  // The app-side typed-data values are emitted once, on the root case; the
  // other TypedDataSign cases sign the same Mail message.
  final mailTypedData = kernelV4MailTypedDataFromCase(
    erc1271['typedDataSignRoot'] as Map<String, dynamic>,
  );

  final root = PrivateKeyOwner(_rootPrivateKey);
  final moduleOwner = PrivateKeyOwner(_modulePrivateKey);

  KernelImmutableECDSA account({
    required Map<String, dynamic> forCase,
    AccountOwner? owner,
    KernelV4Validation validation = const KernelV4Validation.root(),
    KernelV4EnableMode? enableMode,
  }) =>
      createKernelImmutableECDSA(
        owner: owner ?? root,
        chainId: chainId,
        validation: validation,
        enableMode: enableMode,
        // The fixture accounts were deployed by the locally-instantiated
        // factory; their addresses are pinned rather than re-derived — the
        // CREATE2 path has its own vectors.
        address: EthereumAddress.fromHex(forCase['sender'] as String),
      );

  group('root selection', () {
    test('signMessage matches the contract-accepted signature', () async {
      final c = erc1271['personalSignRoot'] as Map<String, dynamic>;
      expect(
        await account(forCase: c).signMessage(c['message'] as String),
        equals(c['signature']),
      );
    });

    test('sign frames the given hash directly (no re-prefixing)', () async {
      // `isValidSignature(hash, …)` wraps the input hash as-is into the
      // PersonalSign struct, so `sign(hashMessage(m))` must equal
      // `signMessage(m)` — a second EIP-191 pass would verify nothing.
      final c = erc1271['personalSignRoot'] as Map<String, dynamic>;
      final acc = account(forCase: c);
      expect(
        await acc.sign(c['hash'] as String),
        equals(await acc.signMessage(c['message'] as String)),
      );
    });

    test('signTypedData matches the contract-accepted signature', () async {
      final c = erc1271['typedDataSignRoot'] as Map<String, dynamic>;
      expect(
        await account(forCase: c).signTypedData(mailTypedData),
        equals(c['signature']),
      );
    });

    test('signTypedDataReplayable signs the sans-chainId wrap', () async {
      final c = erc1271['typedDataSignRoot'] as Map<String, dynamic>;
      final replayable =
          erc1271['typedDataSignReplayable'] as Map<String, dynamic>;
      expect(
        await account(forCase: c).signTypedDataReplayable(mailTypedData),
        equals(replayable['signature']),
      );
    });
  });

  group('validator selection', () {
    test('signMessage carries the validator prefix and its owner\'s signature',
        () async {
      final c = erc1271['personalSignValidator'] as Map<String, dynamic>;
      final acc = account(
        forCase: c,
        owner: moduleOwner,
        validation: KernelV4Validation.validator(
          EthereumAddress.fromHex(c['validator'] as String),
        ),
      );
      expect(
        await acc.signMessage(c['message'] as String),
        equals(c['signature']),
      );
    });

    test('signTypedData composes the prefix with the 7739 tail', () async {
      final c = erc1271['typedDataSignValidator'] as Map<String, dynamic>;
      final acc = account(
        forCase: c,
        owner: moduleOwner,
        validation: KernelV4Validation.validator(
          EthereumAddress.fromHex(c['validator'] as String),
        ),
      );
      expect(await acc.signTypedData(mailTypedData), equals(c['signature']));
    });
  });

  group('permission selection', () {
    test('signMessage carries the permission prefix and signature list',
        () async {
      final c = erc1271['personalSignPermission'] as Map<String, dynamic>;
      final acc = account(
        forCase: c,
        owner: moduleOwner,
        validation: KernelV4Validation.permission(
          c['permissionId'] as String,
          policySignatures: [c['policyData'] as String],
        ),
      );
      expect(
        await acc.signMessage(c['message'] as String),
        equals(c['signature']),
      );
    });

    test('signTypedData keeps the signature list ahead of the 7739 tail',
        () async {
      final c = erc1271['typedDataSignPermission'] as Map<String, dynamic>;
      final acc = account(
        forCase: c,
        owner: moduleOwner,
        validation: KernelV4Validation.permission(
          c['permissionId'] as String,
          policySignatures: [c['policyData'] as String],
        ),
      );
      expect(await acc.signTypedData(mailTypedData), equals(c['signature']));
    });
  });

  group('enable-mode selection (stateless view verification)', () {
    final c = erc1271['enableMode'] as Map<String, dynamic>;

    KernelImmutableECDSA enableAccount({required bool replayable}) => account(
          forCase: c,
          owner: moduleOwner,
          validation: KernelV4Validation.validator(
            EthereumAddress.fromHex(c['validator'] as String),
          ),
          enableMode: KernelV4EnableMode(
            packages: kernelV4PackagesFromCase(c),
            rootOwner: root,
            replayableEnableSignature: replayable,
          ),
        );

    test('signMessage produces the enable-framed signature', () async {
      expect(
        await enableAccount(replayable: false)
            .signMessage(c['message'] as String),
        equals(c['signature']),
      );
    });

    test('a replayable enable signs the sans-chainId install digest', () async {
      expect(
        await enableAccount(replayable: true)
            .signMessage(c['message'] as String),
        equals(c['replayableSignature']),
      );
    });

    test('signTypedData appends the 7739 tail after the enable blob', () async {
      final typed = erc1271['typedDataSignEnable'] as Map<String, dynamic>;
      expect(
        await enableAccount(replayable: false).signTypedData(mailTypedData),
        equals(typed['signature']),
      );
    });

    test('enable mode with root validation is rejected before the chain', () {
      final acc = account(
        forCase: c,
        owner: moduleOwner,
        enableMode: KernelV4EnableMode(
          packages: kernelV4PackagesFromCase(c),
          rootOwner: root,
        ),
      );
      expect(
        () => acc.signMessage(c['message'] as String),
        throwsArgumentError,
      );
    });
  });
}
