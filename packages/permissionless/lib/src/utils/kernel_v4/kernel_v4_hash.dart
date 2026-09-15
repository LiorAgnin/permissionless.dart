import '../../types/address.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../message_hash.dart';
import '../user_operation_hash.dart';

/// The chain-agnostic userOpHash a Kernel v4 account validates when the nonce
/// carries the replayable mode bit (`0x40`).
///
/// Kernel swaps the EntryPoint-supplied hash for
/// `Lib4337.chainAgnosticUserOpHash`: the same EntryPoint v0.9
/// `PackedUserOperation` struct hash (including the EIP-7702 initCode
/// override and the paymaster-signature strip), but under an EIP-712 domain
/// with **no chainId** —
/// `EIP712Domain(string name,string version,address verifyingContract)` with
/// the EntryPoint's `ERC4337` / `1` and [entryPointAddress] as the verifying
/// contract. An owner signature over this digest is therefore valid on every
/// chain where the same account, EntryPoint, and nonce line up.
///
/// The EntryPoint itself still enforces its per-chain nonce; only the signed
/// digest is chain-agnostic. The `0x40` mode bit lives in `userOp.nonce`, so
/// it is part of what is signed.
///
/// [delegationAddress] supplies the EIP-7702 delegate for operations whose
/// factory is the `0x7702` marker, exactly as in `getUserOperationHash`.
String getKernelV4ChainAgnosticUserOpHash({
  required UserOperationV07 userOperation,
  required EthereumAddress entryPointAddress,
  EthereumAddress? delegationAddress,
}) {
  // The struct hash is identical to the standard v0.9 digest's, so reuse its
  // typed-data builder (paymaster strip, 7702 initCode override, packing) and
  // swap only the domain. The chainId passed here feeds nothing but the
  // domain being replaced, so any value works.
  final standard = getUserOperationTypedData(
    userOperation: userOperation,
    entryPointAddress: entryPointAddress,
    entryPointVersion: EntryPointVersion.v09,
    chainId: BigInt.zero,
    delegationAddress: delegationAddress,
  );
  return hashTypedData(
    TypedData(
      domain: TypedDataDomain(
        name: 'ERC4337',
        version: '1',
        verifyingContract: entryPointAddress,
      ),
      types: {
        ...standard.types,
        'EIP712Domain': const [
          TypedDataField(name: 'name', type: 'string'),
          TypedDataField(name: 'version', type: 'string'),
          TypedDataField(name: 'verifyingContract', type: 'address'),
        ],
      },
      primaryType: standard.primaryType,
      message: standard.message,
    ),
  );
}
