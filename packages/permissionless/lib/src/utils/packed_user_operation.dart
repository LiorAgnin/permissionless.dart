import '../types/address.dart';
import '../types/eip7702.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';

/// Packed UserOperation format for EntryPoint v0.7.
///
/// This is the on-chain representation of a v0.7 UserOperation where certain
/// fields are packed together for efficiency:
/// - [initCode] = factory address (20 bytes) + factoryData
/// - [accountGasLimits] = verificationGasLimit (16 bytes) + callGasLimit (16 bytes)
/// - [gasFees] = maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes)
/// - [paymasterAndData] = paymaster (20 bytes) + paymasterVerificationGasLimit (16 bytes)
///   + paymasterPostOpGasLimit (16 bytes) + paymasterData
///
/// This format is used when computing the UserOperation hash and for
/// on-chain validation.
///
/// Example:
/// ```dart
/// final packed = getPackedUserOperation(userOperation);
/// print('initCode: ${packed.initCode}');
/// print('accountGasLimits: ${packed.accountGasLimits}');
/// ```
class PackedUserOperation {
  /// Creates a packed UserOperation for on-chain use.
  ///
  /// Prefer using [getPackedUserOperation] to pack a [UserOperationV07]
  /// rather than constructing this directly.
  const PackedUserOperation({
    required this.sender,
    required this.nonce,
    required this.initCode,
    required this.callData,
    required this.accountGasLimits,
    required this.preVerificationGas,
    required this.gasFees,
    required this.paymasterAndData,
    required this.signature,
  });

  /// The smart account address.
  final EthereumAddress sender;

  /// The account's nonce.
  final BigInt nonce;

  /// Packed initCode: factory address (20 bytes) + factoryData.
  /// '0x' if no factory (account already deployed).
  final String initCode;

  /// The encoded callData for execution.
  final String callData;

  /// Packed gas limits: verificationGasLimit (16 bytes) + callGasLimit (16 bytes).
  final String accountGasLimits;

  /// Pre-verification gas.
  final BigInt preVerificationGas;

  /// Packed gas fees: maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes).
  final String gasFees;

  /// Packed paymaster data: paymaster (20 bytes) + paymasterVerificationGasLimit (16 bytes)
  /// + paymasterPostOpGasLimit (16 bytes) + paymasterData.
  /// '0x' if no paymaster.
  final String paymasterAndData;

  /// The signature.
  final String signature;

  /// Converts to JSON-RPC compatible map.
  Map<String, dynamic> toJson() => {
        'sender': sender.hex,
        'nonce': Hex.fromBigInt(nonce),
        'initCode': initCode,
        'callData': callData,
        'accountGasLimits': accountGasLimits,
        'preVerificationGas': Hex.fromBigInt(preVerificationGas),
        'gasFees': gasFees,
        'paymasterAndData': paymasterAndData,
        'signature': signature,
      };
}

// ============================================================================
// Packing Functions
// ============================================================================

/// Packs a v0.7 UserOperation into the packed format.
///
/// This converts the unpacked [UserOperationV07] into [PackedUserOperation]
/// which is the format used for on-chain validation and hash computation.
///
/// Example:
/// ```dart
/// final userOp = UserOperationV07(...);
/// final packed = getPackedUserOperation(userOp);
/// ```
PackedUserOperation getPackedUserOperation(
  UserOperationV07 userOperation, {
  EthereumAddress? delegationAddress,
}) =>
    PackedUserOperation(
      sender: userOperation.sender,
      nonce: userOperation.nonce,
      initCode:
          getInitCode(userOperation, delegationAddress: delegationAddress),
      callData: userOperation.callData,
      accountGasLimits: getAccountGasLimits(userOperation),
      preVerificationGas: userOperation.preVerificationGas,
      gasFees: getGasFees(userOperation),
      paymasterAndData: getPaymasterAndData(userOperation),
      signature: userOperation.signature,
    );

/// Creates the packed initCode from factory + factoryData.
///
/// Returns '0x' if no factory is set (account already deployed).
///
/// Format: factory address (20 bytes) + factoryData
///
/// For EIP-7702, pass [delegationAddress] (authorization contract) so the
/// initCode matches EntryPoint hashing (viem `getInitCode` parity).
///
/// Example:
/// ```dart
/// final initCode = getInitCode(userOp);
/// // Returns '0x5fbdb2315678afecb367f032d93f642f64180aa3abcdef...'
/// ```
String getInitCode(
  UserOperationV07 userOperation, {
  EthereumAddress? delegationAddress,
}) =>
    packUserOperationInitCode(
      factory: userOperation.factory,
      factoryData: userOperation.factoryData,
      delegationAddress: delegationAddress,
    );

/// Creates the packed accountGasLimits from gas limits.
///
/// Format: verificationGasLimit (16 bytes) + callGasLimit (16 bytes)
///
/// Example:
/// ```dart
/// final gasLimits = getAccountGasLimits(userOp);
/// // Returns '0x0000000000000000000000000000c350000000000000000000000000000186a0'
/// ```
String getAccountGasLimits(UserOperationV07 userOperation) => Hex.concat([
      Hex.padLeft(Hex.fromBigInt(userOperation.verificationGasLimit), 16),
      Hex.padLeft(Hex.fromBigInt(userOperation.callGasLimit), 16),
    ]);

/// Creates the packed gasFees from fee parameters.
///
/// Format: maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes)
///
/// Example:
/// ```dart
/// final fees = getGasFees(userOp);
/// ```
String getGasFees(UserOperationV07 userOperation) => Hex.concat([
      Hex.padLeft(Hex.fromBigInt(userOperation.maxPriorityFeePerGas), 16),
      Hex.padLeft(Hex.fromBigInt(userOperation.maxFeePerGas), 16),
    ]);

/// Creates the packed paymasterAndData from paymaster fields.
///
/// Returns '0x' if no paymaster is set.
///
/// Format: paymaster (20 bytes) + paymasterVerificationGasLimit (16 bytes)
///         + paymasterPostOpGasLimit (16 bytes) + paymasterData
///
/// For EntryPoint v0.9, a non-null [UserOperationV07.paymasterSignature] is
/// appended as `signature ‖ uint16(length) ‖ [paymasterSignatureMagic]`.
///
/// Throws [ArgumentError] if `paymasterSignature` is set but empty — see
/// [encodePaymasterSignatureSuffix].
///
/// Example:
/// ```dart
/// final pmData = getPaymasterAndData(userOp);
/// ```
String getPaymasterAndData(UserOperationV07 userOperation) {
  if (userOperation.paymaster == null) {
    return '0x';
  }
  return Hex.concat([
    userOperation.paymaster!.hex,
    Hex.padLeft(
      Hex.fromBigInt(
        userOperation.paymasterVerificationGasLimit ?? BigInt.zero,
      ),
      16,
    ),
    Hex.padLeft(
      Hex.fromBigInt(userOperation.paymasterPostOpGasLimit ?? BigInt.zero),
      16,
    ),
    userOperation.paymasterData ?? '0x',
    if (userOperation.paymasterSignature != null)
      encodePaymasterSignatureSuffix(userOperation.paymasterSignature!),
  ]);
}

// ============================================================================
// Paymaster signature suffix (EntryPoint v0.9)
// ============================================================================

/// Magic bytes marking a paymaster signature suffix: `keccak("PaymasterSignature")[:8]`.
///
/// Mirrors `UserOperationLib.PAYMASTER_SIG_MAGIC`.
const String paymasterSignatureMagic = '0x22e325a297439656';

/// Byte length of [paymasterSignatureMagic].
const int paymasterSignatureMagicLength = 8;

/// Byte length of the trailing `uint16(length) ‖ magic` framing.
const int paymasterSignatureSuffixLength = paymasterSignatureMagicLength + 2;

/// Byte offset at which paymaster-specific data begins in `paymasterAndData`.
///
/// Mirrors `UserOperationLib.PAYMASTER_DATA_OFFSET`
/// (paymaster 20 + verificationGasLimit 16 + postOpGasLimit 16).
const int paymasterDataOffset = 52;

/// Shortest `paymasterAndData` that could contain a signature suffix.
const int minPaymasterAndDataWithSuffixLength =
    paymasterDataOffset + paymasterSignatureSuffixLength;

/// A correctly shaped placeholder paymaster signature (65 bytes, ECDSA-like).
///
/// Use this when signing a v0.9 operation before the paymaster has responded.
/// The userOpHash depends on *whether* a paymaster signature is present but not
/// on its contents or length, so replacing this with the real signature leaves
/// the hash — and therefore the user's signature — valid. Being the realistic
/// 65 bytes also keeps calldata-based gas estimation accurate.
const String paymasterSignatureStub =
    '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

/// Encodes a paymaster signature as the suffix appended to `paymasterAndData`.
///
/// Format: `signature ‖ uint16(byteLength) ‖ [paymasterSignatureMagic]`.
/// Mirrors `UserOperationLib.encodePaymasterSignature`.
///
/// Throws [ArgumentError] if [paymasterSignature] is empty. The contract
/// returns no suffix for a zero-length signature, so an empty value cannot
/// express "a suffix is present" — pass `null` for the no-signature case
/// instead of `'0x'`.
///
/// Throws [ArgumentError] if the signature exceeds 65535 bytes, which the
/// `uint16` length field cannot describe.
String encodePaymasterSignatureSuffix(String paymasterSignature) {
  final length = Hex.byteLength(paymasterSignature);
  if (length == 0) {
    throw ArgumentError.value(
      paymasterSignature,
      'paymasterSignature',
      'must not be empty: EntryPoint v0.9 treats a zero-length signature as '
          'no signature at all, which produces a different userOpHash. Pass '
          'null for "no paymaster signature", or paymasterSignatureStub when '
          'the real signature is not known yet',
    );
  }
  if (length > 0xffff) {
    throw ArgumentError.value(
      length,
      'paymasterSignature',
      'exceeds the uint16 length field (max 65535 bytes)',
    );
  }
  return Hex.concat([
    paymasterSignature,
    Hex.padLeft(Hex.fromBigInt(BigInt.from(length)), 2),
    paymasterSignatureMagic,
  ]);
}

/// Returns the byte length of the paymaster signature in [paymasterAndData],
/// or 0 if there is none.
///
/// Mirrors `UserOperationLib.getPaymasterSignatureLength`: a suffix is only
/// recognised when the blob is long enough, ends with
/// [paymasterSignatureMagic], and declares a non-zero length.
///
/// Throws [ArgumentError] when the declared length would extend back past the
/// start of the paymaster data — the contract reverts with
/// `InvalidPaymasterSignatureLength` here.
int getPaymasterSignatureLength(String paymasterAndData) {
  final byteLength = Hex.byteLength(paymasterAndData);
  if (byteLength < minPaymasterAndDataWithSuffixLength) {
    return 0;
  }

  final magic = Hex.slice(
    paymasterAndData,
    byteLength - paymasterSignatureMagicLength,
    byteLength,
  );
  if (magic.toLowerCase() != paymasterSignatureMagic) {
    return 0;
  }

  final declared = Hex.toBigInt(
    Hex.slice(
      paymasterAndData,
      byteLength - paymasterSignatureSuffixLength,
      byteLength - paymasterSignatureMagicLength,
    ),
  ).toInt();

  if (declared > byteLength - minPaymasterAndDataWithSuffixLength) {
    throw ArgumentError.value(
      declared,
      'paymasterAndData',
      'declared paymaster signature length extends before the paymaster data '
          '(blob is $byteLength bytes)',
    );
  }
  return declared;
}

/// Extracts the paymaster signature from [paymasterAndData].
///
/// Returns `'0x'` when no suffix is present.
String getPaymasterSignature(String paymasterAndData) {
  final length = getPaymasterSignatureLength(paymasterAndData);
  if (length == 0) {
    return '0x';
  }
  final end = Hex.byteLength(paymasterAndData) - paymasterSignatureSuffixLength;
  return Hex.slice(paymasterAndData, end - length, end);
}

/// Returns the paymaster-specific data covered by the user's signature.
///
/// This is [paymasterAndData] with the 52-byte static header and any signature
/// suffix removed. Mirrors `UserOperationLib.getSignedPaymasterData`.
String getSignedPaymasterData(String paymasterAndData) {
  final byteLength = Hex.byteLength(paymasterAndData);
  final signatureLength = getPaymasterSignatureLength(paymasterAndData);
  final end = signatureLength == 0
      ? byteLength
      : byteLength - (signatureLength + paymasterSignatureSuffixLength);
  return Hex.slice(paymasterAndData, paymasterDataOffset, end);
}

/// Returns the exact bytes the EntryPoint hashes in place of
/// [paymasterAndData].
///
/// When a signature suffix is present, the signature and its length are
/// dropped but the magic is retained: `prefix ‖ magic`. Otherwise the input is
/// returned unchanged. Mirrors `paymasterDataKeccak` in the EntryPoint's
/// `Helpers.sol`.
///
/// This is what makes the userOpHash independent of the paymaster's signature,
/// so the two signatures can be produced in parallel.
String getHashedPaymasterAndData(String paymasterAndData) {
  final signatureLength = getPaymasterSignatureLength(paymasterAndData);
  if (signatureLength == 0) {
    return paymasterAndData;
  }
  final prefixEnd = Hex.byteLength(paymasterAndData) -
      (signatureLength + paymasterSignatureSuffixLength);
  return Hex.concat([
    Hex.slice(paymasterAndData, 0, prefixEnd),
    paymasterSignatureMagic,
  ]);
}

/// Appends a paymaster signature to an already-packed [paymasterAndData].
///
/// This is the final step of the v0.9 sponsorship flow: build and sign the
/// operation with [paymasterSignatureStub] (or any placeholder), then splice in
/// the real signature once the paymaster returns it. The userOpHash is
/// unaffected, so the user's signature stays valid.
///
/// Throws [ArgumentError] if [paymasterAndData] already carries a suffix —
/// stacking a second one would make the first unrecoverable.
String splicePaymasterSignature(
  String paymasterAndData,
  String paymasterSignature,
) {
  if (getPaymasterSignatureLength(paymasterAndData) != 0) {
    throw ArgumentError.value(
      paymasterAndData,
      'paymasterAndData',
      'already carries a paymaster signature suffix',
    );
  }
  return Hex.concat([
    paymasterAndData,
    encodePaymasterSignatureSuffix(paymasterSignature),
  ]);
}

// ============================================================================
// Unpacking Functions
// ============================================================================

/// Result of unpacking initCode.
class UnpackedInitCode {
  /// Creates an unpacked initCode result.
  ///
  /// Both fields are null if the account is already deployed.
  const UnpackedInitCode({
    this.factory,
    this.factoryData,
  });

  /// The factory address, or null if no factory.
  final EthereumAddress? factory;

  /// The factory calldata, or null if no factory.
  final String? factoryData;
}

/// Unpacks initCode into factory + factoryData.
///
/// Example:
/// ```dart
/// final unpacked = unpackInitCode('0x5fbdb2315...abcdef');
/// print('Factory: ${unpacked.factory?.hex}');
/// print('Data: ${unpacked.factoryData}');
/// ```
UnpackedInitCode unpackInitCode(String initCode) {
  if (initCode == '0x' || initCode.isEmpty) {
    return const UnpackedInitCode();
  }

  final hex = Hex.strip0x(initCode);
  if (hex.length < 40) {
    return const UnpackedInitCode();
  }

  return UnpackedInitCode(
    factory: EthereumAddress.fromHex('0x${hex.substring(0, 40)}'),
    factoryData: hex.length > 40 ? '0x${hex.substring(40)}' : '0x',
  );
}

/// Result of unpacking accountGasLimits.
class UnpackedAccountGasLimits {
  /// Creates unpacked account gas limits.
  ///
  /// - [verificationGasLimit]: Gas for account validation
  /// - [callGasLimit]: Gas for the execution call
  const UnpackedAccountGasLimits({
    required this.verificationGasLimit,
    required this.callGasLimit,
  });

  /// Gas limit for account signature verification.
  final BigInt verificationGasLimit;

  /// Gas limit for the execution call.
  final BigInt callGasLimit;
}

/// Unpacks accountGasLimits into verificationGasLimit + callGasLimit.
///
/// Example:
/// ```dart
/// final unpacked = unpackAccountGasLimits(packed.accountGasLimits);
/// print('Verification: ${unpacked.verificationGasLimit}');
/// print('Call: ${unpacked.callGasLimit}');
/// ```
UnpackedAccountGasLimits unpackAccountGasLimits(String accountGasLimits) {
  final hex = Hex.strip0x(accountGasLimits);

  // Each field is 16 bytes = 32 hex chars
  final verificationHex = hex.substring(0, 32);
  final callHex = hex.substring(32, 64);

  return UnpackedAccountGasLimits(
    verificationGasLimit: BigInt.parse(verificationHex, radix: 16),
    callGasLimit: BigInt.parse(callHex, radix: 16),
  );
}

/// Result of unpacking gasFees.
class UnpackedGasFees {
  /// Creates unpacked gas fee values.
  ///
  /// - [maxPriorityFeePerGas]: Maximum priority fee (tip) per gas
  /// - [maxFeePerGas]: Maximum total fee per gas
  const UnpackedGasFees({
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
  });

  /// Maximum priority fee (tip) per gas unit.
  final BigInt maxPriorityFeePerGas;

  /// Maximum total fee per gas unit (base fee + priority fee).
  final BigInt maxFeePerGas;
}

/// Unpacks gasFees into maxPriorityFeePerGas + maxFeePerGas.
///
/// Example:
/// ```dart
/// final unpacked = unpackGasFees(packed.gasFees);
/// print('Priority: ${unpacked.maxPriorityFeePerGas}');
/// print('Max: ${unpacked.maxFeePerGas}');
/// ```
UnpackedGasFees unpackGasFees(String gasFees) {
  final hex = Hex.strip0x(gasFees);

  // Each field is 16 bytes = 32 hex chars
  final priorityHex = hex.substring(0, 32);
  final maxHex = hex.substring(32, 64);

  return UnpackedGasFees(
    maxPriorityFeePerGas: BigInt.parse(priorityHex, radix: 16),
    maxFeePerGas: BigInt.parse(maxHex, radix: 16),
  );
}

/// Result of unpacking paymasterAndData.
class UnpackedPaymasterAndData {
  /// Creates unpacked paymaster data.
  ///
  /// All fields are null if no paymaster is used.
  const UnpackedPaymasterAndData({
    this.paymaster,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
    this.paymasterData,
    this.paymasterSignature,
  });

  /// The paymaster address, or null if no paymaster.
  final EthereumAddress? paymaster;

  /// The paymaster verification gas limit, or null if no paymaster.
  final BigInt? paymasterVerificationGasLimit;

  /// The paymaster post-op gas limit, or null if no paymaster.
  final BigInt? paymasterPostOpGasLimit;

  /// The paymaster data, or null if no paymaster.
  ///
  /// Excludes any EntryPoint v0.9 signature suffix, which is reported
  /// separately as [paymasterSignature].
  final String? paymasterData;

  /// The EntryPoint v0.9 paymaster signature, or null if the blob carries no
  /// signature suffix.
  final String? paymasterSignature;
}

/// Unpacks paymasterAndData into its components.
///
/// Any EntryPoint v0.9 signature suffix is split out into
/// [UnpackedPaymasterAndData.paymasterSignature] rather than being left on the
/// end of `paymasterData`.
///
/// Example:
/// ```dart
/// final unpacked = unpackPaymasterAndData(packed.paymasterAndData);
/// if (unpacked.paymaster != null) {
///   print('Paymaster: ${unpacked.paymaster!.hex}');
/// }
/// ```
UnpackedPaymasterAndData unpackPaymasterAndData(String paymasterAndData) {
  if (paymasterAndData == '0x' || paymasterAndData.isEmpty) {
    return const UnpackedPaymasterAndData();
  }

  final hex = Hex.strip0x(paymasterAndData);

  // Minimum: paymaster (40) + verificationGas (32) + postOpGas (32) = 104 chars
  if (hex.length < 104) {
    return const UnpackedPaymasterAndData();
  }

  final signatureLength = getPaymasterSignatureLength(paymasterAndData);
  final dataEnd = signatureLength == 0
      ? hex.length
      : hex.length - (signatureLength + paymasterSignatureSuffixLength) * 2;

  return UnpackedPaymasterAndData(
    paymaster: EthereumAddress.fromHex('0x${hex.substring(0, 40)}'),
    paymasterVerificationGasLimit:
        BigInt.parse(hex.substring(40, 72), radix: 16),
    paymasterPostOpGasLimit: BigInt.parse(hex.substring(72, 104), radix: 16),
    paymasterData: dataEnd > 104 ? '0x${hex.substring(104, dataEnd)}' : '0x',
    paymasterSignature:
        signatureLength == 0 ? null : getPaymasterSignature(paymasterAndData),
  );
}

/// Converts a PackedUserOperation back to an unpacked UserOperationV07.
///
/// This is the inverse of [getPackedUserOperation].
///
/// Example:
/// ```dart
/// final packed = getPackedUserOperation(userOp);
/// final unpacked = unpackUserOperation(packed);
/// // unpacked is equivalent to the original userOp
/// ```
UserOperationV07 unpackUserOperation(PackedUserOperation packed) {
  final initCode = unpackInitCode(packed.initCode);
  final gasLimits = unpackAccountGasLimits(packed.accountGasLimits);
  final fees = unpackGasFees(packed.gasFees);
  final paymaster = unpackPaymasterAndData(packed.paymasterAndData);

  return UserOperationV07(
    sender: packed.sender,
    nonce: packed.nonce,
    factory: initCode.factory,
    factoryData: initCode.factoryData,
    callData: packed.callData,
    verificationGasLimit: gasLimits.verificationGasLimit,
    callGasLimit: gasLimits.callGasLimit,
    preVerificationGas: packed.preVerificationGas,
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
    maxFeePerGas: fees.maxFeePerGas,
    paymaster: paymaster.paymaster,
    paymasterVerificationGasLimit: paymaster.paymasterVerificationGasLimit,
    paymasterPostOpGasLimit: paymaster.paymasterPostOpGasLimit,
    paymasterData: paymaster.paymasterData,
    paymasterSignature: paymaster.paymasterSignature,
    signature: packed.signature,
  );
}
