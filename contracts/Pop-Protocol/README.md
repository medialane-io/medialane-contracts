# Pop Protocol

Soulbound proof-of-participation credentials on Starknet.

- `POPFactory` — anyone calls `create_collection(name, symbol, base_uri, claim_end_time)`; the caller becomes the collection's organizer. The factory has no owner and cannot be upgraded.
- `POPCollection` — one per event. Non-transferable ERC-721 (ERC-5192 `locked`); only the holder can `burn` their own token.
  - `set_allowlist_root(root)` — the organizer publishes a Poseidon Merkle root of eligible addresses (`0` closes claims).
  - `claim(proof)` — a listed address mints one token before `claim_end_time` (`0` = no deadline).
  - `issue(recipient, token_uri)` — the organizer mints directly; an empty `token_uri` uses the collection URI.
  - `burn(token_id)` — the holder destroys their own token. The address cannot receive another from this collection.
  - One token per address. Metadata is fixed at deployment: `token_uri` returns the token's own URI if it was issued with one, otherwise `base_uri`.

Merkle leaves are `poseidon([poseidon([address])])`, nodes are the Poseidon hash of the sorted pair, and proofs are verified with OpenZeppelin `merkle_proof::verify_poseidon`.

## Deployments

| Network | Item | Address / class hash |
|---|---|---|
| Mainnet | `POPFactory` | _pending_ |
| Mainnet | `POPCollection` class | _pending_ |

## Build & Test

Toolchain: see `.tool-versions` (Scarb 2.18.0, Starknet Foundry 0.59.0).

```bash
scarb build
snforge test
```
