# Parity Audit: Thirdweb Smart Account

**Scope**: permissionless.js v0.3.5 `accounts/thirdweb/` vs permissionless.dart v0.3.0 `lib/src/accounts/thirdweb/`

**JS files**:
- `permissionless.js/packages/permissionless/accounts/thirdweb/toThirdwebSmartAccount.ts`
- `permissionless.js/packages/permissionless/accounts/thirdweb/utils/{getFactoryData,getAccountAddress,encodeCallData,decodeCallData,signMessage,signTypedData}.ts`

**Dart files**:
- `permissionless.dart/packages/permissionless/lib/src/accounts/thirdweb/thirdweb_account.dart`
- `permissionless.dart/packages/permissionless/lib/src/accounts/thirdweb/constants.dart`
- `permissionless.dart/packages/permissionless/lib/src/accounts/thirdweb/thirdweb.dart` (barrel)

Selectors were independently verified with `cast sig`: `createAccount(address,bytes)` = `0xd8fd8f44`, `execute(address,uint256,bytes)` = `0xb61d27f6`, `executeBatch(address[],uint256[],bytes[])` = `0x47e1da2a`, `getAddress(address,bytes)` = `0x8878ed33` — all match the Dart constants.

## Verdict Table

| # | Aspect | Verdict |
|---|--------|---------|
| 1 | Factory address, EP v0.6 (`0x85e23b94e7F5E9cC1fF78BCe78cfb15B81f0DF00`) | mirrors |
| 2 | Factory address, EP v0.7 (`0x4be0ddfebca9a5a4a617dee4dece99e7c862dceb`) | mirrors |
| 3 | factoryData / initCode encoding (`createAccount(address,bytes)`) | mirrors |
| 4 | Salt interpretation (string -> bytes) | **diverges** |
| 5 | Counterfactual address derivation | mirrors (different mechanism, same result) |
| 6 | Stub / dummy signature | mirrors (byte-identical) |
| 7 | `execute` single-call calldata | mirrors |
| 8 | `executeBatch` calldata | mirrors |
| 9 | `decodeCalls` | **missing** |
| 10 | `signUserOperation`, EP v0.7 (EIP-191 over userOpHash) | mirrors |
| 11 | `signUserOperation`, EP v0.6 | **missing** |
| 12 | `signMessage` ERC-1271 `AccountMessage` wrapping | **diverges** |
| 13 | `signTypedData` ERC-1271 wrapping | **diverges** |
| 14 | `signTypedData` self-verifying-contract detection | **diverges** |
| 15 | `sign({ hash })` | missing (minor) |
| 16 | `getNonce` / nonceKey plumbing | mirrors |

Summary: 9 mirrors, 4 diverges, 3 missing.

### Notes on "mirrors" rows

- **1–2 (factory addresses)**: JS `toThirdwebSmartAccount.ts:39-52` (`THIRDWEB_ADDRESSES["0.6"]["1.5.20"]` / `["0.7"]["1.5.20"]`) vs Dart `constants.dart:10-15` (`factoryV06` / `factoryV07`), selected per EP version at `thirdweb_account.dart:85-89` matching JS `toThirdwebSmartAccount.ts:120-123`. Byte-identical (case differs, addresses equal). The JS `version: "1.5.20"` parameter has exactly one value, so Dart omitting it is non-behavioral.
- **3 (factoryData)**: JS `utils/getFactoryData.ts:11-39` encodes `createAccount(address _admin, bytes _salt)`; Dart `thirdweb_account.dart:171-189` hand-encodes selector `0xd8fd8f44` + admin address + dynamic-bytes head at offset 64 + length + right-padded data — standard ABI, identical output for the same salt bytes. Both sides use it for v0.6 initCode (`thirdweb_account.dart:154-160`) and v0.7 factory/factoryData (`thirdweb_account.dart:164-168`), matching JS `getFactoryArgs` (`toThirdwebSmartAccount.ts:139-147`).
- **5 (address)**: JS calls the factory's on-chain `getAddress(_adminSigner, _data)` view (`utils/getAccountAddress.ts:11-47`); Dart uses a pre-supplied `address` or `EntryPoint.getSenderAddress` simulation with the initCode (`thirdweb_account.dart:124-150`), and throws a `StateError` if neither is available (`thirdweb_account.dart:146-149`). Both produce the counterfactual `createAccount` deployment address, so results agree given the same salt bytes (see finding 4 for when salt bytes differ). Dart's unused `ThirdwebSelectors.getAddress` constant (`constants.dart:33`) suggests a local factory-call path was planned but not built.
- **6 (stub signature)**: JS `toThirdwebSmartAccount.ts:177-179` and Dart `thirdweb_account.dart:301-302` — verified byte-identical by string comparison.
- **7–8 (execute/executeBatch)**: JS `utils/encodeCallData.ts:10-80` — batch iff `calls.length > 1`, else single `execute`, throw on empty. Dart `thirdweb_account.dart:215-225` implements the same dispatch. Single-call encoding (`thirdweb_account.dart:193-211`): selector `0xb61d27f6`, address, value, bytes head at offset 96 — correct. Batch encoding (`thirdweb_account.dart:228-297`): three heads at 0x60, array lengths, per-element `bytes[]` offsets relative to the array data area — hand-checked against canonical ABI encoding, matches `encodeFunctionData` output including empty-`data` elements (JS defaults `value ?? 0n`, `data ?? "0x"`; Dart `Call` carries concrete values).
- **10 (v0.7 signUserOperation)**: JS `toThirdwebSmartAccount.ts:199-219` — `admin.signMessage({ raw: getUserOperationHash(...) })`, i.e. EIP-191 `personal_sign` over the raw 32-byte v0.7 userOpHash with empty signature field. Dart `thirdweb_account.dart:306-309` calls `owner.signPersonalMessage(userOpHash)` (EIP-191 prefix `\x19Ethereum Signed Message:\n32`, `account_owner.dart:116-129`), with the hash computed locally in `_computeUserOpHash`/`_packUserOpForHash` (`thirdweb_account.dart:379-441`). The packing (sender, nonce, keccak(initCode), keccak(callData), accountGasLimits as 16+16 bytes, preVerificationGas, gasFees as 16+16 bytes, keccak(paymasterAndData); then keccak(hash ++ entryPoint ++ chainId)) matches viem's v0.7 `getUserOperationHash` exactly.
- **16 (nonce)**: JS `toThirdwebSmartAccount.ts:170-176` (`parameters.nonceKey ?? args.key`); Dart exposes `nonceKey` (default 0) at `thirdweb_account.dart:113-114` for the client to use. Same effective behavior.

---

## Finding 4 — Salt interpretation (diverges)

**JS**: the `salt` string is converted with viem's `toHex`, which UTF-8-encodes the string into bytes:

- `toThirdwebSmartAccount.ts:144` — `salt: salt ? toHex(salt) : "0x"` (factoryData)
- `toThirdwebSmartAccount.ts:159` — `salt: salt ? toHex(salt) : "0x"` (getAddress)

So JS `salt: "1234"` produces salt bytes `0x31323334` (ASCII), and even an explicit `salt: "0x"` is truthy and becomes `0x3078`.

**Dart**: the `salt` string is parsed as a hex string:

- `thirdweb_account.dart:173-174` — `final salt = _config.salt.isEmpty ? '0x' : _config.salt; final saltBytes = Hex.decode(salt);` (`Hex.decode` strips `0x` and hex-decodes, `types/hex.dart:17-22`)

So Dart `salt: '1234'` produces salt bytes `0x1234`.

**Impact**: the two implementations agree only for the default (JS `salt` omitted -> `"0x"`; Dart default `'0x'` -> empty bytes). For any user-supplied salt they produce different `createAccount` calldata and therefore **different counterfactual account addresses**. A user porting `salt: "my-salt"` from JS to Dart (or passing a hex salt in either direction) lands on a different account. Dart would need to UTF-8-encode non-hex salts (and hex-encode the literal characters of `0x…` strings) to match JS byte-for-byte.

---

## Finding 9 — decodeCalls (missing)

**JS**: `utils/decodeCallData.ts:3-87` decodes calldata back to a call list — tries `executeBatch(address[],uint256[],bytes[])` first, falls back to `execute(address,uint256,bytes)` — and is wired into the account at `toThirdwebSmartAccount.ts:167-169`.

**Dart**: no decode API exists on `ThirdwebSmartAccount` or on the `SmartAccount` interface (`lib/src/clients/smart_account/smart_account_interface.dart:20-114` has only `encodeCall`/`encodeCalls`). This is a library-wide gap, not thirdweb-specific, but it is part of the JS thirdweb surface.

**Impact**: functionality absent; no wrong bytes produced.

---

## Finding 11 — signUserOperation for EntryPoint v0.6 (missing)

**JS**: fully supports EP v0.6 — the entryPoint version flows into `getUserOperationHash` (`toThirdwebSmartAccount.ts:199-219`, version at `toThirdwebSmartAccount.ts:105-112`), which uses the v0.6 packing (initCode/paymasterAndData as flat fields, separate gas fields).

**Dart**: the account advertises v0.6 support — `entryPointVersion` config defaults to v0.7 but accepts v0.6 (`thirdweb_account.dart:34,51`), `factoryV06` is selected (`thirdweb_account.dart:86-89`), `entryPoint` returns `EntryPointAddresses.v06` (`thirdweb_account.dart:107-110`), and `getInitCode()` exists (`thirdweb_account.dart:154-160`) — **but there is no v0.6 signing path**:

- `ThirdwebSmartAccount implements SmartAccount` only (`thirdweb_account.dart:80`); it does not implement `SmartAccountV06` (`smart_account_interface.dart:120-130`), unlike `BiconomySmartAccount` (`biconomy/biconomy_account.dart:81`) and `TrustSmartAccount` (`trust/trust_account.dart:81`).
- `SmartAccountClient.signUserOperationV06` therefore throws `StateError('Account does not support v0.6 signing...')` (`smart_account_client.dart:541-547`).
- `signUserOperation` takes a `UserOperationV07` and `_computeUserOpHash` packs only the v0.7 format (`thirdweb_account.dart:306-309, 379-441`); there is no v0.6 hash computation.

**Impact**: a Thirdweb account configured with `EntryPointVersion.v06` can build init code and encode calls but cannot sign — the v0.6 half of the account is a trap. JS handles both versions end-to-end.

---

## Finding 12 — signMessage ERC-1271 wrapping (diverges)

Both sides build the same `AccountMessage` EIP-712 wrapper (domain `{name: "Account", version: "1", chainId, verifyingContract: accountAddress}`, type `AccountMessage(bytes message)`, message = EIP-191 hash of the input):

- JS: `utils/signMessage.ts:20-32`
- Dart: `thirdweb_account.dart:313-332`

**But the final signing step differs:**

- **JS** (`signMessage.ts:22`): `admin.signTypedData(...)` — the owner signs the **EIP-712 digest directly** (`keccak256("\x19\x01" ++ domainSeparator ++ structHash)`), no EIP-191 prefix.
- **Dart** (`thirdweb_account.dart:334-336`): `final wrappedHash = hashTypedData(wrappedTypedData); return _config.owner.signPersonalMessage(wrappedHash);` — the EIP-712 digest is **re-wrapped with the EIP-191 prefix** (`"\x19Ethereum Signed Message:\n32" ++ digest`, `account_owner.dart:116-129`) before signing.

**Impact**: the Dart signature is over a different final digest and will **fail ERC-1271 `isValidSignature` verification** on the Thirdweb account contract, which recovers against the EIP-712 digest. Dart's `AccountOwner.signTypedData` (`account_owner.dart:151-168`) signs the EIP-712 hash directly and is what should be called here (the in-code comment "Thirdweb signs typed data with personal message prefix" at `thirdweb_account.dart:334` does not match the JS reference).

Secondary scope note: JS accepts `SignableMessage` (UTF-8 string or `{ raw: hex }`); Dart `signMessage(String)` UTF-8-encodes only (`utils/message_hash.dart:22-36`), so raw-bytes messages cannot be expressed.

---

## Finding 13 — signTypedData ERC-1271 wrapping (diverges)

Same root cause as Finding 12, in both branches:

- **Wrapping branch** — JS `utils/signTypedData.ts:50-66`: hashes the caller's typed data, ABI-encodes the hash as `bytes32`, and signs the `AccountMessage` wrapper via `admin.signTypedData` (direct EIP-712 digest signature). Dart `thirdweb_account.dart:351-375`: builds the identical wrapper (the `encodeUint256(BigInt.parse(typedHash))` at `thirdweb_account.dart:353-355` is equivalent to JS's `encodeAbiParameters([{type:"bytes32"}], [typedHash])` at `signTypedData.ts:51-54`), but then signs `signPersonalMessage(hashTypedData(wrapper))` (`thirdweb_account.dart:374-375`) — EIP-191 prefix added on top of the EIP-712 digest.
- **Self-verifying branch** — JS `signTypedData.ts:27-31`: `admin.signTypedData(typedData)` (direct). Dart `thirdweb_account.dart:344-349`: `signPersonalMessage(hashTypedData(typedData))` (prefixed).

**Impact**: as with Finding 12, Dart signatures are over `keccak256("\x19Ethereum Signed Message:\n32" ++ eip712Digest)` instead of the EIP-712 digest itself, and will not verify via ERC-1271. Fix is to route both branches through `owner.signTypedData` / a raw-digest sign of the EIP-712 hash.

---

## Finding 14 — signTypedData self-verifying-contract detection (diverges)

- **JS** (`utils/signTypedData.ts:21-24`):
  ```ts
  const isSelfVerifyingContract =
      (typedData.domain as TypedDataDomain)?.verifyingContract?.toLowerCase() === accountAddress
  ```
  Only the left side is lowercased; `accountAddress` (from `this.getAddress()`, an EIP-55 checksummed address) almost always contains uppercase characters, so this comparison is effectively **always false** — JS in practice always takes the wrapping branch. (This is a known-looking case-sensitivity bug in the reference.)
- **Dart** (`thirdweb_account.dart:345-346`): lowercases **both** sides, so the check works as intended and the self-verifying branch is actually reachable.

**Impact**: for typed data whose `verifyingContract` equals the account address, JS wraps it in `AccountMessage` while Dart signs it directly — different signatures for the same input. Dart implements the intended semantics; JS exhibits the buggy ones. Flagged because the audit criterion is behavioral parity with the reference: if byte-parity with permissionless.js is the goal, Dart differs here; if correctness is the goal, Dart is right and the JS bug should be documented instead.

---

## Finding 15 — `sign({ hash })` (missing, minor)

**JS** (`toThirdwebSmartAccount.ts:180-182`): exposes `sign({ hash })`, delegating to `signMessage({ message: hash })` (viem treats the hex string as a raw-hash message). Used by viem tooling (e.g. ERC-6492 flows).

**Dart**: no `sign` method on `ThirdwebSmartAccount` or the `SmartAccount` interface (`smart_account_interface.dart:20-114`). Interface-wide gap; and since Dart's `signMessage` UTF-8-encodes its input, the JS behavior (`{ raw: hash }`) cannot currently be reproduced through it.
