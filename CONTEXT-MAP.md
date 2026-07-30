# Context Map

This monorepo has one primary bounded context per package. System-wide
decisions live under [`docs/adr/`](docs/adr/).

## Contexts

- [permissionless](packages/permissionless/CONTEXT.md) — ERC-4337 smart
  accounts, UserOperations, bundler/paymaster clients, and shared encoding
  utilities
- [permissionless_passkeys](packages/permissionless_passkeys/) — WebAuthn /
  passkey owners and Flutter helpers that plug into `permissionless` accounts
  (no package glossary yet; terms for smart-account ownership live in
  `permissionless`)

## Relationships

- **permissionless_passkeys → permissionless**: passkey credentials surface as
  an `AccountOwner` (or equivalent owner) consumed by Kernel, Safe, and other
  accounts in the core package. Domain language for accounts, EntryPoints, and
  validation belongs to `permissionless`.
