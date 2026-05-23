import '../types/hex.dart';

/// ERC-4337 v0.9 paymaster signature magic suffix.
const String paymasterSignatureMagic = '0x22e325a297439656';

/// Appends an ERC-4337 v0.9 paymaster signature suffix to paymaster data.
///
/// The returned value is encoded as:
///
/// `paymasterData || paymasterSignature || uint16(signatureSize) || magic`
String appendPaymasterSignature({
  required String paymasterData,
  required String paymasterSignature,
}) {
  _validateHexData(paymasterData, name: 'paymasterData');
  _validateHexData(paymasterSignature, name: 'paymasterSignature');

  final signatureSize = Hex.byteLength(paymasterSignature);
  if (signatureSize == 0) {
    throw ArgumentError.value(
      paymasterSignature,
      'paymasterSignature',
      'must not be empty',
    );
  }
  if (signatureSize > 0xffff) {
    throw ArgumentError.value(
      paymasterSignature,
      'paymasterSignature',
      'must fit in uint16 length encoding',
    );
  }

  return Hex.concat([
    paymasterData,
    paymasterSignature,
    Hex.fromBigInt(BigInt.from(signatureSize), byteLength: 2),
    paymasterSignatureMagic,
  ]);
}

void _validateHexData(String value, {required String name}) {
  final clean = Hex.strip0x(value);
  if (!Hex.isValid(value)) {
    throw ArgumentError.value(value, name, 'must be valid hex data');
  }
  if (clean.length.isOdd) {
    throw ArgumentError.value(value, name, 'must contain whole bytes');
  }
}
