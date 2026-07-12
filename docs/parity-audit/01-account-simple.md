# Parity Audit 01 — Simple Smart Account (incl. EIP-7702 variant)

**Reference:** permissionless.js v0.3.5 — `accounts/simple/toSimpleSmartAccount.ts`, `accounts/simple/to7702SimpleSmartAccount.ts`
**Port:** permissionless.dart v0.3.0 — `lib/src/accounts/simple/simple_account.dart`, `eip7702_simple_account.dart`, `constants.dart`, `simple.dart`

Paths below are abbreviated:

- `JS` = `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless/accounts/simple/toSimpleSmartAccount.ts`
- `JS-7702` = `.../accounts/simple/to7702SimpleSmartAccount.ts`
- `DART` = `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/lib/src/accounts/simple/simple_account.dart`
- `DART-7702` = `.../lib/src/accounts/simple/eip7702_simple_account.dart`
- `DART-CONST` = `.../lib/src/accounts/simple/constants.dart`
- `VIEM` = `/Users/liorag/Documents/development/permissionless/viem/src/account-abstraction/` (permissionless.js delegates hashing/typed-data to viem)
- `DART-CLIENT` = `.../lib/src/clients/smart_account/smart_account_client.dart` (cited where account-level signing behavior depends on what the client feeds it)

The JS account is a single implementation parameterized by EP version + `eip7702` flag; the Dart port splits it into `SimpleSmartAccount` (v0.6/v0.7/v0.8 selectable) and `Eip7702SimpleSmartAccount` (v0.8 only). Behavior was compared byte-for-byte for constants, calldata, and signed payloads. Selectors independently verified via viem `toFunctionSelector`: `execute(address,uint256,bytes)` = `0xb61d27f6`, `executeBatch(address[],uint256[],bytes[])` = `0x47e1da2a`, `executeBatch(address[],bytes[])` = `0x18dfb3c7`, `executeBatch((address,uint256,bytes)[])` = `0x34fcd5be`, `createAccount(address,uint256)` = `0x5fbfb9cf`.

## Verdict table

| # | Aspect | Verdict | JS | Dart |
|---|--------|---------|----|------|
| 1 | Factory address v0.6 `0x9406Cc6185a346906296840746125a0E44976454` | mirrors | JS:127 | DART-CONST:12-13 |
| 2 | Factory address v0.7 `0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985` | mirrors | JS:125 | DART-CONST:16-17 |
| 3 | Factory address v0.8 `0x13E9ed32155810FDbd067D4522C492D6f68E5944` | mirrors | JS:123 | DART-CONST:20-21 |
| 4 | Custom factory override | mirrors | JS:119 | DART:85-88 |
| 5 | factoryData = `createAccount(owner, salt)` (`0x5fbfb9cf`), salt/index default 0 | mirrors | JS:37-73, 186 | DART:210-214, 31; DART-CONST:62 |
| 6 | Default EP version (v0.7 non-7702, v0.8 for 7702); EP addresses | mirrors | JS:198-218; VIEM constants/address.ts:1-6 | DART:26; DART-7702:198-206; `constants/entry_point.dart:14-28` |
| 7 | Sender address via EP `getSenderAddress` simulation; explicit `address` override | mirrors | JS:257-269 | DART:123-149 |
| 8 | Dummy/stub signature (`0xfff...aaa1c`, both variants) | mirrors | JS:430-432 | DART:322-325; DART-7702:366-367 |
| 9 | `execute` single-call calldata (`0xb61d27f6`, all EP versions) | mirrors | JS:334-339, 481-505 | DART:239-252; DART-7702:280-292 |
| 10 | `executeBatch` v0.7 calldata (`0x47e1da2a`, 3 parallel arrays) | mirrors | JS:306-315, 528-552 | DART:255-315 |
| 11 | `executeBatch` v0.6 calldata | **diverges** | JS:318-325, 507-526 | DART:225-236 |
| 12 | `executeBatch` v0.8 calldata — non-7702 account | **diverges** | JS:291-304, 554-585 | DART:225-236 |
| 13 | `executeBatch` v0.8 calldata — 7702 variant (`0x34fcd5be`, `Call[]` tuple array) | mirrors | JS:291-304, 554-585 | DART-7702:266-362; DART-CONST:59 |
| 14 | `signUserOperation` v0.7 (EIP-191 personal-sign of packed v0.7 userOpHash) | mirrors | JS:460-477; VIEM getUserOperationHash.ts:90-124 | DART:331-334, 355-425; `accounts/account_owner.dart:116-129` |
| 15 | `signUserOperation` v0.6 (v0.6 hash format) | **missing** | JS:460-477; VIEM getUserOperationHash.ts:54-88 | DART:331-334 (v0.7 format only) |
| 16 | `signUserOperation` v0.8 — non-7702 account (EIP-712 typed data) | **diverges** | JS:446-457 | DART:331-334 |
| 17 | `signUserOperation` v0.8 — 7702 variant: typed-data domain/types/message shape | mirrors | JS:447-457; VIEM getUserOperationTypedData.ts:18-48 | DART-7702:373-377, 431-513 |
| 18 | 7702 typed-data `initCode` value pre-delegation | **diverges** | JS:246-251; VIEM getInitCode.ts:10-21 | DART-7702:464-472; DART-CLIENT:236-239 |
| 19 | `signMessage` / `signTypedData` — non-7702 (ERC-1271) | **diverges** | JS:433-441 | DART:340-350 |
| 20 | `signMessage` / `signTypedData` — 7702 variant | **dart-only** | JS:436-441 (throws) | DART-7702:393-425 |
| 21 | `decodeCalls` | **missing** | JS:341-422 | — |
| 22 | `nonceKey` parameter | **missing** | JS:189, 423-429 | DART:113-114 (fixed `0`) |
| 23 | 7702: account address = owner EOA; no factory/initCode | mirrors | JS:188, 243-252 | DART-7702:219-233 |
| 24 | 7702: delegation target default `0xe6Cae83BdE06E4c305530e199D7217f42808555B`; override param | mirrors | JS:190, 281-286 | DART-CONST:41-42; DART-7702:131-133 |
| 25 | 7702: authorization construction (EIP-7702 auth over `accountLogicAddress`) | mirrors | JS:281-286 (viem signs `keccak256(0x05‖rlp([chainId,addr,nonce]))`) | DART-7702:248-253; `types/eip7702.dart:97-140` |
| 26 | Empty-calls error | mirrors | JS:328-332 | DART:226-228; DART-7702:267-269 |

**Counts: 15 mirrors · 5 diverges · 3 missing · 1 dart-only** (rows 11/12 and 15/16 are distinct behavioral defects even though they share a root cause: the Dart account is version-configurable but hardcodes v0.7 behavior).

---

## Finding 11 — diverges: v0.6 `executeBatch` uses the wrong function signature

JS selects `executeBatch(address[] dest, bytes[] func)` (selector `0x18dfb3c7`) for EP v0.6, because the v0.6 SimpleAccount contract has no `value` array:

- `JS:318-325` — falls through to `executeBatch06Abi` when version is neither 0.8 nor 0.7
- `JS:507-526` — `executeBatch06Abi`: two params, `address[]` + `bytes[]`

Dart `SimpleSmartAccount.encodeCalls` unconditionally encodes the three-array v0.7 form `executeBatch(address[],uint256[],bytes[])` (`0x47e1da2a`) regardless of `entryPointVersion`:

- `DART:225-236` — `encodeCalls` always calls `_encodeExecuteBatch`
- `DART:255-280` — `_encodeExecuteBatch` emits `SimpleAccountSelectors.executeBatch` (`0x47e1da2a`, DART-CONST:55) with dest/values/func arrays

A `SimpleSmartAccount` configured with `EntryPointVersion.v06` (allowed by `DART:26` + factory constant `DART-CONST:12-13`) produces batch calldata for a function that does not exist on the v0.6 SimpleAccount contract. Dart has no `0x18dfb3c7` selector anywhere in the simple/ directory.

## Finding 12 — diverges: v0.8 `executeBatch` on the non-7702 account uses the v0.7 array form

JS uses the tuple-array form `executeBatch((address,uint256,bytes)[])` (`0x34fcd5be`) whenever `entryPoint.version === "0.8"`, for both plain and 7702 accounts:

- `JS:291-304` — v0.8 branch using `executeBatch08Abi`
- `JS:554-585` — `executeBatch08Abi` (`struct BaseAccount.Call[]`)

Dart implements the tuple encoding only in the 7702 class (`DART-7702:298-362`, selector `DART-CONST:59` — verified `0x34fcd5be`, byte-layout of the manual tuple-array encoding checked and correct). The plain `SimpleSmartAccount`, which accepts `EntryPointVersion.v08` (`DART-CONST:24-29`), still emits the three-array v0.7 form (`DART:225-236`). Batch calldata from a Dart v0.8 non-7702 Simple account therefore does not match JS (and would not decode on the v0.8 SimpleAccount contract).

## Finding 15 — missing: v0.6 userOpHash / signing path

JS computes the version-correct hash via viem (`VIEM utils/userOperation/getUserOperationHash.ts:54-88` — v0.6 packs `callGasLimit`, `verificationGasLimit`, `maxFeePerGas`, `maxPriorityFeePerGas` as separate uint256 fields) and signs it (`JS:460-477`).

Dart `SimpleSmartAccount.signUserOperation` accepts only `UserOperationV07` and always packs the v0.7 format (`DART:331-334`, `_packUserOpForHash` at `DART:370-425`: `accountGasLimits`/`gasFees` as packed bytes32). There is no v0.6 hash path. Additionally, the class implements `SmartAccount` but not `SmartAccountV06` (`clients/smart_account/smart_account_interface.dart:120-129`), and the v0.6 client flow does `account as SmartAccountV06` (`DART-CLIENT:549` region, `signUserOperationV06`), so a v0.6-configured Simple account cannot be driven through the v0.6 pipeline at all — v0.6 support is config-visible (factory constant, enum) but non-functional. JS fully supports v0.6.

## Finding 16 — diverges: v0.8 non-7702 signing uses raw-hash personal-sign instead of EIP-712 typed data

JS switches to EIP-712 typed-data signing for any account whose EP version is 0.8 — including a plain (non-7702) v0.8 Simple account:

- `JS:446-457` — `if (entryPoint.version === "0.8") { ... getUserOperationTypedData ... localOwner.signTypedData(typedData) }`

Dart implements typed-data signing only in `Eip7702SimpleSmartAccount` (`DART-7702:373-377`). The plain `SimpleSmartAccount` with `entryPointVersion: v08` falls into the personal-sign-of-v0.7-hash path (`DART:331-334`), producing a signature over the wrong payload for EP v0.8. (The v0.7 path itself mirrors: EIP-191 prefix applied by `PrivateKeyOwner.signPersonalMessage`, `accounts/account_owner.dart:116-129`, matching JS `signMessage(client, { message: { raw: hash } })` at `JS:460-476`; the Dart hand-rolled v0.7 hash at `DART:355-425` matches viem's `getUserOperationHash.ts:90-124` field-for-field.)

## Finding 18 — diverges: 7702 signed `initCode` differs pre-delegation

Both sides agree on the v0.8 typed-data envelope (domain `{name: 'ERC4337', version: '1', chainId, verifyingContract: entryPoint}` and the 8-field `PackedUserOperation` type — `VIEM getUserOperationTypedData.ts:18-48` vs `DART-7702:476-512`), and both pack `accountGasLimits`/`gasFees`/`paymasterAndData` identically. The divergence is the `initCode` message field for the *first* (delegating) UserOperation:

- JS: the permissionless.js 7702 account returns `factory: undefined, factoryData: undefined` (`JS:243-252`), so viem's `getInitCode` yields `'0x'` (`VIEM utils/userOperation/getInitCode.ts:19`). The signed `initCode` is `0x` both pre- and post-delegation. (Note: viem's own `toSimple7702SmartAccount` instead uses factory `'0x7702'`, which `getInitCode.ts:11-17` expands to the delegation address when an authorization is attached — permissionless.js deliberately differs from viem here; the Dart port matches neither.)
- Dart: the client marks pending delegation with factory = `0x7702000000000000000000000000000000000000` and factoryData `'0x'` (`DART-CLIENT:236-239`, marker defined at `DART-CLIENT:130-131`), and `_getUserOperationTypedData` naively concatenates `factory‖factoryData` whenever `factory != null` (`DART-7702:464-472`). The signed `initCode` is therefore the 20-byte `0x7702…0000` marker pre-delegation.

Result: for the first 7702 UserOperation, the EIP-712 digest signed by Dart is byte-for-byte different from what JS signs for the same operation. Post-delegation (factory null) both sign `initCode = 0x` and mirror. Note EntryPoint v0.8 substitutes the account's actual delegate address into the hash when the `0x7702…` marker is used, so the two libraries cannot both be producing on-chain-valid first-op signatures — this row is flagged on JS-vs-Dart bytes; on-chain validity should be settled by the live-test follow-up.

## Finding 19 — diverges: non-7702 `signMessage`/`signTypedData` sign instead of throwing

JS deliberately rejects ERC-1271 flows because SimpleAccount (v0.6/v0.7) does not implement `isValidSignature`:

- `JS:436-441` — both `signMessage` and `signTypedData` throw `"Simple account isn't 1271 compliant"`; `sign({hash})` (`JS:433-435`) routes into the same throw.

Dart `SimpleSmartAccount` happily produces owner-EOA signatures:

- `DART:340-343` — `signMessage` returns `owner.signPersonalMessage(hashMessage(message))`
- `DART:349-350` — `signTypedData` returns `owner.signTypedData(typedData)`

These signatures are EOA signatures that no contract will validate for the smart-account address — JS's throw is the safer, reference behavior.

## Finding 20 — dart-only: 7702 `signMessage`/`signTypedData` with delegation guard

JS throws for `signMessage`/`signTypedData` even in 7702 mode (same implementation object, `JS:436-441`; `JS-7702:47-50` merely forwards to `toSimpleSmartAccount` with `eip7702: true`). Dart's 7702 variant implements them: it checks the EOA has been delegated (has code) via `_ensureDeployedForEip1271` and then signs with the owner key (`DART-7702:393-425`). Since the `Simple7702Account` implementation contract is ERC-1271-capable, this is a functional extension rather than a bug, but it is behavior the reference does not have.

## Finding 21 — missing: `decodeCalls`

JS implements `decodeCalls` for all three EP versions (tuple array for 0.8, three arrays for 0.7, two arrays with `value: 0n` for 0.6, single-`execute` fallback) at `JS:341-422`. Neither Dart class has any decode capability (`DART`, `DART-7702` — no counterpart; `SmartAccount` interface has none). API-surface gap, no wire impact.

## Finding 22 — missing: `nonceKey` parameter

JS accepts a `nonceKey` construction parameter used in `getNonce` (`JS:189`, `JS:423-429`, `nonceKey ?? args?.key`). Dart hardcodes `nonceKey => BigInt.zero` with no config field (`DART:113-114`; `SimpleSmartAccountConfig` at `DART:16-59` has no such option). Parallel-nonce (2D nonce) usage is not reachable for Dart Simple accounts.
