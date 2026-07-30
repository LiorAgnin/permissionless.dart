# permissionless

Dart ERC-4337 smart-account SDK: accounts, UserOperations, clients, and
encoding utilities for account abstraction.

## Language

### EntryPoint and UserOperations

**EntryPoint**:
The singleton ERC-4337 contract that validates and executes UserOperations.
_Avoid_: bundler, paymaster

**EntryPoint version**:
A published EntryPoint contract generation (v0.6, v0.7, v0.8, v0.9) with its
own canonical address and UserOperation layout rules.
_Avoid_: “latest EntryPoint” without a version

**UserOperation**:
The ERC-4337 operation a smart account submits through a bundler to an
EntryPoint.
_Avoid_: transaction, call (a single target invocation inside a UserOperation)

**Packed UserOperation**:
The EntryPoint v0.7+ field layout that packs gas and paymaster data into fewer
slots than v0.6.
_Avoid_: “v0.9 UserOperation” as a separate shape when fields match the packed
era

**userOpHash**:
The digest the account signs for a UserOperation under a given EntryPoint
version and chain.
_Avoid_: transaction hash; the bundler’s submitted UserOperation hash (a
different identifier)

**Paymaster signature**:
Optional paymaster-authored bytes on EntryPoint v0.9 that let the user and
paymaster sign concurrently.
_Avoid_: account signature; paymaster data (sponsorship payload without the
parallel-sign artifact)

### Kernel v4

**Kernel v4**:
ZeroDev’s Kernel line that targets EntryPoint v0.9 and uses nonce-encoded
validation with ERC-7579-style modules.
_Avoid_: Kernel v0.3.x; “Kernel” alone when the major line matters

**UUPS (KernelUUPS)**:
The upgradeable Kernel v4 proxy variant.
_Avoid_: ImmutableECDSA; Kernel7702

**ImmutableECDSA**:
The Kernel v4 variant with an immutable fallback ECDSA signer set at
deployment.
_Avoid_: UUPS; Kernel7702

**Kernel7702**:
The Kernel v4 implementation used as an EIP-7702 delegation target so an EOA
gains modular Kernel features without a separate factory-deployed proxy.
_Avoid_: UUPS; ImmutableECDSA

**Validation mode**:
How Kernel v4 selects standard vs enable behavior and chain-bound vs
replayable hashing for a UserOperation.
_Avoid_: validation type

**Validation type**:
Which kind of entity authorizes the UserOperation: root/fallback, validator,
or permission.
_Avoid_: validation mode; module type

**Validation id**:
The identity of the non-root authorizing entity (a validator or a
PermissionId).
_Avoid_: nonce key; sequence

**PermissionId**:
The identity of a Kernel v4 permission composed of policies plus one signer.
_Avoid_: session key; validator id

**Enable mode**:
A validation mode that installs modules atomically with the first validation
of a UserOperation.
_Avoid_: a separate module-install UserOperation without enable framing

**Install package**:
A single module-install unit (type, module, module data, internal data) used
at account initialize, batch install, and enable mode.
_Avoid_: “module” alone when the full install unit is meant

**Permission**:
A Kernel v4 authorization path under a PermissionId: policies plus a signer
that validate together.
_Avoid_: validator; owner

### Shared account vocabulary

**Smart account**:
A contract account that validates UserOperations (and often ERC-1271
signatures) per its implementation rules.
_Avoid_: wallet; account abstraction (the broader design space)

**Account owner**:
The local signing principal the SDK uses to produce signatures for a smart
account (EOA key, passkey, etc.).
_Avoid_: validator; signer module

**Bundler**:
An ERC-4337 RPC service that accepts UserOperations and submits them to the
EntryPoint.
_Avoid_: EntryPoint; paymaster

**Paymaster**:
A contract or service that sponsors gas for a UserOperation under EntryPoint
rules.
_Avoid_: bundler; paymaster signature
