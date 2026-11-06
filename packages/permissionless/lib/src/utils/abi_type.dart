/// The atomic Solidity ABI types viem accepts (its `bytesRegex` /
/// `integerRegex`); group 2 is the size of a `bytesN`.
///
/// web3dart only `assert`s type widths, so without this check a release build
/// encodes `uint7` or `bytes33` as given, and every build accepts `bytes0`.
final RegExp atomicAbiType = RegExp(
  '^(address|bool|string|bytes([1-9]|[12][0-9]|3[0-2])?|u?int(8|16|24|32|40'
  '|48|56|64|72|80|88|96|104|112|120|128|136|144|152|160|168|176|184|192|200'
  r'|208|216|224|232|240|248|256)?)$',
);
