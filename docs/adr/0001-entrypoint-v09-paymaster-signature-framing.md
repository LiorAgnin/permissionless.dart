# ADR 0001 — EntryPoint v0.9 paymaster signature framing

- **Status:** accepted
- **Date:** 2026-07-25
- **Scope:** `getUserOperationHash`, `getPaymasterAndData`,
  `UserOperationV07.paymasterSignature`

This ADR records the framing question ticket 01 was required to resolve
against contract truth. The broader "why the Kernel v4 contracts, not
permissionless.js, are the parity baseline" decision is
[ADR 0002](./0002-kernel-v4-parity-baseline.md).

## Context

EntryPoint v0.9 lets a paymaster attach its own signature to a UserOperation.
The point is that the user and the paymaster can sign **concurrently**: the
user should not have to wait for the paymaster's signature before producing
their own.

Two questions had to be settled before any Dart code was written:

1. How is the paymaster signature framed inside `paymasterAndData`?
2. What exactly does the userOpHash cover?

The workspace's vendored `viem/` source checkout appends the paymaster
signature raw, with no length prefix and no magic marker, and hashes the
result verbatim. That contradicts the pinned Solidity. Ticket 01 mandated that
contract truth wins on any divergence.

## Decision

Follow the contracts. Concretely, from
`account-abstraction` `contracts/core/UserOperationLib.sol` and `Helpers.sol`:

**Wire format** — `UserOperationLib.encodePaymasterSignature`:

```
paymasterAndData = paymaster(20) ‖ verificationGasLimit(16) ‖ postOpGasLimit(16)
                 ‖ paymasterData
                 ‖ paymasterSignature ‖ uint16(len) ‖ 0x22e325a297439656
```

The magic is `keccak256("PaymasterSignature")[:8]`.

**Hash format** — `paymasterDataKeccak` substitutes, in place of the blob
above:

```
prefix ‖ 0x22e325a297439656          // prefix = everything before the suffix
```

A suffix is only recognised when the blob is at least 62 bytes, ends with the
magic, and declares a **non-zero** length. Otherwise the blob is hashed
verbatim.

Three consequences follow, and all three are load-bearing:

1. The userOpHash is **invariant to the signature's bytes and its length**. A
   65-byte and a 3-byte paymaster signature over the same operation produce an
   identical userOpHash. This is what makes parallel signing sound.
2. The userOpHash is **not** invariant to whether a suffix exists. Adding the
   magic changes the digest, so a signer must know that a paymaster signature
   is coming, even though it need not know what it will be.
3. A zero-length declaration means "no signature", and the trailing bytes are
   then hashed as ordinary data.

### API shape

`UserOperationV07` carries an optional `paymasterSignature`. Per the spec, no
`UserOperationV09` subclass is introduced — `PackedUserOperation` is
byte-identical across v0.7, v0.8, and v0.9.

| Value | Meaning |
|---|---|
| `null` | No suffix; `paymasterAndData` hashed verbatim |
| non-empty hex | Suffix emitted; digest covers `prefix ‖ magic` |
| `'0x'` | **Rejected** with `ArgumentError` |

`'0x'` is rejected rather than given a meaning. Consequence 3 makes it
genuinely ambiguous: a caller writing `'0x'` almost certainly means "a
signature is coming, I don't have it yet", but the contract would read the
result as "no signature" and compute a different hash than the one the user
signed. Failing loudly beats producing an operation that reverts on-chain.

For the "signature not known yet" case, `paymasterSignatureStub` is a 65-byte
ECDSA-shaped placeholder. Being realistically sized also keeps
calldata-derived gas estimation honest; by consequence 1, swapping in the real
signature afterwards leaves the userOpHash — and so the user's signature —
valid.

Setting `paymasterSignature` on a v0.6/v0.7/v0.8 operation throws rather than
being silently ignored, so a field that is wider than any single EntryPoint
version cannot cause a quiet wrong hash.

## On viem

The divergence turned out to be **stale, not real**. The vendored `viem/`
source checkout in this workspace predates the fix; the published
**viem 2.44.4** implements exactly the contract framing, via a `forHash`
option on `toPackedUserOperation` that selects `prefix ‖ magic` for hashing
and the full suffix for the wire.

So contract truth and current viem agree, and this implementation matches
both. Both were used as independent oracles while building this: the Solidity
oracle (`tool/entry_point_v09_vectors/`) and viem 2.44.4 produce identical
userOpHashes for every non-suffix case, and the Solidity oracle alone covers
the suffix cases.

One deliberate difference from viem remains: viem treats a truthy
`paymasterSignature` as a suffix, and `'0x'` is truthy in JavaScript, so viem
will emit a `0x0000 ‖ magic` suffix that the EntryPoint then reads as
no-signature-plus-data. This implementation rejects that input instead.

## Consequences

- Accounts do not implement v0.9 packing themselves; they call the shared
  `getUserOperationHash`.
- The golden vectors are generated from the pinned contracts and committed, so
  `dart test` needs no Foundry. Regenerate with
  `tool/entry_point_v09_vectors/generate.sh`.
- If a future EntryPoint changes the framing, the fixture regenerates and the
  diff will show every affected hash.

## References

- `account-abstraction/contracts/core/UserOperationLib.sol` —
  `PAYMASTER_SIG_MAGIC`, `getPaymasterSignatureLength`,
  `encodePaymasterSignature`
- `account-abstraction/contracts/core/Helpers.sol` — `paymasterDataKeccak`
- `tool/entry_point_v09_vectors/README.md`
