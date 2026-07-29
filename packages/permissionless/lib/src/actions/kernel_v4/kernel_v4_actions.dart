import '../../clients/smart_account/smart_account_client.dart';
import '../../types/address.dart';
import '../../types/user_operation.dart';
import '../../utils/kernel_v4/kernel_v4_install.dart';
import '../../utils/kernel_v4/kernel_v4_modules.dart';
import '../../utils/kernel_v4/kernel_v4_validation.dart';

/// Kernel v4 module-management actions on [SmartAccountClient].
///
/// Each action encodes the Kernel-specific calldata (see
/// `utils/kernel_v4/kernel_v4_modules.dart`) and sends it as a **self-call
/// UserOperation** — a call from the account to itself, which satisfies the
/// Kernel's EntryPoint-or-self guard — through the ordinary
/// `sendUserOperation` path, so gas estimation and paymaster sponsorship
/// work like any other operation.
///
/// The generic [Erc7579Actions] `installModule` / `uninstallModule` helpers
/// do **not** work against Kernel v4: the Kernel decodes the ERC-7579
/// `initData` as `abi.encode(installData, internalData)` rather than
/// forwarding it raw. Use these Kernel-typed actions instead.
///
/// Example:
/// ```dart
/// // Install a validator module with an allow-listed execute selector.
/// final hash = await client.installKernelV4Module(
///   KernelV4Install.validator(
///     module: validatorAddress,
///     moduleData: ownerAddress.hex,
///     allowedSelectors: [Erc7579Selectors.execute],
///   ),
/// );
/// await client.waitForReceipt(hash);
/// ```
extension KernelV4ModuleActions on SmartAccountClient {
  /// Installs a single module described by the typed [package].
  ///
  /// Policies and signers should go through [installKernelV4Modules]
  /// instead — a permission only becomes usable once its signer lands, and
  /// only the batch entrypoint verifies that atomically.
  ///
  /// Returns the UserOperation hash.
  Future<String> installKernelV4Module(
    KernelV4Install package, {
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) =>
      _selfCall(
        encodeKernelV4InstallModuleCalldata(package),
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        nonce: nonce,
      );

  /// Installs [packages] atomically via the Kernel's batch
  /// `installModule(Install[])` — the required path for permission
  /// (policy + signer) installs.
  ///
  /// Returns the UserOperation hash.
  Future<String> installKernelV4Modules(
    List<KernelV4Install> packages, {
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) =>
      _selfCall(
        encodeKernelV4BatchInstallCalldata(packages),
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        nonce: nonce,
      );

  /// Uninstalls a module. [moduleData] goes to the module's `onUninstall`;
  /// [internalData] is required for fallback selectors (the 4-byte selector)
  /// and policies/signers (the 4-byte PermissionId).
  ///
  /// To remove a whole permission, use [uninstallKernelV4Permission] — it
  /// orders the uninstalls the way the contracts require.
  ///
  /// Returns the UserOperation hash.
  Future<String> uninstallKernelV4Module({
    required BigInt moduleType,
    required EthereumAddress module,
    String moduleData = '0x',
    String internalData = '0x',
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) =>
      _selfCall(
        encodeKernelV4UninstallModuleCalldata(
          moduleType: moduleType,
          module: module,
          moduleData: moduleData,
          internalData: internalData,
        ),
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        nonce: nonce,
      );

  /// Removes a whole permission in one UserOperation, in the order the
  /// contracts require: [policies] (given in **install order**) are
  /// uninstalled in reverse (LIFO), then [signer] once no policies remain.
  ///
  /// Sends one batched UserOperation of self-calls, so the removal is
  /// atomic. See `kernelV4PermissionUninstallCalldatas` for the per-module
  /// `onUninstall` payload parameters.
  ///
  /// Returns the UserOperation hash.
  Future<String> uninstallKernelV4Permission({
    required String permissionId,
    required List<EthereumAddress> policies,
    required EthereumAddress signer,
    List<String>? policyUninstallData,
    String signerUninstallData = '0x',
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) async {
    final accountAddress = await getAddress();
    final calls = kernelV4PermissionUninstallCalldatas(
      permissionId: permissionId,
      policies: policies,
      signer: signer,
      policyUninstallData: policyUninstallData,
      signerUninstallData: signerUninstallData,
    ).map((callData) => Call(to: accountAddress, data: callData)).toList();
    return sendUserOperation(
      calls: calls,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );
  }

  /// Installs [packages] and promotes `packages[0]` to the account's new
  /// root validation (`setRoot`), optionally removing the current root.
  ///
  /// See `encodeKernelV4SetRootCalldata` for the [uninstallData] rules —
  /// notably the `PermissionUninstallData` shape a permission root needs.
  ///
  /// Returns the UserOperation hash.
  Future<String> setKernelV4Root({
    required List<KernelV4Install> packages,
    bool removeCurrent = false,
    String uninstallData = '0x',
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) =>
      _selfCall(
        encodeKernelV4SetRootCalldata(
          packages: packages,
          removeCurrent: removeCurrent,
          uninstallData: uninstallData,
        ),
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        nonce: nonce,
      );

  /// Repoints the root to an already-installed [validation]
  /// (`setRoot(ValidationId)`), with no install or cleanup.
  ///
  /// Returns the UserOperation hash.
  Future<String> setKernelV4RootValidation(
    KernelV4Validation validation, {
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) =>
      _selfCall(
        encodeKernelV4SetRootValidationCalldata(validation),
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        nonce: nonce,
      );

  /// Grants [validation] the right to lead UserOperations with the given
  /// account [selectors] (`grantAccess`) — e.g. to re-enable a validation
  /// whose grants a root rotation invalidated.
  ///
  /// Returns the UserOperation hash.
  Future<String> grantKernelV4Access({
    required KernelV4Validation validation,
    required List<String> selectors,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) =>
      _selfCall(
        encodeKernelV4GrantAccessCalldata(
          validation: validation,
          selectors: selectors,
        ),
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        nonce: nonce,
      );

  /// Sends [callData] as a call from the account to itself.
  Future<String> _selfCall(
    String callData, {
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
  }) async {
    final accountAddress = await getAddress();
    return sendUserOperation(
      calls: [Call(to: accountAddress, data: callData)],
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      nonce: nonce,
    );
  }
}
