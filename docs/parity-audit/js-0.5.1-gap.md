# JS 0.5.1 gap: permissionless.dart vs permissionless.js

**Date:** 2026-11-04
**Tags compared:** `permissionless@0.5.0` → `permissionless@0.5.1`
**JS package:** `permissionless.js/packages/permissionless/`
**Dart package:** `permissionless.dart/packages/permissionless/` (read at worktree `chore-dep-bump-followups`, which tracks current main)
**Diff command:** `git -C permissionless.js diff permissionless@0.5.0 permissionless@0.5.1 -- packages/permissionless`

6 files changed in `packages/permissionless` (+495 / -2). One is behavioral (`actions/pimlico/sendUserOperationSync.ts`, new). Two are API surface (`actions/pimlico/index.ts` exports, `types/pimlico.ts` RPC schema). One is a test. The rest are packaging. Outside the package, the same range touches the JS test rig (`permissionless-test/src/testWithRpc.ts`, `mock-aa-infra/alto/{index,instance}.ts`) and `bun.lock`.

Intermediate commits, in order: `d4dc348` adds the action. `0ef0938` changes the default `timeout` from `10_000` to `client.transport.timeout ?? 10_000` and drains the anvil txpool in the rig. `5f783fc` makes `timeout` a single deadline over send + polling, and adds `throwOnReceiptRevert` plus an `execution_reverted` kind. `acafca5` removes both again and renames `reverted` to `bundlerError`. `e3d419f` renames `bundlerError` to `bundle_reverted` and passes the bundler's message through. This report describes the net 0.5.1 state. **`throwOnReceiptRevert` and `execution_reverted` are not in 0.5.1.** A receipt with `success: false` is returned, not thrown.

## Bottom line

Dart has no `pimlico_sendUserOperationNow` call, no prepare + sign + send-now flow, and no equivalent of `SendUserOperationSyncError`. The pieces it would be built from already exist: `SmartAccountClient.prepareUserOperationWithAuth`, `signUserOperation`, `BundlerClient.getUserOperationReceipt`, `UserOperationReceipt.fromJson` and `BundlerRpcError`. Two supporting pieces are missing. Dart has no shared `getUserOperationHash` util, and JS computes the hash client-side before sending. Dart's JSON-RPC client also turns HTTP failures into `BundlerRpcError`, which would push them into the wrong error kind.

**Status:** closed by `PimlicoActions.sendUserOperationSync` (`lib/src/actions/pimlico/send_user_operation_sync.dart`), shipped with the shared `getUserOperationHash` util and `BundlerHttpError`. The plan below is kept as the design record.

**Behavioral Dart gaps from 0.5.1: 1.** (`sendUserOperationSync` with its RPC call and error type. New, opt-in API. No existing Dart behavior diverges.)

## `sendUserOperationSync` (new Pimlico action)

Changelog wording: *"Added `sendUserOperationSync` to `permissionless/actions/pimlico`. It prepares, signs and sends a user operation with `pimlico_sendUserOperationNow` and returns its receipt. If the outcome is unclear it polls for the receipt, and otherwise throws a `SendUserOperationSyncError` whose `kind` and `canResend` say what happened and whether resending is safe."*

### JS 0.5.0

Not present. The only way to get a receipt was `sendUserOperation` (`eth_sendUserOperation`, mempool) followed by `waitForUserOperationReceipt`.

### JS 0.5.1 (`actions/pimlico/sendUserOperationSync.ts`)

It is a standalone action, `sendUserOperationSync(client, parameters)`. It is exported from `permissionless/actions/pimlico` (`actions/pimlico/index.ts:23-29`) and is **not** added to the `pimlicoActions` client decorator. New exports: `sendUserOperationSync`, `SendUserOperationSyncError` (class), and the types `SendUserOperationSyncParameters`, `SendUserOperationSyncReturnType` and `SendUserOperationSyncErrorKind`.

**Parameters.** All of viem's `SendUserOperationParameters` (`calls` / `callData`, gas and fee fields, `nonce`, `paymaster*`, `signature`, `entryPointAddress`, `account`, `authorization`, …), plus:

| Param | Default | Meaning |
|---|---|---|
| `timeout` (ms) | `client.transport.timeout ?? 10_000` (`:133`). viem `http()` defaults to `10_000`. | One deadline covering the bundler call **and** any receipt polling. The clock starts after prepare + sign + hash (`:165`), so preparation time does not count. |
| `pollingInterval` (ms) | `client.pollingInterval` (`:134`). The viem default is `min(max(blockTime/2, 500), 4000)`, which is 4000 with no chain `blockTime`. | Sleep between `eth_getUserOperationReceipt` polls. |

**Flow.**

1. Resolve the account (`AccountNotFoundError` if none). Then `entryPointAddress = parameters.entryPointAddress ?? account.entryPoint.address`.
2. Prepare with the client's own `prepareUserOperation` (`getAction(client, prepareUserOperation, "prepareUserOperation")`, `:143-147`). Client middleware runs here (paymaster, `userOperation.estimateFeesPerGas`), and EIP-7702 `authorization` is attached if the account needs it.
3. Sign: `parameters.signature || account.signUserOperation(request)` (`:150-154`).
4. Hash locally: `getUserOperationHash({ chainId: client.chain?.id ?? getChainId(), entryPointAddress, entryPointVersion: account.entryPoint.version, userOperation })` (`:156-163`). The error and the polling loop both need this hash, including when the send itself fails.
5. `deadline = now + timeout`. Every await after this point is raced against the deadline (`beforeDeadline`, `:167-179`).
6. Send `pimlico_sendUserOperationNow` with params `[formatUserOperationRequest(userOperation), entryPointAddress]` and `{ retryCount: 0 }`, so the transport never retries (`:200-217`). Request shape: the standard RPC user operation (hex quantities, `eip7702Auth` when an authorization is present) plus the EntryPoint address. Response: an RPC `UserOperationReceipt`, formatted with `formatUserOperationReceipt` into viem's `UserOperationReceipt` (`:224-226`).
7. Classify failures (decision tree below). For "outcome unclear", poll `getUserOperationReceipt({ hash })` until the deadline (`:181-198`). Any poll error, including viem's `UserOperationReceiptNotFoundError`, counts as "not yet" (`.catch(() => null)`). Each poll and each sleep is also deadline-bounded. **The action never resends.**

**Schema change (`types/pimlico.ts:70-74`).**

```ts
{
    Method: "pimlico_sendUserOperationNow"
    Parameters: [userOperation: RpcUserOperation, entryPoint: Address]
    ReturnType: RpcUserOperationReceipt
}
```

**Return type.** `SendUserOperationSyncReturnType = UserOperationReceipt` (viem's, unchanged). No new receipt type. A receipt with `success: false` (execution reverted inside the account, nonce consumed) is **returned**, not thrown. The JS test `returns the receipt when the call reverts` asserts this.

### Decision tree (net 0.5.1, `:219-275`)

`rpcError` is the first `RpcRequestError` found by walking the thrown error's cause chain. `data` is `rpcError.data` read as `{ transactionHash?: Hash }`.

1. The send did not settle before the deadline → throw **`pending`** immediately, with no cause and no polling (the deadline has already passed).
2. The send returned a result → return `formatUserOperationReceipt(result)`.
3. `rpcError.code === -32521` → throw **`bundle_reverted`**, with `cause` set to the error and `message: rpcError.details`. `details` is viem's copy of the bundler's JSON-RPC `error.message`, so the error's `shortMessage` is the bundler's text, for example `"bundle transaction 0xabc reverted onchain"`. If `details` is empty, the default message is used (`message_ || message`, `:88`).
4. `rpcError` exists, `data.transactionHash` is absent, and `code !== -32603` → throw **`rejected`**. Its cause is `getUserOperationError(error, { ...userOperation, calls })`, viem's mapping of AA codes and bundler errors to typed errors. This covers the ERC-7769 validation codes (-32602, -32500, -32501, …) when no tx hash is present.
5. Anything else falls through to polling. That means: an `rpcError` with `data.transactionHash` (for example -32602 "submitted but not yet included"), -32603 internal error, or an error with no `RpcRequestError` in its chain (viem `HttpRequestError` from a non-2xx response, network failure, transport `TimeoutError`). A receipt found before the deadline is returned. Otherwise it throws **`not_found`** if `rpcError.code === -32603` and there is no `transactionHash`, and **`pending`** in every other case, with the original error as `cause`.

### `SendUserOperationSyncError` (`:61-97`)

`class SendUserOperationSyncError extends BaseError`, `name: "SendUserOperationSyncError"`. Fields: `kind: SendUserOperationSyncErrorKind`, `userOperationHash: Hash`, `canResend: boolean`. `metaMessages: ["User operation hash: <hash>"]`. The constructor takes `{ cause?, kind, message?, userOperationHash }`. `message` overrides the default per-kind text. `canResend = kind === "bundle_reverted" || kind === "not_found"`.

| `kind` | When it fires | `canResend` | Default message |
|---|---|---|---|
| `rejected` | JSON-RPC error, code ≠ -32521 and ≠ -32603, no `data.transactionHash`. The bundler refused it before sending (fields, gas limits, simulation, bad nonce). | `false` | "User operation was rejected by the bundler." |
| `bundle_reverted` | JSON-RPC error code -32521. The bundle tx landed and reverted, so the op did not execute. The doc comment says another bundler may have included it first, so check `getUserOperationReceipt` before resending. | `true` | "Bundle transaction reverted onchain. The user operation was not executed." Overridden by the bundler's `error.message` when non-empty. |
| `pending` | Send timed out at the deadline (no polling), **or** polled to the deadline without a receipt after any error other than "-32603 with no tx hash". | `false` | "User operation may have been sent but is not included yet. Poll `getUserOperationReceipt` instead of resending." |
| `not_found` | JSON-RPC -32603 with no `data.transactionHash`, then polled to the deadline without a receipt. | `true` | "Bundler couldn't send the user operation and no receipt was found." |

`rejected` has `canResend: false` even though nothing was sent. Resending the same op would be rejected again, so "safe to resend" means the same op could succeed if sent again, not only that a resend would do no harm.

### Dart today

Nothing in `lib/` or `test/` mentions `sendUserOperationNow`, `SendUserOperationSync`, or `instant bundling`.

Reusable pieces:

| Need | Dart piece | Notes |
|---|---|---|
| Prepare (paymaster, gas, fees, 7702 auth) | `SmartAccountClient.prepareUserOperationWithAuth` (`lib/src/clients/smart_account/smart_account_client.dart:278-450`) | Returns `PreparedUserOperation {userOp, authorization}` (`:18-35`). Like viem, it skips estimation when all three gas limits are given (`:400-402`). The JS tests depend on that. |
| Sign, honoring a caller-supplied signature | `SmartAccountClient.sendUserOperation` pattern (`:552-591`, esp. `:586-590`) and `signUserOperation` (`:486-489`) | Same `signature ?? sign()` rule as JS `:150-154`. |
| v0.6 path | `prepareUserOperationV06` / `signUserOperationV06` (`:666`, `:761`) | Dart keeps v0.6 as a separate method family. |
| RPC transport | `SmartAccountClient.bundler.rpcClient` → `JsonRpcClient.call` (`lib/src/clients/bundler/rpc_client.dart:43-84`) | No retries, so `retryCount: 0` holds already. Per-request `.timeout(timeout)` (`:62`) throws `TimeoutException`. |
| Default timeout | `JsonRpcClient.timeout` (`rpc_client.dart:24,34`). It defaults to 30 s in `createBundlerClient` / `createPimlicoClient` (`bundler_client.dart:261`, `pimlico_client.dart:368`). | This is the Dart analog of `client.transport.timeout`. Note 30 s vs JS's 10 s. |
| 7702 request JSON | `BundlerClient.sendUserOperationWithAuthorization` (`bundler_client.dart:76-93`) plus private `_normalizeEip7702Factory` (`:152-157`) | The `eip7702Auth` injection and the `0x7702` factory marker rewrite are inline and private. The new RPC needs the same JSON. |
| Receipt poll | `BundlerClient.getUserOperationReceipt` (`bundler_client.dart:178-187`) returns `null` when not found | Unlike viem it does not throw on "not found", but a poll must still swallow `BundlerRpcError` / `TimeoutException`. `waitForUserOperationReceipt` (`:215-234`) is not reusable as-is. Its loop is not deadline-bounded per call and throws `TimeoutException`. |
| Receipt type | `UserOperationReceipt.fromJson` (`lib/src/clients/bundler/types.dart:108-144`) | Same RPC shape Alto returns from `parseUserOpReceipt`. |
| RPC error | `BundlerRpcError {code, message, data}` (`types.dart:293-372`) with `aaErrorCode` / `aaErrorDescription` | `data` is `dynamic`, so `data['transactionHash']` is readable. It is a good `cause` for `rejected`, standing in for viem's `getUserOperationError`. |
| Error base | `PermissionlessException(message, [cause])` (`lib/src/errors/errors.dart:2-15`) | Fits `SendUserOperationSyncError`. |
| Extension pattern | `extension SmartAccountActions on SmartAccountClient` (`lib/src/actions/smart_account/smart_account_actions.dart:33`), `Erc7579Actions` (`lib/src/actions/erc7579/erc7579_actions.dart:29`) | Natural home for a JS standalone action that takes a smart account client. |

Missing pieces:

1. **The RPC call.** No `pimlico_sendUserOperationNow` anywhere. `PimlicoClient` (`lib/src/clients/pimlico/pimlico_client.dart:35-345`) has `getUserOperationStatus`, gas price, compressed send, token quotes and sponsorship, but no send-now.
2. **The orchestration.** Nothing prepares, signs, hashes, sends to send-now, and polls against one deadline.
3. **The error type.** No `SendUserOperationSyncError`, no kind enum, no `canResend`.
4. **A shared `getUserOperationHash`.** Hashing is private to each account: `_computeUserOpHashV07` / `V06` in `simple_account.dart:479,555`, and the same pattern in `biconomy`, `kernel`, `nexus`, `trust`, `light`, `thirdweb`. v0.8 typed-data hashing is in `simple_account.dart` and `eip7702_simple_account.dart:404,451`. `02-userop-encoding.md` row 19 already records this ("duplicated per-account, no shared util"). `SmartAccount` (`smart_account_interface.dart:20-130`) exposes `entryPoint` and `chainId` but not the EntryPoint version or a hash method. The building blocks for a shared util exist: `packUserOperationInitCode` with `delegationAddress` for 7702 (`lib/src/utils/packed_user_operation.dart:127-135`), `hashTypedData`, `EntryPointAddresses` (`lib/src/constants/entry_point.dart`).
5. **HTTP errors vs JSON-RPC errors.** `JsonRpcClient.call` throws `BundlerRpcError(code: <HTTP status>, message: 'HTTP error: …')` on any non-200 response (`rpc_client.dart:64-70`). A literal port of step 4 of the decision tree would classify an HTTP 502 as **`rejected` / `canResend: false`**, which is the wrong answer: the op may have been sent. viem raises `HttpRequestError`, which is not an `RpcRequestError`, so JS polls and ends in `pending`. Dart needs a way to tell the two apart.

### Verdict

Gap. Dart has no equivalent of the 0.5.1 action, its RPC method, or its error type. This is additive: no existing Dart API is wrong, and parity means adding a new opt-in path.

## Other files in the 0.5.0 → 0.5.1 diff

| File | Change | Classification |
|---|---|---|
| `packages/permissionless/actions/pimlico/index.ts` | Exports `sendUserOperationSync`, `SendUserOperationSyncError`, and types `SendUserOperationSyncErrorKind` / `Parameters` / `ReturnType` | API surface |
| `packages/permissionless/types/pimlico.ts` | Adds `pimlico_sendUserOperationNow` to `PimlicoRpcSchema` (`[RpcUserOperation, Address] → RpcUserOperationReceipt`) and imports `RpcUserOperation` / `RpcUserOperationReceipt` | API surface (types only) |
| `packages/permissionless/actions/pimlico/sendUserOperationSync.test.ts` | New. For EP 0.7 and 0.8 against live Alto: happy path, `rejected` on nonce 5 with estimation skipped, reverting call returns `success: false`, `pending` with `timeout: 1`. With a `custom` transport that throws a chosen `RpcRequestError` for send-now and forwards everything else to Alto: -32521 → `bundle_reverted` (checks `shortMessage` equals the bundler message), -32602 + `transactionHash` → `pending`, -32603 → `not_found` | Test |
| `packages/permissionless/CHANGELOG.md` | 0.5.1 patch note | n/a (docs) |
| `packages/permissionless/package.json` | `0.5.0` → `0.5.1` | n/a (version bump) |
| `packages/permissionless-test/mock-aa-infra/alto/instance.ts` (outside package) | New `enableInstantBundlingEndpoint` option for the Alto launcher | Test rig |
| `packages/permissionless-test/src/testWithRpc.ts` (outside package) | Starts Alto with `enableInstantBundlingEndpoint: true`. Adds `drainTxpool`, which mines until anvil's txpool is empty before handing out the rig, because anvil ≥ 1.8 mines one block per burst and leaves the rest pending, and send-now does not mine | Test rig |
| `packages/permissionless-test/mock-aa-infra/alto/index.ts` (outside package) | Same drain loop after contract deploys in `setupContracts` | Test rig |
| `bun.lock` (repo root) | Lockfile churn | n/a |

## Dart work required

Port `sendUserOperationSync` as an extension on `SmartAccountClient`, in the style of `SmartAccountActions` / `Erc7579Actions`.

### API

New file `lib/src/actions/pimlico/pimlico_actions.dart` (plus `pimlico.dart` barrel), exported from `lib/permissionless.dart` next to `src/actions/erc7579/erc7579.dart`:

```dart
enum SendUserOperationSyncErrorKind {
  rejected('rejected'),
  bundleReverted('bundle_reverted'),
  pending('pending'),
  notFound('not_found');

  const SendUserOperationSyncErrorKind(this.value);
  final String value; // JS wire name
}

class SendUserOperationSyncError extends PermissionlessException {
  SendUserOperationSyncError({
    required this.kind,
    required this.userOperationHash,
    String? message, // bundler's message for bundleReverted
    Object? cause,
  }) : super(
          (message == null || message.isEmpty) ? _defaults[kind]! : message,
          cause,
        );

  final SendUserOperationSyncErrorKind kind;
  final String userOperationHash;

  bool get canResend =>
      kind == SendUserOperationSyncErrorKind.bundleReverted ||
      kind == SendUserOperationSyncErrorKind.notFound;
  // _defaults: the four JS default messages verbatim.
  // toString includes 'User operation hash: <hash>' (JS metaMessages).
}

extension PimlicoActions on SmartAccountClient {
  Future<UserOperationReceipt> sendUserOperationSync({
    List<Call>? calls,
    String? callData,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? nonce,
    BigInt? callGasLimit,
    BigInt? verificationGasLimit,
    BigInt? preVerificationGas,
    String? signature,
    EthereumAddress? factory,
    String? factoryData,
    PaymasterContext? paymasterContext,
    EthereumAddress? sender,
    List<StateOverride>? stateOverride,
    EthereumAddress? entryPointAddress, // default account.entryPoint
    Duration? timeout,                  // default bundler.rpcClient.timeout
    Duration pollingInterval = const Duration(seconds: 2),
  });
}
```

`pollingInterval` defaults to 2 s, which matches Dart's existing `waitForReceipt` default (`smart_account_client.dart:644-645`). Dart clients carry no `pollingInterval`, so there is no direct analog of viem's `client.pollingInterval`. Optionally add a raw `PimlicoClient.sendUserOperationNow(UserOperation, {Eip7702Authorization? authorization}) → Future<UserOperationReceipt>` for callers that sign themselves. JS has no such action (only the schema entry), so it is optional. The extension does not need it, because it calls through `bundler.rpcClient`, which, as in JS, works against any bundler that serves the method, Alto included.

### Implementation steps

1. **Shared hash util** (prerequisite, also closes `02-userop-encoding.md` row 19). Add `lib/src/utils/user_operation_hash.dart`:
   `String getUserOperationHash({required UserOperation userOperation, required EthereumAddress entryPoint, required EntryPointVersion entryPointVersion, required BigInt chainId, EthereumAddress? eip7702Delegation})`.
   The v0.6 and v0.7 branches lift the existing `_computeUserOpHashV06` / `V07` code. The v0.8 branch lifts the typed-data hash from `eip7702_simple_account.dart:451+`, with initCode built by `packUserOperationInitCode(delegationAddress: …)`. Map `account.entryPoint` to a version by comparing against `EntryPointAddresses.v06/v07/v08`, and throw `ArgumentError` for unknown addresses. Gate it with the `verify-userop-hash-formal` skill: every account's private hash must equal the shared util over the seeded bound.
2. **Shared RPC JSON.** Make the `eip7702Auth` injection plus `0x7702` factory normalization in `bundler_client.dart:81-86,152-157` a package-internal helper (for example `userOperationToRpcJson(userOp, authorization)`) and use it from both `sendUserOperationWithAuthorization` and the new path.
3. **Tell HTTP errors apart from JSON-RPC errors.** Add `class BundlerHttpError extends BundlerRpcError` (keeps code = HTTP status) and throw it from `rpc_client.dart:64-70` and `:117-123`. Existing `on BundlerRpcError` catches still match, so this does not break callers. In the classifier, a `BundlerHttpError`, `TimeoutException`, `SocketException` / `http.ClientException`, or JSON decode error counts as "no JSON-RPC error", which leads to polling and then `pending`.
4. **The action.**
   - prepare (`prepareUserOperationWithAuth`)
   - sign unless `signature != null`
   - hash (step 1)
   - `deadline = DateTime.now().add(timeout ?? bundler.rpcClient.timeout)`
   - send with `bundler.rpcClient.call('pimlico_sendUserOperationNow', [json, ep.hex]).timeout(remaining)`
   - classify with a `switch` on the caught error: `TimeoutException` from the outer deadline → `pending` with no polling. `BundlerRpcError` with code -32521 → `bundleReverted(message: e.message)`. `BundlerRpcError` (not HTTP) with no `data['transactionHash']` and code ≠ -32603 → `rejected(cause: e)`. Otherwise poll.
   - poll: loop while before the deadline, each `getUserOperationReceipt` wrapped in `.timeout(remaining)` and `catchError → null`, sleeping `min(pollingInterval, remaining)`
   - after the deadline, throw `notFound` when the error was JSON-RPC -32603 with no tx hash, else `pending`.

   Treat a `null` send-now result (Alto's schema allows `receipt | null`) as "outcome unclear" and poll. JS would crash in `formatUserOperationReceipt(null)` with a raw `TypeError`, so polling is the better reading for Dart.
5. **v0.6.** JS's code path is version-agnostic (only 0.7 and 0.8 are tested). Ship v0.7/v0.8 first through `UserOperationV07`. Add `sendUserOperationSyncV06` later over `prepareUserOperationV06` if wanted.

Keep the JS semantics exactly: never resend; the deadline starts after prepare + sign; a receipt with `success == false` is returned, not thrown (no `throwOnReceiptRevert`, no `execution_reverted`); `rejected` keeps `canResend == false`.

### Test plan

- **Unit (`-P quick`)**, new `test/actions/pimlico/pimlico_actions_test.dart`, using `package:http/testing` `MockClient` the way `test/clients/pimlico/pimlico_client_test.dart:13-34` does. Script the full RPC sequence (nonce, fees, estimate skipped by passing all three gas limits, send-now, receipt polls) and assert:
  - receipt returned, including `success: false`
  - -32521 + message → `bundleReverted`, `canResend`, `message == bundler message`; empty message → default text
  - -32602 without tx hash → `rejected`, `!canResend`, `cause is BundlerRpcError` with `aaErrorCode` kept
  - -32602 with `data.transactionHash` → polls, then `pending`; same with a receipt appearing mid-poll → receipt returned
  - -32603 without tx hash → `notFound`; -32603 with tx hash → `pending`
  - HTTP 502 → polls, then `pending` (the Dart-specific regression guard)
  - send slower than `timeout` → `pending` with no receipt poll after the deadline
  - `userOperationHash` on the error equals the account's own hash for v0.7 and v0.8
- **Hash util**: golden vectors for v0.6/v0.7/v0.8/7702, plus a `verify-userop-hash-formal` run.
- **Local rig (Alto + anvil)**: this works with one change. The rig pins `@pimlico/alto` `0.0.21` (`.claude/skills/verify-permissionless/rig/package.json`), and that version ships `pimlico_sendUserOperationNow` (`rig/node_modules/@pimlico/alto/esm/rpc/methods/pimlico_sendUserOperationNow.js`). It is disabled unless Alto starts with `--enable-instant-bundling-endpoint true`. Without the flag it answers -32602 "endpoint is not enabled", which the action maps to `rejected`. Add the flag to `scripts/launch.sh:47-55`. Then mirror the four JS live tests (happy path, nonce 5 → `rejected`, reverting call → `success: false`, `timeout: 1ms` → `pending`) for EP 0.7 and 0.8 as a new drive mode or a new feature doc. Alto's handler waits on `waitForTransactionReceipt` and does not mine, so it depends on anvil automine. The local anvil is 1.5.1, where the JS rig's `drainTxpool` workaround for anvil ≥ 1.8 is not yet needed. Add the same drain loop to `launch.sh` before anvil is upgraded. `bundle_reverted` and -32602-with-tx-hash cannot be produced on demand by Alto. JS covers them with a mocked transport, and Dart's `MockClient` unit tests cover the same cases.
- **Live Pimlico (`integration`)**: optional single happy-path smoke test against a Pimlico endpoint if the hosted bundler serves send-now on a test chain. Not verified here.

### Size

About 250–350 lines of library code: error + enum ~70, extension ~150, hash util ~120 lifted from existing code, JSON helper and `BundlerHttpError` ~30. About 300–400 lines of tests. One flag line, plus an optional drain loop, in the rig launcher. Additive change, so a minor-version feature bump.
