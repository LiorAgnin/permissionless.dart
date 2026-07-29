import 'package:web3dart/web3dart.dart';

import '../../types/address.dart';
import '../../types/hex.dart';
import 'kernel_v4_install.dart';

/// The 61-byte runtime of Solady's minimal ERC-1967 proxy (LibClone).
const String _erc1967ProxyRuntime =
    '363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076'
    'cc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3';

/// The initialization code of Solady's minimal ERC-1967 proxy for
/// [implementation], optionally carrying [immutableArgs].
///
/// Matches `LibClone.initCodeERC1967` byte-for-byte:
///
/// - without args (Kernel v4 UUPS deployments), 95 bytes:
///   `603d3d8160223d3973 ‖ impl ‖ 60095155f3 ‖ runtime`
/// - with n bytes of args (KernelImmutableECDSA embeds the 20-byte signer),
///   n + 96 bytes:
///   `61 ‖ uint16(0x3d + n) ‖ 3d8160233d3973 ‖ impl ‖ 60095155f3 ‖ runtime ‖ args`
///
/// The two shapes are distinct — Solady's no-args overload is not the args
/// overload with `n = 0` — mirroring the two `KernelFactory` deploy paths.
String kernelV4CloneInitCode({
  required EthereumAddress implementation,
  String immutableArgs = '0x',
}) {
  final args = Hex.strip0x(immutableArgs);
  final argsLength = args.length ~/ 2;

  if (argsLength == 0) {
    return Hex.concat([
      '0x603d3d8160223d3973',
      implementation.hex,
      '0x60095155f3',
      _erc1967ProxyRuntime,
    ]);
  }

  return Hex.concat([
    '0x61',
    Hex.fromBigInt(BigInt.from(0x3d + argsLength), byteLength: 2),
    '0x3d8160233d3973',
    implementation.hex,
    '0x60095155f3',
    _erc1967ProxyRuntime,
    args,
  ]);
}

/// keccak256 of [kernelV4CloneInitCode] — the CREATE2 initcode hash.
String kernelV4CloneInitCodeHash({
  required EthereumAddress implementation,
  String immutableArgs = '0x',
}) =>
    Hex.fromBytes(
      keccak256(
        Hex.decode(
          kernelV4CloneInitCode(
            implementation: implementation,
            immutableArgs: immutableArgs,
          ),
        ),
      ),
    );

/// Standard CREATE2 address:
/// `keccak256(0xff ‖ deployer ‖ salt ‖ initCodeHash)[12:]`.
EthereumAddress _create2Address({
  required EthereumAddress deployer,
  required String salt,
  required String initCodeHash,
}) {
  final digest = keccak256(
    Hex.decode(
      Hex.concat([
        '0xff',
        deployer.hex,
        salt,
        initCodeHash,
      ]),
    ),
  );
  return EthereumAddress.fromHex(Hex.slice(Hex.fromBytes(digest), 12));
}

/// The counterfactual address of a `KernelImmutableECDSA` account, computed
/// offline (no RPC).
///
/// Reproduces `KernelFactory.getECDSAAddress(signer, packages, nonce)`: the
/// salt commits to [packages] and [nonce] ([computeKernelV4Salt]); the
/// [signer] is embedded in the proxy initcode as immutable args. The CREATE2
/// deployer is always the [factory] — deployments routed through the Staker
/// resolve to the same address, because the Staker merely forwards the call.
EthereumAddress computeKernelV4EcdsaAddress({
  required EthereumAddress signer,
  required List<KernelV4Install> packages,
  required BigInt nonce,
  required EthereumAddress factory,
  required EthereumAddress implementation,
}) =>
    _create2Address(
      deployer: factory,
      salt: computeKernelV4Salt(packages: packages, nonce: nonce),
      initCodeHash: kernelV4CloneInitCodeHash(
        implementation: implementation,
        immutableArgs: signer.hex,
      ),
    );
