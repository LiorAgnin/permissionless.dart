# Parity Audit: Kernel (ZeroDev) Smart Account

**Scope:** permissionless.js v0.3.5 `accounts/kernel/` vs permissionless.dart v0.3.0 `lib/src/accounts/kernel/`

**JS files audited:**
- `permissionless.js/packages/permissionless/accounts/kernel/toKernelSmartAccount.ts`
- `permissionless.js/packages/permissionless/accounts/kernel/toEcdsaKernelSmartAccount.ts`
- `permissionless.js/packages/permissionless/accounts/kernel/to7702KernelSmartAccount.ts`
- `permissionless.js/packages/permissionless/accounts/kernel/constants.ts`
- `permissionless.js/packages/permissionless/accounts/kernel/utils/{encodeCallData,decodeCallData,getNonceKey,isKernelV2,signMessage,signTypedData,wrapMessageHash}.ts`
- `permissionless.js/packages/permissionless/accounts/kernel/abi/*.ts`
- `permissionless.js/packages/permissionless/utils/encode7579Calls.ts`, `actions/erc7579/supportsExecutionMode.ts` (mode encoding)

**Dart files audited:**
- `permissionless.dart/packages/permissionless/lib/src/accounts/kernel/kernel_account.dart`
- `permissionless.dart/packages/permissionless/lib/src/accounts/kernel/eip7702_kernel_account.dart`
- `permissionless.dart/packages/permissionless/lib/src/accounts/kernel/constants.dart`
- `permissionless.dart/packages/permissionless/lib/src/accounts/kernel/kernel.dart`
- Supporting: `lib/src/utils/erc7579.dart`, `lib/src/utils/webauthn_encoding.dart`, `lib/src/accounts/account_owner.dart`, `lib/src/utils/message_hash.dart`

All function selectors below were independently verified with `cast sig`.

---

## Verdict Table

| # | Aspect | Verdict |
|---|--------|---------|
| 1 | Contract addresses for shared versions (0.2.4, 0.3.1, 0.3.3) | mirrors |
| 2 | Version coverage (0.2.1–0.2.3, 0.3.0-beta, 0.3.2) | missing (M1) |
| 3 | Default Kernel version for EP v0.7 (JS: 0.3.0-beta, Dart: 0.3.1) | diverges (D4) |
| 4 | EP v0.6 factoryData: `createAccount(address,bytes,uint256)` + `initialize(address,bytes)` | mirrors |
| 5 | EP v0.7 factoryData: metaFactory `deployWithFactory(address,bytes,bytes32)`, salt = bytes32(index) | mirrors |
| 6 | `useMetaFactory: false / "optional"` factory paths | missing (M2) |
| 7 | v0.3.1+ `initialize(bytes21,address,bytes,bytes,bytes[])` rootValidator encoding (`0x01 ++ validator`, hook=0, initConfig=[]) | mirrors |
| 8 | WebAuthn validator init data (`tuple(x,y)`, `keccak256(credentialId)`) | mirrors |
| 9 | Address resolution via `getSenderAddress` / explicit address | mirrors |
| 10 | **v0.2.x execute / executeBatch calldata selectors** | **diverges (D1, critical)** |
| 11 | v0.3.x ERC-7579 execute encoding (mode bytes, packed single call, batch tuple[]) | mirrors |
| 12 | Unpatched-kernel migration in `encodeCalls` (`MIGRATION_HELPER_ADDRESS`, `rootValidator` patch check) | missing (M4) |
| 13 | `decodeCalls` | missing (M5) |
| 14 | Nonce key structural encoding (v3: `00 ‖ 00 ‖ validator ‖ 0000` = 24 bytes; v2: plain) | mirrors |
| 15 | Custom `nonceKey` parameter (JS: ≤ maxUint16 for v3, passthrough for v2) | missing (M3) |
| 16 | Dummy/stub signature — v2 (`0x00000000 ++ dummy`) and v3 ECDSA | mirrors |
| 17 | Dummy/stub signature — v3 WebAuthn | diverges (D5, minor) |
| 18 | **signUserOperation (ECDSA): EIP-191 wrap of userOpHash** | **diverges (D3)** |
| 19 | signUserOperation v2 sudo prefix `0x00000000` | mirrors |
| 20 | **signMessage / signTypedData (ERC-1271): Kernel EIP-712 wrapping + root-validator prefix** | **diverges (D2, major)** |
| 21 | EP v0.6 vs v0.7 dispatch & userOpHash computation (incl. `signUserOperationV06` path) | mirrors |
| 22 | 7702: address = EOA, no factory, authorization → accountLogic (0.3.3) | mirrors |
| 23 | 7702: userOp signing (EIP-191 wrap + raw ECDSA, no prefix) | mirrors |
| 24 | 7702: 1271 signing (Kernel EIP-712 domain typed-data + `0x00` EIP7702 identifier prefix) | mirrors |
| 25 | 7702: pre-delegation 1271 guard | mirrors (with caveat: Dart skips check when no `publicClient`) |
| 26 | `toEcdsaKernelSmartAccount` deprecated alias | missing (M6, trivial) |
| 27 | WebAuthn owner allowed on v0.3.3 (JS has no WEB_AUTHN_VALIDATOR for 0.3.2/0.3.3 and throws) | dart-only (O1) |
| 28 | Dynamic RIP-7212 precompile detection for WebAuthn | dart-only (O2) |
| 29 | Explicit `signUserOperationV06` / separate `Eip7702KernelSmartAccount` class | dart-only (O3, behavior-equivalent) |

**Counts:** mirrors: 15 · diverges: 4 · missing: 6 · dart-only: 3

---

## D1 (critical) — Kernel v0.2.x execute/executeBatch use wrong function selectors

**Verdict: diverges.** Any single or batch call on a Kernel v0.2.4 account produced by the Dart library targets non-existent functions and will revert on-chain.

JS encodes v2 calls against `KernelExecuteAbi`:

- `permissionless.js/.../accounts/kernel/utils/encodeCallData.ts:19-46` — `encodeFunctionData({ abi: KernelExecuteAbi, functionName: "execute" | "executeBatch", ... })`
- `permissionless.js/.../accounts/kernel/abi/KernelAccountAbi.ts:4-60` — `execute(address to, uint256 value, bytes data, uint8 operation)` and `executeBatch((address,uint256,bytes)[] calls)`

Correct selectors (verified with `cast sig`):

- `execute(address,uint256,bytes,uint8)` → **`0x51945447`**
- `executeBatch((address,uint256,bytes)[])` → **`0x34fcd5be`**

Dart hardcodes the **SimpleAccount** selectors instead:

- `permissionless.dart/.../lib/src/accounts/kernel/constants.dart:132` — `executeV2 = '0xb61d27f6'` — this is `execute(address,uint256,bytes)` (3-arg SimpleAccount form), yet `kernel_account.dart:471-478` appends **four** parameters (to, value, data-offset, operation) after it. Wrong selector *and* the body doesn't even match the selector's signature.
- `permissionless.dart/.../lib/src/accounts/kernel/constants.dart:135` — `executeBatchV2 = '0x47e1da2a'` — this is `executeBatch(address[],uint256[],bytes[])` (SimpleAccount), while `kernel_account.dart:497-525` encodes the Kernel tuple-array layout after it.

Fix: change `executeV2` to `0x51945447` and `executeBatchV2` to `0x34fcd5be` (parameter encoding in `_encodeCallV2` / `_encodeCallsV2` already matches the Kernel v2 ABI layout).

---

## D2 (major) — signMessage/signTypedData: no Kernel EIP-712 wrapping and no root-validator prefix (non-7702 account)

**Verdict: diverges.** ERC-1271 signatures produced by the Dart `KernelSmartAccount` will not verify on-chain.

JS behavior (`toKernelSmartAccount.ts:890-947` + `utils/signMessage.ts`, `utils/signTypedData.ts`, `utils/wrapMessageHash.ts`):

1. For all versions except 0.2.1/0.2.2 (`signMessage.ts:100-104`), the EIP-191/EIP-712 hash is wrapped via `wrapMessageHash` (`wrapMessageHash.ts:19-43`): `digest = keccak256(0x1901 ‖ domainSeparator({name:"Kernel", version: kernelVersion, chainId, verifyingContract: account}) ‖ h)` where for v3 `h = keccak256(keccak256("Kernel(bytes32 hash)") ‖ messageHash)` and for v2 `h = messageHash`.
2. For v3, the final signature is prefixed with the root validator identifier `0x01 ‖ validatorAddress` (`toKernelSmartAccount.ts:910-917`, `:939-946`, via `getEcdsaRootIdentifierForKernelV3` at `:255-263`). Kernel v2 returns the bare signature.

Dart behavior:

- `permissionless.dart/.../kernel_account.dart:655-669` (`signMessage`) — signs `hashMessage(message)` directly with `signRawHash`; no Kernel domain wrap, no `0x01 ‖ validator` prefix.
- `permissionless.dart/.../kernel_account.dart:677-690` (`signTypedData`) — delegates to `owner.signTypedData(typedData)` (raw EIP-712 hash of the *user's* typed data, see `account_owner.dart:152-170`); no Kernel wrap, no prefix.
- The WebAuthn branches (`kernel_account.dart:658-666`, `:678-687`) sign the unwrapped hash too, whereas JS wraps string messages/typed-data hashes before `owner.sign` (`signMessage.ts:33-44`, `signTypedData.ts:78-88`).

This also affects v0.2.4: JS wraps for 0.2.3/0.2.4 (only 0.2.1/0.2.2 sign plainly, `signMessage.ts:100-104`), while Dart 0.2.4 signs plainly.

Note the Dart **7702** variant does implement the correct wrapping and prefix (`eip7702_kernel_account.dart:479-510`), so the fix is to port that logic (with `0x01 ‖ validatorAddress` instead of `0x00`, and the `Kernel(bytes32 hash)` struct-hash step) into `KernelSmartAccount`.

---

## D3 — signUserOperation (ECDSA): Dart signs the raw userOpHash; JS signs the EIP-191-wrapped hash

**Verdict: diverges.**

- JS: `toKernelSmartAccount.ts:973-975` — `owner.signMessage({ message: { raw: hash } })`, i.e. the signed digest is `keccak256("\x19Ethereum Signed Message:\n32" ‖ userOpHash)`.
- Dart: `kernel_account.dart:586` — `_config.owner.signRawHash(userOpHash)`, which signs the bare 32-byte hash with no prefix (`account_owner.dart:135-149`), for both v0.2.4 (`:588-593`, after which the `0x00000000` sudo prefix is added — the prefix itself mirrors JS `toKernelSmartAccount.ts:978-980`) and v0.3.x (`:594-597`). Same for `signUserOperationV06` (`kernel_account.dart:604-613`).

Byte output differs from the JS reference. In practice ZeroDev's ECDSA validators accept **both** the raw and eth-signed digest, so operations still validate on-chain, but this is a reference divergence and is internally inconsistent with the Dart 7702 variant, which *does* apply the EIP-191 wrap (`eip7702_kernel_account.dart:329-337`, matching JS).

---

## D4 — Default Kernel version for EntryPoint v0.7

**Verdict: diverges.**

- JS: `toKernelSmartAccount.ts:195-210` — default is `"0.2.2"` for EP v0.6 and **`"0.3.0-beta"`** for EP v0.7 (and `0.3.3` when eip7702).
- Dart: `kernel_account.dart:35` / `:784` — default is `KernelVersion.v0_3_1`; there is no v0.3.0-beta at all (see M1), and the Dart v0.6 default (v0.2.4) differs from JS's 0.2.2.

Consequence: a user porting JS code without an explicit `version` gets a **different account implementation, factory, validator, and therefore a different counterfactual address**. JS 0.3.0-beta addresses (`toKernelSmartAccount.ts:163-169`): logic `0x94F097E1ebEB4ecA3AAE54cabb08905B239A7D27`, factory `0x6723b44Abeec4E71eBE3232BD5B455805baDD22f`, ECDSA validator `0x8104e3Ad430EA6d354d013A6789fDFc71E671c43` — none exist in `constants.dart`. Also note 0.3.0-beta uses the 4-arg `initialize(bytes21,address,bytes,bytes)` (`toKernelSmartAccount.ts:292-303`, selector `0x12af322c`), which Dart does not implement.

---

## D5 (minor) — WebAuthn stub signature contents and `usePrecompiled` flag

**Verdict: diverges** (gas-estimation surface only, plus a flag difference in real signatures).

- JS stub: `toKernelSmartAccount.ts:864-883` — fixed `authenticatorData` `0x49960de5...631d00000000` (37 bytes), a long fixed `clientDataJSON` (includes the "other_keys_can_be_added_here" filler), fixed r/s values, and `usePrecompiled` hard-coded to `false`. Real WebAuthn signatures also always encode `usePrecompiled: false` (`utils/signMessage.ts:63-79`, "TODO: check if it is a RIP 7212 supported network").
- Dart stub: `kernel_account.dart:561-563` + `webauthn_encoding.dart:78-103` — 37 zero bytes of authenticatorData, a much shorter dummy clientDataJSON, different r/s, and `usePrecompiled` set dynamically from chain support (`shouldUseP256Precompile` / `isRip7212Supported`, `kernel_account.dart:543-548`, `:576-582`).

Estimated calldata size differs (shorter clientDataJSON → potentially under-estimated gas vs JS), and on RIP-7212 chains Dart's real signatures set `usePrecompiled=true` where JS always sends `false`. Dart's dynamic detection is arguably an improvement, but it is a behavioral difference from the reference.

---

## M1 — Missing Kernel versions 0.2.1, 0.2.2, 0.2.3, 0.3.0-beta, 0.3.2

JS supports eight versions (`toKernelSmartAccount.ts:123-126`, address map `:134-189`). Dart supports three (`constants.dart:4-27`, address map `:70-125`). For the three shared versions all addresses are byte-identical (verified: 0.2.4 logic `0xd3082872...`, factory `0x5de4839a...`, validator `0xd9AB5096...`; 0.3.1 logic `0xBAC849bB...`, factory `0xaac5D424...`, metaFactory `0xd703aaE7...`, validator `0x845ADb2C...`, WebAuthn `0x7ab16Ff3...`; 0.3.3 logic `0xd6CEDDe8...`, factory `0x2577507b...`, metaFactory `0xd703aaE7...`, validator `0x845ADb2C...`). Missing versions also imply the 0.3.0-beta 4-arg initialize path is absent (see D4). Additionally Dart's 0.3.3 entry declares a `webAuthnValidator` (`constants.dart:120-122`) that JS deliberately omits for 0.3.2/0.3.3 (`toKernelSmartAccount.ts:177-188`) — see O1.

## M2 — Missing `useMetaFactory: false | "optional"` support

JS: `toKernelSmartAccount.ts:404-410` (direct `KernelV3FactoryAbi.createAccount(bytes,bytes32)`, selector `0xea6d13ac`, when `useMetaFactory === false`) and `:659-691` (the `"optional"` probe: try meta factory, fall back to direct factory if `getSenderAddress` returns the zero address). Dart always routes v0.3.x deployment through the meta factory (`kernel_account.dart:353-379`) and returns `metaFactory` as the factory address. The `createAccountV3` selector is declared in `constants.dart:147` but never used.

## M3 — Missing custom `nonceKey` parameter

JS: `parameters.nonceKey` feeds `getNonceKeyWithEncoding` (`toKernelSmartAccount.ts:848-858`; `utils/getNonceKey.ts:6-34`) — for v2 the key passes through unchanged; for v3 it occupies the trailing 2 bytes of the 24-byte key (throws above `maxUint16`). Dart hardcodes the 2-byte salt to zero (`kernel_account.dart:136-161`) and returns `BigInt.zero` for v2 (`:144`); there is no config field. The structural encoding (mode `0x00` ‖ type ROOT `0x00` ‖ validator ‖ salt) otherwise mirrors JS exactly, including using the WebAuthn validator address when the owner is WebAuthn.

## M4 — Missing unpatched-kernel migration logic in `encodeCalls`

JS `encodeCalls` (`toKernelSmartAccount.ts:746-844`) detects accounts still rooted on the vulnerable WebAuthn validator `0xbA45a2BFb8De3D24cA9D7F1B551E14dFF5d690Fd` (`:725-726`, on-chain `rootValidator()` check against `0x017ab16ff...` at `:693-723`) and rewrites the batch into a `migrateWithCall` through `MIGRATION_HELPER_ADDRESS = 0x03EB97959433D55748839D27C93330Cb85F31A93` (`:128-129`), using a delegatecall-mode 7579 execute for v0.3.1+ (`:812-828`) or an install/migrate/uninstall sandwich for 0.3.0-beta (`:830-841`). Dart `encodeCall`/`encodeCalls` (`kernel_account.dart:462-495`) has none of this. Impact is limited because Dart never configures the vulnerable validator (its WebAuthn validator constant is the patched `0x7ab16Ff3...`), but accounts created elsewhere with the old validator cannot be migrated via the Dart SDK.

## M5 — Missing `decodeCalls`

JS exposes `decodeCalls` on the account (`toKernelSmartAccount.ts:845-847`, `utils/decodeCallData.ts` — v2 via `KernelExecuteAbi` decode, v3 via `decode7579Calls`). The Dart `SmartAccount` interface has no decode method for Kernel; a generic `decode7579Calls` exists in `lib/src/utils/erc7579.dart:756-833` but is not wired to the account and there is no v2 decoder.

## M6 (trivial) — Missing `toEcdsaKernelSmartAccount` deprecated alias

JS keeps a deprecated wrapper mapping `ecdsaValidatorAddress` → `validatorAddress` (`toEcdsaKernelSmartAccount.ts:42-62`). Dart has no equivalent; not behaviorally significant since `createKernelSmartAccount` covers it via `customAddresses`.

## O1 (dart-only) — WebAuthn owners permitted on Kernel v0.3.3

Dart's address map gives v0.3.3 a `webAuthnValidator` (`constants.dart:120-122`), so a WebAuthn owner on v0.3.3 resolves a validator and proceeds. In JS, `getDefaultAddresses` (`toKernelSmartAccount.ts:238-245`) would find `WEB_AUTHN_VALIDATOR` undefined for 0.3.2/0.3.3 and `toKernelSmartAccount` throws `"Validator address is required"` (`:609-611`). Whether the 0x7ab16... validator is actually deployed/registered for 0.3.3 accounts is unverified — treat as intentional extension, but flag for review.

## O2 (dart-only) — Dynamic RIP-7212 precompile detection

`kernel_account.dart:543-548` probes the chain (`isRip7212Supported`) or falls back to a static chain list to set `usePrecompiled` in WebAuthn signatures. JS always uses `false`. Covered under D5 for byte-level impact.

## O3 (dart-only) — Structural differences with equivalent behavior

- `signUserOperationV06` (`kernel_account.dart:604-647`) provides correct EP v0.6 packing/hashing for v0.2.4; JS achieves the same through viem's `getUserOperationHash` with `entryPointVersion: "0.6"`. Hash pre-images verified equivalent (v0.6 10-field pack, v0.7 packed-gas pack, both `keccak256(abi.encode(hash, entryPoint, chainId))`).
- The 7702 variant is a separate class (`eip7702_kernel_account.dart:197`) rather than a flag on the main factory; behavior mirrors `toKernelSmartAccount` with `eip7702: true` / `to7702KernelSmartAccount.ts:42-63`: address = EOA (`:258` vs JS `:649`), factory args null (`:264-271` vs JS `:650-655`), authorization to the 0.3.3 account logic (`:280-285` vs JS `:737-742`), ECDSA dummy stub (`:311` vs JS `:885`), EIP-191-wrapped userOp signing (`:329-337` vs JS `:973-975`), Kernel-domain typed-data 1271 signing with single-byte `0x00` EIP7702 identifier prefix (`:479-510` vs JS `signMessage.ts:86-98` + `toKernelSmartAccount.ts:914-917` where `getEcdsaRootIdentifierForKernelV3(v, true)` = `0x00`). One caveat: the pre-delegation 1271 guard (`:463-474`) only fires when a `publicClient` is supplied; JS always checks `isDeployed()` (`toKernelSmartAccount.ts:891-899`).
