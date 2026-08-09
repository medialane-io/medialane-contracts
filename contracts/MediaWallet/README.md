# Media Wallet — Cairo Account Contract

Self-sovereign Starknet smart account. Open source, GPL-3.0.

## What this is

A minimal, audited Starknet account contract for the Media Wallet.
Forked from Argent's argent-contracts-starknet (ChainSecurity audit, April 2025, v0.5.0).

## Features

- Single Stark curve owner — the only signing authority
- Outside execution (SNIP-9 V2) — gasless, paymaster-compatible
- Owner-upgradeable — user controls their own contract upgrades via `replace_class`

Two further capabilities are present in the contract and become available once the owner
designates a guardian through `change_guardians`:

- Guardian recovery — user-designated, fully on-chain, no Medialane service required.
  A wallet deploys with no guardian, so the escape flow stays inert until one is added.
- Session keys — let dapps transact within user-defined scope without exposing the owner key.
  Session authorization is co-signed by a guardian, so a guardian is a prerequisite.

## Build

```sh
scarb build
```

## Test

```sh
snforge test
```

## Deploy

A wallet deploys itself with a standard Starknet `DEPLOY_ACCOUNT` transaction — the account
validates its own deployment through `__validate_deploy__`. Constructor calldata is the owner
signer followed by the guardian option:

```
[0x0, owner_pubkey, 0x1]   // Signer::Starknet(owner), Option::None
```

The address is the standard derivation over `(salt, class_hash, constructor_calldata)` with
deployer address `0`, so it is known before deployment: fund it first, then send the
`DEPLOY_ACCOUNT` transaction from the account itself. `@medialane/sdk` exposes this as
`computeAccountAddress(owner_pubkey, salt)` and `buildDeployAccountParams`.

## Audit

- Fork baseline: `argentlabs/argent-contracts-starknet`
- Audited commit: `6243bcf39fac0df25cff183056a9bc8f1e15ef28` (see `FORK.md`)
- Audit: ChainSecurity, April 2025, v0.5.0

Delta from baseline: see `AUDIT.md`

## License

GPL-3.0
