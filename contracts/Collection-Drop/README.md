# Collection Drop

Timed NFT drops on Starknet.

- `DropFactory` — anyone calls `create_drop(name, symbol, base_uri, max_supply, terms, allowlist_root)`; the caller becomes the drop's organizer. The factory has no owner and cannot be upgraded.
- `DropCollection` — one per drop. A standard, transferable ERC-721.
  - **Sale terms are fixed at creation:** `start_time` / `end_time` (0 = no bound), `price` and `payment_token` (both zero for a free drop), `max_per_wallet` (0 = unlimited) and `max_supply` (0 = open edition).
  - `claim(quantity, proof)` — mints to the caller and transfers `price × quantity` from the caller **directly to the organizer**. The contract never holds funds.
  - `set_allowlist_root(root)` — organizer only. With a root set, only wallets in the Poseidon Merkle tree can claim; `0` opens the drop to everyone.
  - `issue(recipient, quantity)` — organizer only; free mints within `max_supply`.
  - `token_uri(id)` is `base_uri` followed by the token id, fixed at creation.

Merkle leaves are `poseidon([poseidon([address])])`, nodes are the Poseidon hash of the sorted pair, verified with OpenZeppelin `merkle_proof::verify_poseidon`.

## Deployments

| Network | Item | Address / class hash |
|---|---|---|
| Mainnet | `DropFactory` | _pending_ |
| Mainnet | `DropCollection` class | _pending_ |

## Build & Test

Toolchain: see `.tool-versions` (Scarb 2.18.0, Starknet Foundry 0.59.0).

```bash
scarb build
snforge test
```
