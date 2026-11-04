# JS 0.5.2 gap: permissionless.dart vs permissionless.js

**Date:** 2026-11-04
**Tags compared:** `permissionless@0.5.1` → `permissionless@0.5.2`
**JS package:** `permissionless.js/packages/permissionless/`
**Dart package:** `permissionless.dart/packages/permissionless/` (current main, read from the `chore-dep-bump-followups` worktree)
**Diff command:** `git -C permissionless.js diff permissionless@0.5.1 permissionless@0.5.2 -- packages/permissionless`

5 files changed. One is behavioral at the API surface (`clients/decorators/pimlico.ts`). One is a type-parameter pass-through (`clients/pimlico/index.ts`). One is a test, and two are packaging.

Commits in range: `50bf751` (feat: add `sendUserOperationSync` to `pimlicoActions`), `e55dbff` (format), `6ef1f4b` (Version Packages).

## Bottom line

0.5.2 adds no new RPC call and no new logic. It makes the 0.5.1 standalone action `sendUserOperationSync(client, args)` callable as a method, `client.sendUserOperationSync(args)`, on any client extended with `pimlicoActions`. That covers a smart account client after `.extend(pimlicoActions({ entryPoint }))` and every `createPimlicoClient` result. The decorated method forwards to the standalone action with the same client and the same args. Nothing is injected from the decorator config.

Dart has no `sendUserOperationSync` at all. A grep for `sendUserOperationSync`, `SendUserOperationSync` and `pimlico_sendUserOperationNow` under `lib/` and `test/` returns nothing. So the 0.5.2 gap cannot be closed until the 0.5.1 action is ported.

**Status:** closed by `PimlicoActions.sendUserOperationSync` (`lib/src/actions/pimlico/send_user_operation_sync.dart`), shipped with the shared `getUserOperationHash` util and `BundlerHttpError`. The plan below is kept as the design record.

**Behavioral Dart gaps from 0.5.2: 1.** `sendUserOperationSync` must be callable as a method on `SmartAccountClient`. This depends on the 0.5.1 port. If the 0.5.1 port is written as an extension method on `SmartAccountClient`, as recommended below, that one change closes both releases and 0.5.2 adds only a test.

## `sendUserOperationSync` on `pimlicoActions`

### JS 0.5.1

The action existed only as a standalone function, exported from `permissionless/actions/pimlico` (`actions/pimlico/index.ts:23-29`):

```ts
// actions/pimlico/sendUserOperationSync.ts:123-130
export async function sendUserOperationSync<
    const calls extends readonly unknown[],
    account extends SmartAccount | undefined,
    accountOverride extends SmartAccount | undefined = undefined
>(
    client: Client<Transport, Chain | undefined, account>,
    parameters: SendUserOperationSyncParameters<account, accountOverride, calls>
): Promise<SendUserOperationSyncReturnType>
```

Callers wrote `sendUserOperationSync(smartAccountClient, { calls })`. `PimlicoActions` had no such member. The decorator's client parameter was `Client<TTransport, TChain>`, so the account type was not threaded through.

### JS 0.5.2

`clients/decorators/pimlico.ts` changes in three places:

1. `PimlicoActions` gains a third type parameter, `account extends SmartAccount | undefined = SmartAccount | undefined` (`:38-42`).
2. A new member (`:140-145`):
   ```ts
   sendUserOperationSync: <
       const calls extends readonly unknown[],
       accountOverride extends SmartAccount | undefined = undefined
   >(
       args: SendUserOperationSyncParameters<account, accountOverride, calls>
   ) => Promise<SendUserOperationSyncReturnType>
   ```
3. The decorator's inner function gains `TAccount`, takes `client: Client<TTransport, TChain, TAccount>`, returns `PimlicoActions<TChain, entryPointVersion, TAccount>` (`:187-193`), and implements the member as a plain forward (`:203-204`):
   ```ts
   sendUserOperationSync: async (args) =>
       sendUserOperationSync(client, args),
   ```

`clients/pimlico/index.ts:43-45` passes `account` into `PimlicoActions<chain, entryPointVersion, account>`, so `PimlicoClient` gets the member with the right account typing.

New test (`actions/pimlico/sendUserOperationSync.test.ts:45-69`, run for EntryPoint 0.7 and 0.8): build a smart account client, `.extend(pimlicoActions({ entryPoint: bundlerClient.account.entryPoint }))`, call `sendUserOperationSync({ calls: [{ to: zeroAddress, data: "0x", value: 0n }] })`, and assert `receipt.success === true` and `receipt.sender === account.address`.

### What `pimlicoActions` decoration means in JS

- `pimlicoActions({ entryPoint })` is a curried viem decorator. Its result goes to `client.extend(...)`, which calls it with the current client and merges the returned methods into that client. Each method closes over the client as it was at extend time.
- Clients it extends:
  - Every `createPimlicoClient` result, automatically (`clients/pimlico/index.ts:135-150`: `.extend(bundlerActions).extend(paymasterActions).extend(pimlicoActions({ entryPoint }))`, where `entryPoint` defaults to v0.7).
  - Any client the user extends by hand. In the 0.5.2 docs and test, that is a smart account client. `createSmartAccountClient` does **not** apply it by default; it applies only `bundlerActions` and `smartAccountActions` (`clients/createSmartAccountClient.ts:191-215`).
- Account binding: the method calls `sendUserOperationSync(client, args)` and the action reads `parameters.account ?? client.account` (`sendUserOperationSync.ts:131-139`). On a smart account client the account comes from the client. On a `PimlicoClient` with no account, the caller passes `account` in args.
- Preparation binding: the action prepares through `getAction(client, prepareUserOperation, "prepareUserOperation")` (`:143-147`). On an extended smart account client that resolves to the client's own `prepareUserOperation`, so its `paymaster`, `paymasterContext`, `userOperation.estimateFeesPerGas` and any custom `userOperation.prepareUserOperation` all apply. On a bare `PimlicoClient` you get plain `bundlerActions.prepareUserOperation` with no paymaster.
- EntryPoint: unlike its siblings (`sendCompressedUserOperation`, `sponsorUserOperation`, `validateSponsorshipPolicies`, `getTokenQuotes`, `estimateErc20PaymasterCost`, `:198-226`), this member does **not** inject the decorator's `entryPoint`. The action uses `parameters.entryPointAddress ?? account.entryPoint.address` (`sendUserOperationSync.ts:140-141`). The `entryPoint` passed to `pimlicoActions(...)` has no effect on this call.
- Type constraints: `account` comes from the client's `TAccount`. `SendUserOperationParameters` builds on `GetSmartAccountParameter<account, accountOverride, false>` (`viem/src/account-abstraction/actions/bundler/sendUserOperation.ts:50`; `types/account.ts:9-21`). The `false` makes `account` optional at the type level in every case, so a missing account is caught only at runtime (`AccountNotFoundError`, `sendUserOperationSync.ts:138`). `const calls` keeps the call tuple literal for typed `calls`. `accountOverride` defaults to `undefined`, so by default the client's account type is used. Extra params are `timeout` and `pollingInterval` (`:28-44`).
- Net effect: `client.sendUserOperationSync(args)` and `sendUserOperationSync(client, args)` behave the same. 0.5.2 only changes how the action is reached.

### Dart today

Dart has no client decoration. Pimlico methods are exposed in three ways:

1. **Methods on a subclass.** `class PimlicoClient extends BundlerClient` (`lib/src/clients/pimlico/pimlico_client.dart:35`) holds the `pimlico_*` methods: `getUserOperationStatus` (`:58`), `getUserOperationGasPrice` (`:75`), `sendCompressedUserOperation` (`:100`), `getTokenQuotes` (`:166`), `estimateErc20PaymasterCost` (`:245`), `validateSponsorshipPolicies` (`:323`). `createPimlicoClient` builds it (`:356-371`). `PimlicoClient` holds an `entryPoint` (`bundler_client.dart:49`) and an `rpcClient` (`:46`), but no account, public client or paymaster.
2. **Composition into `SmartAccountClient`.** `SmartAccountClient` (`lib/src/clients/smart_account/smart_account_client.dart:70`) takes `bundler` typed as plain `BundlerClient` (`:109`; ctor `:84-92`; `createSmartAccountClient` `:961-963`). The README passes a `PimlicoClient` as the bundler (`README.md:111-126`). Pimlico methods are **not** reachable from the smart account client. Users hold the `pimlico` reference or cast `client.bundler as PimlicoClient`.
3. **Extension methods on `SmartAccountClient`.** These are the Dart analog of `client.extend(decorator)`: `extension SmartAccountActions on SmartAccountClient` (`lib/src/actions/smart_account/smart_account_actions.dart:33`, the JS `smartAccountActions` port) and `extension Erc7579Actions on SmartAccountClient` (`lib/src/actions/erc7579/erc7579_actions.dart:29`). Both are exported from the barrel (`lib/permissionless.dart:37-38`). There is no Pimlico extension.

How actions that JS exposes both standalone and on `pimlicoActions` map in Dart:

| JS standalone | JS `pimlicoActions` member | Dart |
|---|---|---|
| `getUserOperationGasPrice` (`actions/pimlico/getUserOperationGasPrice.ts:40`) | `decorators/pimlico.ts:194` | `PimlicoClient.getUserOperationGasPrice()` (`pimlico_client.dart:75`). No standalone function. Reaches a `SmartAccountClient` only indirectly, through the `estimateFeesPerGas` hook with `estimateFeesFromPimlico(pimlico)` (`lib/src/utils/gas.dart:305-321`). |
| `estimateErc20PaymasterCost` (`actions/pimlico/estimateErc20PaymasterCost.ts:44`) | `decorators/pimlico.ts:221-226` (injects `entryPoint`) | `PimlicoClient.estimateErc20PaymasterCost(userOperation:, token:)` (`pimlico_client.dart:245-289`). The entry point comes from the client field, matching the decorator's injection. |
| `sponsorUserOperation` (`actions/pimlico/sponsorUserOperation.ts:77`) | `decorators/pimlico.ts:205-209` (injects `entryPoint`) | `PaymasterClient.sponsorUserOperation` (`lib/src/clients/paymaster/paymaster_client.dart:134-146`). This is a different class, as the earlier audit noted (`docs/parity-audit/04a-clients-pimlico-etherspot.md:35`). |
| `sendUserOperationSync` (0.5.1, `actions/pimlico/sendUserOperationSync.ts:123`) | `decorators/pimlico.ts:203-204` (0.5.2, no injection) | **Missing.** |

(`sendCompliantUserOperation` does not exist in JS 0.5.2. The only "Compliant" hits in the JS package are `isEip7702Compliant` test fixtures.)

So Dart maps a JS `pimlicoActions` member to an instance method on `PimlicoClient` whenever the action needs only bundler RPC plus an entry point. When an action needs the account, signing, paymaster or fee hooks (`prepareUserOperationForErc20Paymaster`, `lib/src/experimental/pimlico/erc20_paymaster.dart:125-135`), Dart takes `SmartAccountClient` and `PimlicoClient` as separate arguments.

`sendUserOperationSync` is in the second group. It prepares the op (with paymaster, fees, nonce and 7702 authorization), signs it, hashes it, calls `pimlico_sendUserOperationNow`, then polls `eth_getUserOperationReceipt`. A Dart `PimlicoClient` cannot prepare or sign. `SmartAccountClient` can: `prepareUserOperationWithAuth` (`smart_account_client.dart:278`), `signUserOperation` (`:486`), and its `bundler` exposes `rpcClient`, `getUserOperationReceipt` (`bundler_client.dart:178`) and `chainId` (`:198`). The account exposes `entryPoint` and `chainId` (`smart_account_interface.dart:111-114`).

### Where a Dart `sendUserOperationSync` must be reachable

To match 0.5.2 (`smartAccountClient.sendUserOperationSync({ calls })`), it must be an instance-call on `SmartAccountClient`:

```dart
final receipt = await smartAccountClient.sendUserOperationSync(
  calls: [Call(to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'), data: '0x')],
);
```

Recommended shape: a new `extension PimlicoSmartAccountActions on SmartAccountClient` in `lib/src/actions/pimlico/` (mirrors JS `actions/pimlico/`), exported from `lib/permissionless.dart` next to `:37-38`. This follows the existing `SmartAccountActions` and `Erc7579Actions` pattern. A Dart extension member works as both forms JS has: `client.sendUserOperationSync(...)` is the decorated call, and `PimlicoSmartAccountActions(client).sendUserOperationSync(...)` is the explicit standalone call. One implementation covers 0.5.1 and 0.5.2.

Notes for that port. Behavior belongs to the 0.5.1 audit; these are listed only so the 0.5.2 shape does not block it:
- Do not require `bundler is PimlicoClient`. The JS action works on any client at runtime, and a plain `BundlerClient` pointed at a Pimlico URL can call `pimlico_sendUserOperationNow` through `bundler.rpcClient`. If the team wants a type-level "only when Pimlico" signal, put the raw RPC primitive on `PimlicoClient` and have the extension delegate when the bundler is one. That is a style choice, not a parity requirement.
- The `PimlicoClient` + `account` path that JS 0.5.2 also enables (`pimlicoClient.sendUserOperationSync({ account, calls })`) has no separate Dart target. A Dart user with an account always has a `SmartAccountClient`, and `PimlicoClient` has no paymaster or public client to prepare with. Do not add a `PimlicoClient.sendUserOperationSync({account, ...})`.
- Ignore any decorator-level entry point. Use `account.entryPoint` (with an optional override), as JS does at `sendUserOperationSync.ts:140-141`. Do not use `bundler.entryPoint`, even though they normally match.
- The 7702 authorization must go into the `pimlico_sendUserOperationNow` userOp JSON the same way `BundlerClient.sendUserOperationWithAuthorization` does it (`bundler_client.dart:76-93`: inject `eip7702Auth`, normalize the `0x7702` factory marker). JS gets this through `formatUserOperationRequest`.
- Dart `JsonRpcClient.call` has no retry layer (`rpc_client.dart:43-62`), so JS `{ retryCount: 0 }` holds without extra work.
- Timeout default: JS uses `client.transport.timeout ?? 10_000`. Dart's closest value is `bundler.rpcClient.timeout`, which `createPimlicoClient` sets to 30 s (`pimlico_client.dart:368`). The 0.5.1 port should pick a default and document it.
- The return type exists already: `UserOperationReceipt` with `sender` and `success` (`lib/src/clients/bundler/types.dart:108-156`), so the 0.5.2 test translates directly.

### Verdict

Gap. Dart cannot call `sendUserOperationSync` on a smart account client, because the action does not exist in Dart yet. The 0.5.2 part of the gap is reachability only. It is closed by porting 0.5.1 as an extension on `SmartAccountClient`. If 0.5.1 is ported as a top-level function or as a `PimlicoClient` method that takes a signed op, 0.5.2 still needs a thin `SmartAccountClient` extension member that forwards to it.

## Other files in the 0.5.1 → 0.5.2 diff

| File | Change | Classification |
|---|---|---|
| `packages/permissionless/clients/pimlico/index.ts` | `PimlicoActions<chain, entryPointVersion>` → `PimlicoActions<chain, entryPointVersion, account>` (`:45`) | Types only; makes `PimlicoClient` carry the new member with account typing. No Dart analog (no generics on `PimlicoClient`). |
| `packages/permissionless/actions/pimlico/sendUserOperationSync.test.ts` | New "returns the receipt through pimlicoActions" case (`:45-69`), plus import of `pimlicoActions` | Test. Dart should add the matching test with the port (receipt `success` + `sender`), on the local Alto rig for EP 0.7 and 0.8. |
| `packages/permissionless/CHANGELOG.md` | 0.5.2 patch note | n/a (docs) |
| `packages/permissionless/package.json` | `"version": "0.5.1"` → `"0.5.2"` | n/a (version bump) |

`6ef1f4b` (Version Packages) expanded the `package.json` `keywords` array onto separate lines, and `e55dbff` (chore: format) collapsed it back onto one line, so the net change is the version bump only. `50bf751` also added a `.changeset/pimlico-actions-send-user-operation-sync.md` outside the package. The release step consumed it into `CHANGELOG.md`.

## Dart work required

One item, blocked on the 0.5.1 port:

- Make `sendUserOperationSync` callable as `smartAccountClient.sendUserOperationSync(calls: ..., ...)`, returning `UserOperationReceipt`. Implement it as an `extension` on `SmartAccountClient` under `lib/src/actions/pimlico/`, export it from `lib/permissionless.dart`, and port the 0.5.2 test (EP 0.7 and 0.8, assert `success` and `sender`). If the 0.5.1 port already lands as that extension, the only 0.5.2 work left is the test.

Not required: a `pimlicoActions`-style decorator, generics on `PimlicoClient`, or a `PimlicoClient.sendUserOperationSync` that takes an account.
