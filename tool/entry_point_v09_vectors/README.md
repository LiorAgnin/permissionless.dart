# EntryPoint v0.9 hash vectors

Regenerates
`packages/permissionless/test/fixtures/entry_point_v09_vectors.json` — the
golden vectors for `getUserOperationHash` and paymaster-signature packing on
EntryPoint v0.9.

The oracle is the **Solidity contract**, not another SDK. `src/Oracle.sol` is a
thin external wrapper over `UserOperationLib` from eth-infinitism's
`account-abstraction` checkout, so the fixture cannot drift from the semantics
the EntryPoint actually enforces. See
[ADR 0001 - EntryPoint v0.9 paymaster signature framing](../docs/adr/0001-entrypoint-v09-paymaster-signature-framing.md)
for the framing rules and how they were resolved.

## Regenerating

Foundry only — the Dart test suite consumes the committed JSON and never shells
out to `forge`.

```bash
./generate.sh
```

The script looks for a sibling `account-abstraction/` checkout by walking up
from this directory. Override the location explicitly:

```bash
AA_DIR=/path/to/account-abstraction ./generate.sh
```

`generate.sh` symlinks that checkout to `./aa` (gitignored) so Foundry can
resolve the `@aa/` remapping without depending on the repo's nesting depth.

Commit the regenerated JSON. Review the diff: a change in any existing hash
means either the pinned contracts moved or a vector definition changed, and
both are worth a second look.

## What is covered

`cases[]` — vectors expressed as unpacked v0.9 UserOperation fields, so the
Dart side exercises its own packing and is compared on `initCode`,
`paymasterAndData`, the EIP-712 struct hash, and the final userOpHash:

| Case | Covers |
|---|---|
| `base` | No factory, no paymaster |
| `factory` | `factory ‖ factoryData` initCode |
| `eip7702` / `eip7702NoPayload` | `0x7702` marker initCode with the delegate-address hash override |
| `paymaster` / `paymasterEmptyData` | Packed paymaster fields, no signature |
| `paymasterSig65` / `paymasterSig3` | Paymaster signature suffix. **Both must produce the same userOpHash** — the hash covers neither the signature bytes nor its length, which is what allows the user and the paymaster to sign in parallel |
| `paymasterSigNoData` | Suffix with empty `paymasterData` |
| `factoryAndPaymasterSig` | Both extension paths at once |

`rawPaymasterAndData[]` — blobs the unpacked model cannot express, pinning the
suffix-detection boundaries in `getPaymasterSignatureLength`:

| Case | Covers |
|---|---|
| `magicBelowMinimumLength` | Ends with the magic but is under the 62-byte floor, so the magic is data |
| `magicAtMinimumLength` | Exactly at the floor |
| `magicWithZeroDeclaredLength` | Well-formed suffix declaring length 0 — reported as "no signature" and hashed verbatim, magic included |
| `noMagic` | Trailing 8 bytes that are not the magic |
