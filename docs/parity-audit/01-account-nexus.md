# Parity Audit: Nexus (Biconomy ERC-7579) Smart Account

**Scope**: permissionless.js v0.3.5 `accounts/nexus/toNexusSmartAccount.ts` vs
permissionless.dart v0.3.0 `lib/src/accounts/nexus/` (`nexus_account.dart`, `constants.dart`, `nexus.dart`).

Paths below are abbreviated:

- **JS** = `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless`
- **Dart** = `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless`

Helper code compared as part of the behavior chain: JS `utils/encode7579Calls.ts`,
`actions/erc7579/supportsExecutionMode.ts` (`encodeExecutionMode`), `actions/public/getAccountNonce.ts`;
Dart `lib/src/utils/erc7579.dart`, `lib/src/utils/message_hash.dart`, `lib/src/accounts/account_owner.dart`,
`lib/src/clients/public/public_client.dart`, `lib/src/clients/smart_account/smart_account_client.dart`.

## Verdict table

| # | Aspect | Verdict | JS | Dart |
|---|--------|---------|----|------|
| 1 | K1ValidatorFactory address `0x00000bb19a3579F4D779215dEf97AFbd0e30DB55` | mirrors | `toNexusSmartAccount.ts:87` | `constants.dart:11-12` |
| 2 | K1Validator address `0x00000004171351c442B202678c48D8AB5B321E8f` | mirrors | `toNexusSmartAccount.ts:88` | `constants.dart:15-16` |
| 3 | factoryData: `createAccount(address,uint256,address[],uint8)` encoding (selector `0x0d51f0b7`, arg order, offset, attester sort) | mirrors | `toNexusSmartAccount.ts:151-180` | `nexus_account.dart:197-223`, `constants.dart:25` |
| 4 | initCode / getFactoryArgs (always factory+factoryData; deployment check external) | mirrors | `toNexusSmartAccount.ts:151-180` | `nexus_account.dart:180-194` |
| 5 | Counterfactual address derivation | mirrors (different RPC mechanism, same result — see note A) | `toNexusSmartAccount.ts:195-226` | `nexus_account.dart:150-176` |
| 6 | Nonce key encoding: `key(3 bytes) ++ 0x00 ++ validator(20 bytes)` as uint192 | mirrors (default key = 0) | `toNexusSmartAccount.ts:227-244` | `nexus_account.dart:129-143`, `public_client.dart:164-176` |
| 7 | Custom nonce key parameter (`args.key % 16777215`) | **missing** | `toNexusSmartAccount.ts:228-229` | `nexus_account.dart:134` (hardcoded `BigInt.zero`) |
| 8 | Dummy/stub signature (offset word + validator word + fixed 65-byte sig) | mirrors | `toNexusSmartAccount.ts:259-262` | `nexus_account.dart:243-252` |
| 9 | signUserOperation: userOpHash computation (EP v0.7 packing) | mirrors | `toNexusSmartAccount.ts:336-345` (viem `getUserOperationHash`) | `nexus_account.dart:353-415` |
| 10 | signUserOperation: returned signature bytes | **diverges** | `toNexusSmartAccount.ts:346-348` (bare 65-byte sig) | `nexus_account.dart:264-275` (validator-prefixed, 85 bytes) |
| 11 | signMessage: ERC-7739 `PersonalSign(bytes prefixed)` wrapping + personal-sign + `validator ++ sig` packing | mirrors | `toNexusSmartAccount.ts:44-74, 266-283` | `nexus_account.dart:279-289, 306-350` |
| 12 | signTypedData: same PersonalSign wrapping quirk + `validator ++ sig` packing | mirrors (see note B) | `toNexusSmartAccount.ts:284-329` | `nexus_account.dart:293-303` |
| 13 | encodeCalls single: `execute(bytes32,bytes)` selector `0xe9ae5c53`, mode byte0=0x00 byte1=0x00, packed `to ++ value(32) ++ data` | mirrors | `encode7579Calls.ts:102-113`, `supportsExecutionMode.ts:46-61` | `erc7579.dart:240-261, 334-349` |
| 14 | encodeCalls batch: mode byte0=0x01, `abi.encode(Execution[])` (target,value,bytes) | mirrors | `encode7579Calls.ts:55-94` | `erc7579.dart:267-329, 354-377` |
| 15 | Delegatecall mode from account `encodeCalls` | mirrors (neither side emits it for Nexus; both libs can encode 0xff) | `toNexusSmartAccount.ts:245-255` | `nexus_account.dart:227-239` |
| 16 | decodeCalls on the account | **missing** | `toNexusSmartAccount.ts:256-258` | no counterpart on `NexusSmartAccount` / `SmartAccount` interface (util `decode7579Calls` exists at `erc7579.dart:756` but is not wired) |
| 17 | EntryPoint version: v0.7 only | mirrors | `toNexusSmartAccount.ts:143-147` | `nexus_account.dart:112, 123`; `constants/entry_point.dart:21-22` |
| 18 | Custom EntryPoint address override (`entryPoint: {address, version: "0.7"}`) | **missing** | `toNexusSmartAccount.ts:106-109, 143-147` | `nexus_account.dart:123` (hardcoded `EntryPointAddresses.v07`) |
| 19 | Module install hooks during setup (none — K1 factory installs the validator) | mirrors | `toNexusSmartAccount.ts` (absent by design) | `nexus_account.dart` (absent by design) |
| 20 | `computeAccountAddress` selector constant | **dart-only** (dead code, and the value is wrong) | `toNexusSmartAccount.ts:200-214` (uses ABI by name) | `constants.dart:27-28` |

Counts: 14 mirrors, 1 diverges, 3 missing, 1 dart-only (incorrect dead constant), 1 n/a folded into mirrors (#15).

---

## Finding 10 — diverges: `signUserOperation` prepends the validator address (HIGH severity)

**JS** (`toNexusSmartAccount.ts:330-349`) hashes the userOp and returns the owner's bare
EIP-191 signature — 65 bytes, **no validator prefix**:

```ts
return await localOwner.signMessage({
    message: { raw: hash as Hex }
})
```

**Dart** (`nexus_account.dart:264-275`) packs the validator address in front, producing an
85-byte signature:

```dart
final signature = await _config.owner.signPersonalMessage(userOpHash);
// Pack: validator address + signature (85 bytes total)
return Hex.concat([
  _validatorAddress.hex,
  Hex.strip0x(signature),
]);
```

Why this matters on-chain: for Nexus, the validator module is selected via the **nonce key**
(aspect #6), and `Nexus.validateUserOp` forwards `userOp.signature` untouched to
`K1Validator.validateUserOp`, which does an ECDSA recover expecting a 65-byte signature.
An 85-byte signature fails recovery, so every Dart-signed Nexus UserOperation should be
rejected with signature-validation failure (AA24). The validator-prefix packing is correct
for ERC-1271 `signMessage`/`signTypedData` (aspects #11/#12, where JS does the same
`encodePacked(["address","bytes"])`) — it was incorrectly carried over to the userOp path.
The doc comment at `nexus_account.dart:258-262` asserts this prefix is expected, which
contradicts the TS reference.

Fix: return the bare 65-byte `signPersonalMessage(userOpHash)` result.

The hash computed before signing (aspect #9) was verified field-by-field against viem's
v0.7 `getUserOperationHash` packing (`keccak(abi.encode(sender, nonce, keccak(initCode),
keccak(callData), accountGasLimits, preVerificationGas, gasFees, keccak(paymasterAndData)))`
then `keccak(abi.encode(hash, entryPoint, chainId))`) — that part mirrors
(`nexus_account.dart:353-415`).

## Finding 7 — missing: custom nonce key input

**JS** (`toNexusSmartAccount.ts:227-235`) accepts a caller-supplied key and folds it into the
top 3 bytes of the 24-byte key:

```ts
const TIMESTAMP_ADJUSTMENT = 16777215n // max value for size 3
const defaultedKey = (args?.key ?? 0n) % TIMESTAMP_ADJUSTMENT
const key = concat([toHex(defaultedKey, { size: 3 }), "0x00", validatorAddress])
```

**Dart** (`nexus_account.dart:129-143`) exposes `nonceKey` as a getter with the key portion
hardcoded to zero (`final defaultedKey = BigInt.zero % BigInt.from(timestampAdjustment);`),
and `smart_account_client.dart:224-229` passes it straight to
`publicClient.getAccountNonce(..., nonceKey: account.nonceKey)`. There is no way to use a
parallel nonce lane. The default (key = 0) path is byte-identical to JS:
`0x000000 ++ 0x00 ++ validator` interpreted as uint192 and passed to
`EntryPoint.getNonce(address,uint192)` (`public_client.dart:164-176`, selector `0x35567e1a`
matches JS `getAccountNonce`).

## Finding 16 — missing: `decodeCalls`

**JS** wires `decode7579Calls` into the account (`toNexusSmartAccount.ts:256-258`), used by
viem's `sendCalls`/debugging paths. **Dart** has an equivalent standalone util
(`erc7579.dart:756`, `decode7579Calls`) but the `SmartAccount` interface
(`lib/src/clients/smart_account/smart_account_interface.dart`) has no `decodeCalls` member
and `NexusSmartAccount` does not expose it. Library-wide interface gap, not Nexus-specific;
low impact (encode path is what goes on-chain).

## Finding 18 — missing: EntryPoint address override

**JS** allows `entryPoint: { address, version: "0.7" }` (`toNexusSmartAccount.ts:106-109`),
defaulting to `entryPoint07Address` (`toNexusSmartAccount.ts:143-147`). **Dart** hardcodes
`EntryPointAddresses.v07` (`nexus_account.dart:123`,
`constants/entry_point.dart:21-22` = `0x0000000071727De22E5E9d8BAf0edAc6f37da032`, which
matches viem's `entryPoint07Address`). Only affects users pointing at a non-canonical
EntryPoint deployment; the default is byte-identical. Note the hardcoded EntryPoint is also
baked into the manual userOpHash (`nexus_account.dart:359`), so an override would need to
flow there too.

## Finding 20 — dart-only: incorrect (dead) `computeAccountAddress` selector

**Dart** `constants.dart:27-28` declares:

```dart
/// computeAccountAddress(address eoaOwner, uint256 index, address[] attesters, uint8 threshold)
static const String computeAccountAddress = '0x8b97fea1';
```

The actual selector for `computeAccountAddress(address,uint256,address[],uint8)` is
**`0x322cc8ca`** (computed with viem `toFunctionSelector`; the `createAccount` selector
`0x0d51f0b7` at `constants.dart:25` was verified correct the same way). The constant is
referenced nowhere in `lib/` or `test/`, so there is no behavioral impact today — but if
anyone wires it up to replicate the JS `getAddress` path (`toNexusSmartAccount.ts:198-223`),
the eth_call will revert. Recommend fixing the value or deleting the constant.

---

## Note A — address derivation mechanism

JS calls the factory's view function `computeAccountAddress(eoaOwner, index, attesters,
threshold)` directly (`toNexusSmartAccount.ts:195-226`). Dart instead builds the initCode
and simulates `EntryPoint.getSenderAddress(initCode)` via `publicClient.getSenderAddress`
(`nexus_account.dart:161-168`), or accepts a precomputed `address`, and throws a
`StateError` if neither is available (`nexus_account.dart:171-175`). Since the initCode runs
the same `createAccount` calldata (verified byte-identical, aspect #3) against the same
factory, the resulting CREATE2 address is the same — mechanism differs, behavior does not.
Attester sorting is also equivalent: JS `localeCompare` on lowercased hex
(`toNexusSmartAccount.ts:173-175`) vs Dart `compareTo` on lowercased hex
(`nexus_account.dart:199-200`) yield the same lexicographic order for `0x`-prefixed
hex strings.

## Note B — signTypedData validation and wrapping quirk

Both sides wrap the EIP-712 digest with the ERC-7739 **PersonalSign** typehash
(`keccak256("PersonalSign(bytes prefixed)")`) inside the Nexus domain
(`name: "Nexus", version, chainId, verifyingContract`) — JS `toNexusSmartAccount.ts:44-74,
313-317`; Dart `nexus_account.dart:306-350`. This is arguably a bug upstream (typed data
"should" use the TypedDataSign wrapper), but the Dart port faithfully reproduces the JS
bytes, which is what parity requires. Dart's EIP-712 hashing chain
(`message_hash.dart:52-107` — domain separator with only-present fields, `0x1901` prefix)
matches viem's `hashTypedData`/`domainSeparator`. The only difference: JS runs
`validateTypedData` before hashing (`toNexusSmartAccount.ts:299-304`), Dart does not —
input validation only, no byte difference for valid input. Signing of the wrapped hash uses
EIP-191 personal-sign on both sides (viem `signMessage({raw})` vs web3dart
`signPersonalMessageToUint8List`, `account_owner.dart:116-129`), and both pack
`validator ++ signature` (JS `encodePacked(["address","bytes"])`,
`toNexusSmartAccount.ts:279-282, 325-328`; Dart `Hex.concat`,
`nexus_account.dart:285-288, 299-302`).

## Note C — execution mode bytes

JS Nexus passes `revertOnError: false`, which `encodeExecutionMode` maps to execType byte
`0x00` (`supportsExecutionMode.ts:56` — `revertOnError ? "0x01" : "0x00"`; the JS field is
confusingly named). Dart `encode7579ExecuteMode` defaults execType to `0x00`
(`erc7579.dart:240-249`). Resulting 32-byte mode is identical
(`0x00/0x01` calltype, `0x00` exectype, 30 zero bytes). Beware: Dart's separate
`ExecutionMode.encode()` class (`erc7579.dart:195-225`) uses the **opposite** boolean
convention (`revertOnError ? 0x00 : 0x01`) — not used by the Nexus account, so out of
scope here, but flagged for the ERC-7579 utils audit unit.
