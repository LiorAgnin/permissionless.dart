/// Parses a dynamic value (int, BigInt, hex string, or decimal string) to BigInt.
BigInt parseBigInt(dynamic value) {
  if (value is int) return BigInt.from(value);
  if (value is BigInt) return value;
  final str = value.toString();
  if (str.startsWith('0x')) {
    return BigInt.parse(str.substring(2), radix: 16);
  }
  return BigInt.parse(str);
}
