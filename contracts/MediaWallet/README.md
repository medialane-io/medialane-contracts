# Media Wallet — Cairo Account Contract

Self-sovereign Starknet smart account. Open source, GPL-3.0.

## What this is

A minimal, audited Starknet account contract for the Media Wallet.
Forked from Argent's argent-contracts-starknet (ChainSecurity audit, April 2025, v0.5.0).

## Features

- Single Stark curve owner — the only signing authority
- Optional guardian recovery — user-designated, fully on-chain, no Medialane service required
- Session keys — let dapps transact within user-defined scope without exposing the owner key
- Outside execution (SNIP-9 V2) — gasless, paymaster-compatible
- Owner-upgradeable — user controls their own contract upgrades via `replace_class`

## Build

```sh
scarb build
```

## Test

```sh
snforge test
```

## Deploy

Use `MediaWalletFactory`. Deploy the factory with the `MediaWallet` class hash, then call `deploy_wallet(owner_pubkey, salt)`.

Predict a wallet address before deployment (counterfactual):

```sh
factory.compute_address(owner_pubkey, salt)
```

The wallet address is independent of the factory address — `deploy_from_zero: true`. Same owner pubkey and salt always produce the same address regardless of which factory deployed it.

## Audit

- Fork baseline: `argentlabs/argent-contracts-starknet`
- Audited commit: `6243bcf39fac0df25cff183056a9bc8f1e15ef28` (see `FORK.md`)
- Audit: ChainSecurity, April 2025, v0.5.0

Delta from baseline: see `AUDIT.md`

## License

GPL-3.0
