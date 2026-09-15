import '../../types/address.dart';

/// Contract addresses for a Kernel v4 deployment.
///
/// Distinct from the v2/v3 `KernelAddresses` shape: v4 has a Staker (the
/// staked deployment wrapper replacing the v3 meta factory), one factory, and
/// three implementation contracts.
///
/// No root-validator module address is tabled: Kernel v4 ships no production
/// validator deployments yet, and `KernelImmutableECDSA` needs none (the
/// signer is immutable in the proxy). Callers configuring an external
/// validator supply [ecdsaValidator] / [webAuthnValidator] explicitly.
class KernelV4Addresses {
  /// Creates a set of Kernel v4 contract addresses.
  const KernelV4Addresses({
    required this.kernelUUPS,
    required this.kernelImmutableECDSA,
    required this.factory,
    required this.staker,
    this.kernel7702,
    this.ecdsaValidator,
    this.webAuthnValidator,
  });

  /// `KernelUUPS` implementation address.
  final EthereumAddress kernelUUPS;

  /// `KernelImmutableECDSA` implementation address.
  final EthereumAddress kernelImmutableECDSA;

  /// `KernelFactory` address — the CREATE2 deployer for both proxy variants.
  final EthereumAddress factory;

  /// `Staker` address — the staked wrapper that forwards deployments to
  /// approved factories. Routing through it does not change account
  /// addresses.
  final EthereumAddress staker;

  /// `Kernel7702` implementation address (EIP-7702 delegation target).
  final EthereumAddress? kernel7702;

  /// Optional external ECDSA validator module. No library default exists —
  /// Kernel v4 has no published validator deployments.
  final EthereumAddress? ecdsaValidator;

  /// Optional WebAuthn validator module. Same no-default story.
  final EthereumAddress? webAuthnValidator;

  /// The Kernel release v0.4.0 addresses.
  ///
  /// These are the CREATE2 predictions recorded in the release metadata
  /// (`releases/v0.4.0.json`, deterministic deployer
  /// `0x4e59b44847b379578588920cA78FbF26c0B4956C`, salt 0). The release repo
  /// records no confirmed on-chain deployments; deployment is permissionless
  /// and address-stable, so these hold on any chain where the recipe has been
  /// (or will be) run. Override per-account for private or forked
  /// deployments.
  static final KernelV4Addresses predicted = KernelV4Addresses(
    kernelUUPS: EthereumAddress.fromHex(
      '0xC842fE2aC44046AE3cEf033A16c67a9BC287cbD2',
    ),
    kernelImmutableECDSA: EthereumAddress.fromHex(
      '0x6F0999265B6E1dFbe875F104548b875a99A65d37',
    ),
    factory: EthereumAddress.fromHex(
      '0xA299A4eFee7BBFb2Ea5668b30218C45fff78356c',
    ),
    staker: EthereumAddress.fromHex(
      '0x58E2fD56990250b0eE784d15905C9856209226aE',
    ),
    kernel7702: EthereumAddress.fromHex(
      '0x36312BA78010247390C6677a59807Fe7878e9B59',
    ),
  );
}
