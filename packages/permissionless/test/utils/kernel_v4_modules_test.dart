import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../helpers/kernel_v4_vectors.dart';

/// Byte-matches the Kernel v4 module-management encoders against the
/// `moduleManagement` fixture section — calldata the Foundry oracle executed
/// against a real factory-deployed Kernel v4 account (see
/// `tool/kernel_v4_vectors/`).
void main() {
  final vectors = loadKernelV4Vectors();
  final mm = vectors['moduleManagement'] as Map<String, dynamic>;
  final chainId = BigInt.from(vectors['chainId'] as int);
  final sender = EthereumAddress.fromHex(mm['sender'] as String);
  final hookModule = EthereumAddress.fromHex(mm['hookModule'] as String);
  final fallbackSelector = mm['fallbackSelector'] as String;
  final executeSelector = mm['executeSelector'] as String;
  final permissionId = mm['permissionId'] as String;
  final installs =
      (mm['installs'] as List<dynamic>).cast<Map<String, dynamic>>();
  final uninstalls =
      (mm['uninstalls'] as List<dynamic>).cast<Map<String, dynamic>>();

  Map<String, dynamic> installCase(String name) =>
      installs.singleWhere((c) => c['name'] == name);
  Map<String, dynamic> uninstallCase(String name) =>
      uninstalls.singleWhere((c) => c['name'] == name);

  /// The typed builder equivalent of each fixture install case — the fixture
  /// holds the oracle-accepted bytes; this map holds the constructor calls a
  /// developer would write to produce them.
  final typedInstalls =
      <String, KernelV4Install Function(Map<String, dynamic>)>{
    'hook': (c) => KernelV4Install.hook(
          module: EthereumAddress.fromHex(c['module'] as String),
        ),
    'validatorSentinelHook': (c) => KernelV4Install.validator(
          module: EthereumAddress.fromHex(c['module'] as String),
          moduleData: c['moduleData'] as String,
          hook: KernelV4HookSentinels.installedNoHook,
          allowedSelectors: [executeSelector],
        ),
    'validatorEmptyInternalData': (c) => KernelV4Install.validator(
          module: EthereumAddress.fromHex(c['module'] as String),
          moduleData: c['moduleData'] as String,
        ),
    'validatorRealHook': (c) => KernelV4Install.validator(
          module: EthereumAddress.fromHex(c['module'] as String),
          moduleData: c['moduleData'] as String,
          hook: hookModule,
          allowedSelectors: [executeSelector],
        ),
    'executor': (c) => KernelV4Install.executor(
          module: EthereumAddress.fromHex(c['module'] as String),
        ),
    'fallbackHandler': (c) => KernelV4Install.fallbackHandler(
          module: EthereumAddress.fromHex(c['module'] as String),
          selector: fallbackSelector,
          hook: KernelV4HookSentinels.installedNoHook,
        ),
  };

  group('KernelV4Install typed builders', () {
    for (final entry in typedInstalls.entries) {
      test('${entry.key} matches the oracle-accepted package', () {
        final c = installCase(entry.key);
        final package = entry.value(c);
        expect(package.moduleType, BigInt.from(c['moduleType'] as int));
        expect(
          package.module.hex.toLowerCase(),
          (c['module'] as String).toLowerCase(),
        );
        expect(package.moduleData, c['moduleData']);
        expect(package.internalData, c['internalData']);
      });
    }

    test('batch policy + signer match the oracle-accepted packages', () {
      final packages = (mm['batchInstall'] as Map<String, dynamic>)['packages']
          as List<dynamic>;
      final policyCase = packages[0] as Map<String, dynamic>;
      final signerCase = packages[1] as Map<String, dynamic>;

      final policy = KernelV4Install.policy(
        module: EthereumAddress.fromHex(policyCase['module'] as String),
        permissionId: permissionId,
      );
      expect(policy.moduleType, BigInt.from(5));
      expect(policy.moduleData, policyCase['moduleData']);
      expect(policy.internalData, policyCase['internalData']);

      final signer = KernelV4Install.signer(
        module: EthereumAddress.fromHex(signerCase['module'] as String),
        moduleData: signerCase['moduleData'] as String,
        permissionId: permissionId,
        hook: KernelV4HookSentinels.notInstalled,
        allowedSelectors: [executeSelector],
      );
      expect(signer.moduleType, BigInt.from(6));
      expect(signer.internalData, signerCase['internalData']);
    });

    test('fallbackHandler rejects unsupported call types', () {
      expect(
        () => KernelV4Install.fallbackHandler(
          module: sender,
          selector: fallbackSelector,
          callType: 0x01, // batch is not a fallback callType
        ),
        throwsArgumentError,
      );
    });

    test('selector and permissionId lengths are enforced', () {
      expect(
        () => KernelV4Install.fallbackHandler(module: sender, selector: '0x01'),
        throwsArgumentError,
      );
      expect(
        () => KernelV4Install.validator(
          module: sender,
          allowedSelectors: ['0x112233'],
        ),
        throwsArgumentError,
      );
      expect(
        () => KernelV4Install.policy(module: sender, permissionId: '0x0102'),
        throwsArgumentError,
      );
    });
  });

  group('encodeKernelV4InstallModuleCalldata', () {
    for (final entry in typedInstalls.entries) {
      test('${entry.key} matches the executed installModule calldata', () {
        final c = installCase(entry.key);
        expect(
          encodeKernelV4InstallModuleCalldata(entry.value(c)),
          c['callData'],
        );
      });
    }
  });

  group('encodeKernelV4UninstallModuleCalldata', () {
    for (final c in uninstalls) {
      test('${c['name']} matches the executed uninstallModule calldata', () {
        expect(
          encodeKernelV4UninstallModuleCalldata(
            moduleType: BigInt.from(c['moduleType'] as int),
            module: EthereumAddress.fromHex(c['module'] as String),
            moduleData: c['moduleData'] as String,
            internalData: c['internalData'] as String,
          ),
          c['callData'],
        );
      });
    }

    test('fallback, policy, and signer uninstalls require internalData', () {
      for (final moduleType in [3, 5, 6]) {
        expect(
          () => encodeKernelV4UninstallModuleCalldata(
            moduleType: BigInt.from(moduleType),
            module: sender,
          ),
          throwsArgumentError,
          reason: 'module type $moduleType reads internalData[0:4] on-chain',
        );
      }
    });
  });

  group('encodeKernelV4BatchInstallCalldata', () {
    test('matches the executed installModule(Install[]) calldata', () {
      final batch = mm['batchInstall'] as Map<String, dynamic>;
      expect(
        encodeKernelV4BatchInstallCalldata(kernelV4PackagesFromCase(batch)),
        batch['callData'],
      );
    });

    test('rejects an empty batch', () {
      expect(() => encodeKernelV4BatchInstallCalldata([]), throwsArgumentError);
    });

    test('rejects a batch that leaves a permission unfinished', () {
      // The oracle proved the contract enforces this on-chain
      // (PermissionInstallNotFinished); the encoder enforces it offline.
      final policy = KernelV4Install.policy(
        module: sender,
        permissionId: permissionId,
      );
      expect(
        () => encodeKernelV4BatchInstallCalldata([policy]),
        throwsArgumentError,
      );
    });

    test('rejects interleaved permission ids inside one permission', () {
      final policy = KernelV4Install.policy(
        module: sender,
        permissionId: permissionId,
      );
      final otherSigner = KernelV4Install.signer(
        module: sender,
        permissionId: '0x00000001',
      );
      expect(
        () => encodeKernelV4BatchInstallCalldata([policy, otherSigner]),
        throwsArgumentError,
      );
    });

    test('accepts a signer-only permission', () {
      final signer = KernelV4Install.signer(
        module: sender,
        permissionId: permissionId,
      );
      expect(encodeKernelV4BatchInstallCalldata([signer]), startsWith('0x'));
    });
  });

  group('setRoot', () {
    test('rotation calldata matches the executed setRoot', () {
      final c = mm['setRootRotate'] as Map<String, dynamic>;
      expect(
        encodeKernelV4SetRootCalldata(
          packages: kernelV4PackagesFromCase(c),
          removeCurrent: c['removeCurrent'] as bool,
          uninstallData: c['uninstallData'] as String,
        ),
        c['callData'],
      );
    });

    test('permission-root cleanup calldata and uninstallData match', () {
      final c = mm['setRootPermissionCleanup'] as Map<String, dynamic>;
      final perModule =
          (c['perModuleUninstallData'] as List<dynamic>).cast<String>();
      final uninstallData = encodeKernelV4PermissionUninstallData(perModule);
      expect(uninstallData, c['uninstallData']);
      expect(
        encodeKernelV4SetRootCalldata(
          packages: kernelV4PackagesFromCase(c),
          removeCurrent: c['removeCurrent'] as bool,
          uninstallData: uninstallData,
        ),
        c['callData'],
      );
    });

    test('setRoot(vId) calldata matches for a validator validation', () {
      final c = mm['setRootVId'] as Map<String, dynamic>;
      final vId = c['vId'] as String; // bytes21: 0x01 ‖ validator address
      final validator =
          EthereumAddress.fromHex('0x${Hex.strip0x(vId).substring(2)}');
      expect(
        encodeKernelV4SetRootValidationCalldata(
          KernelV4Validation.validator(validator),
        ),
        c['callData'],
      );
    });

    test('setRoot(vId) rejects the root validation', () {
      expect(
        () => encodeKernelV4SetRootValidationCalldata(
          const KernelV4Validation.root(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty package list', () {
      expect(
        () => encodeKernelV4SetRootCalldata(packages: []),
        throwsArgumentError,
      );
    });

    test('rejects a first package that cannot be a root', () {
      // Only validators (1), policies (5), and signers (6) can root.
      expect(
        () => encodeKernelV4SetRootCalldata(
          packages: [KernelV4Install.executor(module: sender)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('encodeKernelV4GrantAccessCalldata', () {
    test('matches the executed grantAccess calldata', () {
      final c = mm['grantAccess'] as Map<String, dynamic>;
      final vId = c['vId'] as String;
      final validator =
          EthereumAddress.fromHex('0x${Hex.strip0x(vId).substring(2)}');
      expect(
        encodeKernelV4GrantAccessCalldata(
          validation: KernelV4Validation.validator(validator),
          selectors: [executeSelector],
        ),
        c['callData'],
      );
    });

    test('rejects the root validation and empty selectors', () {
      expect(
        () => encodeKernelV4GrantAccessCalldata(
          validation: const KernelV4Validation.root(),
          selectors: [executeSelector],
        ),
        throwsArgumentError,
      );
      expect(
        () => encodeKernelV4GrantAccessCalldata(
          validation: KernelV4Validation.validator(sender),
          selectors: [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('encodeKernelV4SignedInstallCalldata', () {
    test('digest and calldata match the executed root-signed install', () {
      final c = mm['signedInstall'] as Map<String, dynamic>;
      final packages = kernelV4PackagesFromCase(c);
      expect(
        getKernelV4InstallPackagesDigest(
          accountAddress: EthereumAddress.fromHex(c['sender'] as String),
          installNonce: BigInt.parse(c['installNonce'] as String),
          packages: packages,
          chainId: chainId,
        ),
        c['installDigest'],
      );
      expect(
        encodeKernelV4SignedInstallCalldata(
          replayable: c['replayable'] as bool,
          installNonce: BigInt.parse(c['installNonce'] as String),
          packages: packages,
          signature: c['signature'] as String,
        ),
        c['callData'],
      );
    });
  });

  group('Erc7579ModuleType', () {
    test('carries the Kernel v4 policy and signer ids', () {
      expect(Erc7579ModuleType.policy.id, 5);
      expect(Erc7579ModuleType.signer.id, 6);
    });
  });

  group('uninstall ordering helper', () {
    test('orders permission uninstalls policies-LIFO then signer', () {
      // Fixture order proves the contract requirement: the signer uninstall
      // reverts while policies remain, and policies pop LIFO.
      final policyA =
          EthereumAddress.fromHex(uninstallCase('policy')['module'] as String);
      final signerModule =
          EthereumAddress.fromHex(uninstallCase('signer')['module'] as String);
      final calls = kernelV4PermissionUninstallCalldatas(
        permissionId: permissionId,
        policies: [policyA],
        signer: signerModule,
      );
      expect(calls, [
        uninstallCase('policy')['callData'],
        uninstallCase('signer')['callData'],
      ]);
    });

    test('reverses multi-policy uninstalls (LIFO)', () {
      final p1 =
          EthereumAddress.fromHex('0x1111111111111111111111111111111111111111');
      final p2 =
          EthereumAddress.fromHex('0x2222222222222222222222222222222222222222');
      final s =
          EthereumAddress.fromHex('0x3333333333333333333333333333333333333333');
      final calls = kernelV4PermissionUninstallCalldatas(
        permissionId: permissionId,
        policies: [p1, p2], // install order
        signer: s,
      );
      expect(calls, hasLength(3));
      // p2 (last installed) must be uninstalled first.
      expect(calls[0], contains(Hex.strip0x(p2.hex).toLowerCase()));
      expect(calls[1], contains(Hex.strip0x(p1.hex).toLowerCase()));
      expect(calls[2], contains(Hex.strip0x(s.hex).toLowerCase()));
    });
  });
}
