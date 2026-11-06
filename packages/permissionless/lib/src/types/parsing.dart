/// Parses a JSON-RPC number (int, BigInt, `0x` hex string, or decimal
/// string) to a BigInt.
BigInt parseBigInt(dynamic value) => switch (value) {
      final int v => BigInt.from(v),
      final BigInt v => v,
      _ => BigInt.parse(value.toString()),
    };

/// [parseBigInt], or null when [value] is null.
BigInt? parseBigIntOrNull(dynamic value) =>
    value == null ? null : parseBigInt(value);

/// [parseBigInt] for values that fit in an int (status codes, log indexes).
int parseInt(dynamic value) =>
    value is int ? value : parseBigInt(value).toInt();
