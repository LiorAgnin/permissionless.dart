import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../../helpers/kernel_v4_vectors.dart';

/// Hardhat account #0 — the account root in the fixture scenarios. Fixed
/// offline unit-test key, never used on live networks.
const String _rootPrivateKey =
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

/// Hardhat account #1 — the session key: owner of the permission's signer
/// module, deliberately distinct from the root.
const String _sessionPrivateKey =
    '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

/// The end-to-end offline session-key path on Kernel v4 (ticket 07):
/// compose a permission from policies + one signer under a PermissionId,
/// grant it (at deployment or via batch install), send a UserOperation
/// under it, and revoke it — every encoding pinned to bytes the pinned
/// Kernel v4 contracts accepted or executed (`tool/kernel_v4_vectors`).
void main() {
  final vectors = loadKernelV4Vectors();
  final chainId = BigInt.from(vectors['chainId'] as int);
  final p = vectors['permissionUserOp'] as Map<String, dynamic>;
  final mm = vectors['moduleManagement'] as Map<String, dynamic>;
  final executeSelector = mm['executeSelector'] as String;

  final root = PrivateKeyOwner(_rootPrivateKey);
  final session = PrivateKeyOwner(_sessionPrivateKey);

  /// The session-key permission: one proof policy plus the ECDSA signer
  /// module owned by the session key, composed with the typed builders in
  /// the order the Kernel enforces (policies first, signer finalizes).
  List<KernelV4Install> sessionKeyPackages({
    required String permissionId,
    required EthereumAddress policy,
    required EthereumAddress signerModule,
  }) =>
      [
        KernelV4Install.policy(module: policy, permissionId: permissionId),
        KernelV4Install.signer(
          module: signerModule,
          permissionId: permissionId,
          moduleData: session.address.hex,
          hook: KernelV4HookSentinels.notInstalled,
          allowedSelectors: [executeSelector],
        ),
      ];

  group('granting the session key at deployment', () {
    // The fixture account was deployed by the real KernelFactory with these
    // packages (deployECDSA, factory nonce 101). The CREATE2 salt commits to
    // every package byte, so reproducing the sender address offline proves
    // the typed builders emit the exact policy/signer internalData layouts
    // the contracts consumed.
    test('typed packages reproduce the on-chain CREATE2 sender', () async {
      final account = createKernelImmutableECDSA(
        owner: root,
        chainId: chainId,
        index: BigInt.from(101),
        additionalPackages: sessionKeyPackages(
          permissionId: p['permissionId'] as String,
          policy: EthereumAddress.fromHex(p['policy'] as String),
          signerModule: EthereumAddress.fromHex(p['signerModule'] as String),
        ),
        customAddresses: KernelV4Addresses(
          kernelUUPS:
              EthereumAddress.fromHex(vectors['localKernelUUPS'] as String),
          kernelImmutableECDSA: EthereumAddress.fromHex(
            vectors['localKernelImmutableECDSA'] as String,
          ),
          factory: EthereumAddress.fromHex(vectors['localFactory'] as String),
          staker: KernelV4Addresses.predicted.staker,
        ),
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((p['sender'] as String).toLowerCase()),
      );
    });
  });

  group('granting the session key after deployment', () {
    final batch = mm['batchInstall'] as Map<String, dynamic>;
    final sender = EthereumAddress.fromHex(batch['sender'] as String);
    final fixturePackages =
        (batch['packages'] as List<dynamic>).cast<Map<String, dynamic>>();
    final packages = sessionKeyPackages(
      permissionId: mm['permissionId'] as String,
      policy: EthereumAddress.fromHex(fixturePackages[0]['module'] as String),
      signerModule:
          EthereumAddress.fromHex(fixturePackages[1]['module'] as String),
    );

    test('the batch install calldata matches the executed bytes', () {
      // The batch entrypoint is the required path for permission installs —
      // it runs the Kernel's completeness check (policies, then the signer
      // that finalizes the permission, in one batch).
      expect(
        encodeKernelV4BatchInstallCalldata(packages),
        equals(batch['callData']),
      );
    });

    test('a signer-first batch is rejected before it reaches the chain', () {
      expect(
        () => encodeKernelV4BatchInstallCalldata(packages.reversed.toList()),
        throwsArgumentError,
      );
    });

    test('the install rides an ordinary root-signed UserOperation', () async {
      // Granting a session key post-deployment is a self-call: the root
      // signs a UserOperation whose callData executes the batch install on
      // the account itself.
      final rootAccount = createKernelImmutableECDSA(
        owner: root,
        chainId: chainId,
      );
      final template =
          kernelV4UserOpFromCase(vectors['rootUserOp'] as Map<String, dynamic>);
      final installOp = UserOperationV07(
        sender: sender,
        nonce: template.nonce,
        callData: rootAccount.encodeCalls([
          Call(to: sender, data: encodeKernelV4BatchInstallCalldata(packages)),
        ]),
        callGasLimit: template.callGasLimit,
        verificationGasLimit: template.verificationGasLimit,
        preVerificationGas: template.preVerificationGas,
        maxFeePerGas: template.maxFeePerGas,
        maxPriorityFeePerGas: template.maxPriorityFeePerGas,
      );

      // The nonce routes to root validation — no mode bits, no vId.
      expect(rootAccount.nonceKey, equals(BigInt.zero));

      // The wrapped call decodes back to the self-call install.
      final decoded = rootAccount.decodeCalls(installOp.callData);
      expect(decoded, hasLength(1));
      expect(decoded.single.to, equals(sender));
      expect(decoded.single.data, equals(batch['callData']));

      // Root signing stays the raw 65-byte scheme — installing a permission
      // needs no special signature framing.
      final signature = await rootAccount.signUserOperation(installOp);
      expect(Hex.byteLength(signature), equals(65));
    });
  });

  group('sending under the PermissionId', () {
    final sessionAccount = createKernelImmutableECDSA(
      owner: session,
      chainId: chainId,
      validation: KernelV4Validation.permission(
        p['permissionId'] as String,
        policySignatures: [p['policyData'] as String],
      ),
      nonceKey: BigInt.from(p['nonceKey'] as int),
    );

    test('the nonce routes to the permission (vType 0x02)', () {
      expect(
        sessionAccount.nonceKey,
        equals(BigInt.parse(p['nonce'] as String) >> 64),
      );
    });

    test('the signature is the framed list the contract accepted', () async {
      // One chunk per policy in install order, the session signer's 65-byte
      // signature last — the exact bytes validateUserOp returned 0 for.
      final signature =
          await sessionAccount.signUserOperation(kernelV4UserOpFromCase(p));
      expect(signature, equals(p['signature']));
      expect(p['validationData'], equals(0));
    });

    test('the oracle proved the negatives the framing protects against', () {
      // Recorded on-chain outcomes: a non-session signer, tampered policy
      // data, and the estimation stub all fail cleanly (validationData 1).
      expect(p['wrongSignerValidationData'], equals(1));
      expect(p['wrongPolicyDataValidationData'], equals(1));
      expect(p['stubSignatureValidationData'], equals(1));
      expect(
        sessionAccount.getStubSignature(),
        equals(p['stubSignature']),
      );
    });
  });

  group('revoking the session key', () {
    final batch = mm['batchInstall'] as Map<String, dynamic>;
    final sender = EthereumAddress.fromHex(batch['sender'] as String);
    final uninstalls =
        (mm['uninstalls'] as List<dynamic>).cast<Map<String, dynamic>>();
    Map<String, dynamic> uninstallCase(String name) =>
        uninstalls.singleWhere((c) => c['name'] == name);
    final calldatas = kernelV4PermissionUninstallCalldatas(
      permissionId: mm['permissionId'] as String,
      policies: [
        EthereumAddress.fromHex(uninstallCase('policy')['module'] as String),
      ],
      signer: EthereumAddress.fromHex(
        uninstallCase('signer')['module'] as String,
      ),
    );

    test('the helper emits the contract-required order, executed bytes', () {
      // The Kernel rejects removing the signer while policies remain
      // (the fixture proved the revert on-chain), so the helper hard-codes
      // the safe order: policies LIFO, signer last.
      expect(mm['signerBeforePoliciesReverts'], isTrue);
      expect(calldatas, [
        uninstallCase('policy')['callData'],
        uninstallCase('signer')['callData'],
      ]);
    });

    test('revocation batches into one execute call, order intact', () {
      final rootAccount = createKernelImmutableECDSA(
        owner: root,
        chainId: chainId,
      );
      final callData = rootAccount.encodeCalls([
        for (final data in calldatas) Call(to: sender, data: data),
      ]);
      // The batch decodes back with the order intact: policy first,
      // signer last.
      final decoded = rootAccount.decodeCalls(callData);
      expect(decoded, hasLength(2));
      expect(decoded[0].data, equals(uninstallCase('policy')['callData']));
      expect(decoded[1].data, equals(uninstallCase('signer')['callData']));
    });
  });
}
