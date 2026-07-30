import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/erc7579.dart';
import '../../utils/kernel_v4/kernel_v4.dart';
import '../../utils/message_hash.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import 'constants.dart';

/// Shared behavior of the factory-deployed Kernel v4 accounts
/// (`KernelUUPS` and `KernelImmutableECDSA`).
///
/// Both variants share the KernelFactory / CREATE2 deployment path, ERC-7579
/// execute encoding, and the root signing scheme (raw 65-byte `r‖s‖v` over
/// the EntryPoint v0.9 userOpHash — routing lives in the nonce, not the
/// signature). They differ only in where the account's identity lives:
/// packages[0] root install (UUPS) vs proxy immutable args (ImmutableECDSA)
/// — which is exactly the [getAddress] / [getFactoryData] surface subclasses
/// implement.
///
/// Not exported: this is an implementation detail of the two public account
/// types, per the ticket 07 code-shape decision.
abstract class KernelV4AccountBase implements SmartAccount {
  /// The account owner used for root signing.
  AccountOwner get owner;

  /// The Kernel version (always a v4 version; enforced by the configs).
  KernelVersion get version;

  /// Optional EntryPoint address override for forked or pre-release
  /// EntryPoint v0.9 deployments.
  EthereumAddress? get entryPointOverride;

  /// Optional custom 2-byte parallel nonce key.
  BigInt? get customNonceKey;

  /// The validation path this account's UserOperations run under
  /// (root by default; a validator module or permission otherwise).
  KernelV4Validation get validation;

  /// Whether UserOperations carry the replayable mode bit (`0x40`) and sign
  /// the chain-agnostic digest instead of the chain-bound userOpHash.
  bool get replayableUserOps;

  /// Enable-mode configuration: install modules atomically with the next
  /// UserOperation (nonce mode bit `0x08`), or `null` for plain operations.
  KernelV4EnableMode? get enableMode;

  /// The EntryPoint version this account targets — always v0.9 for Kernel v4.
  EntryPointVersion get entryPointVersion => version.entryPointVersion;

  @override
  EthereumAddress get entryPoint =>
      entryPointOverride ?? EntryPointAddresses.v09;

  @override
  bool get isWebAuthn => false;

  /// The composed nonce mode bitfield: `0x40` for replayable userOp hashes,
  /// `0x08` (+ `0x04` for a replayable enable signature) in enable mode.
  int get _vMode {
    var vMode = replayableUserOps
        ? KernelV4ValidationMode.replayableUserOpHash
        : KernelV4ValidationMode.standard;
    final enable = enableMode;
    if (enable != null) {
      vMode |= KernelV4ValidationMode.enable;
      if (enable.replayableEnableSignature) {
        vMode |= KernelV4ValidationMode.replayableEnable;
      }
    }
    return vMode;
  }

  @override
  BigInt get nonceKey => encodeKernelV4NonceKey(
        vMode: _vMode,
        vType: validation.vType,
        vId: validation.vId,
        nonceKey: customNonceKey,
      );

  @override
  Future<String> getInitCode() async {
    final factoryData = await getFactoryData();
    if (factoryData == null) return '0x';
    return Hex.concat([
      factoryData.factory.hex,
      Hex.strip0x(factoryData.factoryData),
    ]);
  }

  @override
  String encodeCall(Call call) => encode7579Execute(call);

  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }
    if (calls.length == 1) {
      return encodeCall(calls.first);
    }
    return encode7579ExecuteBatch(calls);
  }

  @override
  List<Call> decodeCalls(String callData) => decode7579Calls(callData).calls;

  @override
  String getStubSignature() {
    final enable = enableMode;
    if (enable == null) return validation.stubSignature;
    // Estimation must exercise the full enable path shape: the Kernel
    // decodes the blob, verifies (and fails cleanly on) the stub enable
    // signature, installs the packages, and runs the inner validation on
    // its stub — so both slots carry validation-shaped stubs.
    return encodeKernelV4EnableModeSignature(
      installNonce: enable.installNonce,
      packages: enable.packages,
      enableSignature: kernelDummyEcdsaSignature,
      userOpSignature: validation.stubSignature,
    );
  }

  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    // With the replayable mode bit set, Kernel validates the chain-agnostic
    // digest instead of the EntryPoint-supplied hash.
    final userOpHash = replayableUserOps
        ? getKernelV4ChainAgnosticUserOpHash(
            userOperation: userOp,
            entryPointAddress: entryPoint,
          )
        : getUserOperationHash(
            userOperation: userOp,
            entryPointAddress: entryPoint,
            entryPointVersion: entryPointVersion,
            chainId: chainId,
          );
    // Validation paths recover the signer over the raw digest (no EIP-191
    // personal-message prefix). Routing lives in the nonce, so the raw
    // signature needs no prefix — a permission validation wraps it as the
    // signer's chunk of the signature list.
    final innerSignature =
        validation.wrapSignature(await owner.signRawHash(userOpHash));

    final enable = enableMode;
    if (enable == null) return innerSignature;
    return _encodeEnableModeBlob(
      enable: enable,
      accountAddress: userOp.sender,
      innerSignature: innerSignature,
    );
  }

  /// Builds the `EnableModeSignature` blob shared by enable-mode
  /// UserOperations and enable-mode ERC-1271: the root authorizes the
  /// install by signing the InstallPackages digest over the account's own
  /// EIP-712 domain (verifyingContract = the account), and [innerSignature]
  /// is validated by the path the nonce (or 1271 prefix) routes to —
  /// typically the module being installed.
  Future<String> _encodeEnableModeBlob({
    required KernelV4EnableMode enable,
    required EthereumAddress accountAddress,
    required String innerSignature,
  }) async {
    final rootSigner = enable.rootOwner ?? owner;
    final enableSignature = await rootSigner.signRawHash(
      getKernelV4InstallPackagesDigest(
        accountAddress: accountAddress,
        installNonce: enable.installNonce,
        packages: enable.packages,
        chainId: chainId,
        replayable: enable.replayableEnableSignature,
      ),
    );
    return encodeKernelV4EnableModeSignature(
      installNonce: enable.installNonce,
      packages: enable.packages,
      enableSignature: enableSignature,
      userOpSignature: innerSignature,
    );
  }

  /// Signs [hash] for ERC-1271 verification, wrapped as an ERC-7739
  /// `PersonalSign` under the account's own domain.
  ///
  /// `isValidSignature(hash, …)` embeds its input hash as-is in the
  /// `PersonalSign` struct, so [hash] must be exactly what the verifying app
  /// will pass — for a personal message that is `hashMessage(message)`, which
  /// [signMessage] applies; no further prefixing happens here.
  @override
  Future<String> sign(String hash) async => _signErc1271(
        digest: getKernelV4PersonalSignDigest(
          accountAddress: await getAddress(),
          chainId: chainId,
          hash: hash,
        ),
      );

  @override
  Future<String> signMessage(String message) => sign(hashMessage(message));

  /// Signs app-side EIP-712 [typedData] via the ERC-7739 `TypedDataSign`
  /// wrap — chain-bound: the signed struct carries this chain's id.
  @override
  Future<String> signTypedData(TypedData typedData) =>
      _signTypedData(typedData, replayable: false);

  /// Like [signTypedData], but the `TypedDataSign` struct drops its chainId
  /// field (Kernel's replayable ERC-7739 branch), so the same signature
  /// verifies on every chain the account exists on — provided the app's own
  /// domain is not chain-bound either.
  Future<String> signTypedDataReplayable(TypedData typedData) =>
      _signTypedData(typedData, replayable: true);

  Future<String> _signTypedData(
    TypedData typedData, {
    required bool replayable,
  }) async {
    final wrap = getKernelV4TypedDataSignWrap(
      accountAddress: await getAddress(),
      chainId: chainId,
      typedData: typedData,
      replayable: replayable,
    );
    return _signErc1271(digest: wrap.digest, extension: wrap.extension);
  }

  /// Signs the wrapped [digest] and frames it for `isValidSignature`:
  /// `[vMode | vType | vId]` prefix, the validation-shaped inner signature
  /// (an `EnableModeSignature` blob when enable mode is configured — the
  /// stateless view path, nothing gets installed), then the TypedDataSign
  /// [extension] when present.
  Future<String> _signErc1271({
    required String digest,
    String extension = '',
  }) async {
    final inner = validation.wrapSignature(await owner.signRawHash(digest));
    final enable = enableMode;
    if (enable == null) {
      return encodeKernelV4Erc1271Signature(
        validation: validation,
        signature: inner,
        extension: extension,
      );
    }
    var vMode = KernelV4ValidationMode.enable;
    if (enable.replayableEnableSignature) {
      vMode |= KernelV4ValidationMode.replayableEnable;
    }
    return encodeKernelV4Erc1271Signature(
      validation: validation,
      signature: await _encodeEnableModeBlob(
        enable: enable,
        accountAddress: await getAddress(),
        innerSignature: inner,
      ),
      vMode: vMode,
      extension: extension,
    );
  }
}
