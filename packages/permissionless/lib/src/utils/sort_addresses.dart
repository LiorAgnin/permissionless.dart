import '../types/address.dart';

/// Sorts addresses in ascending UTF-16 code-unit order of lowercased `0x` hex.
///
/// Independent of the host locale. A locale collator (for example a Danish
/// ICU collation where the "aa" digraph sorts after "z") would make CREATE2
/// counterfactual address derivation non-deterministic across hosts.
///
/// Copies the input; does not mutate it. Checksum casing is ignored.
List<EthereumAddress> sortAddresses(List<EthereumAddress> addresses) =>
    List<EthereumAddress>.from(addresses)
      ..sort((a, b) => a.hex.toLowerCase().compareTo(b.hex.toLowerCase()));
