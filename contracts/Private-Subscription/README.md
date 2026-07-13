# Private Subscription

A permissionless, ownerless, no-custody registry for **subscriber-private
recurring subscriptions** on Starknet. Creators publish public subscription
plans; subscribers hold their subscriptions as private commitments. The contract
never holds or moves funds — confidential payments settle subscriber → creator
inside a confidential-token pool, and the contract only *witnesses* them.

> ⚠️ **Reference build.** This class is a complete, tested reference
> implementation built against a mocked proof seam. Its `proof_verified()` gate
> is permissive (`is_reference_build()` returns `true`, `contract_version()`
> returns `'0.1.0-ref'`) pending confirmation of the confidential-token proof
> interface. **Not for mainnet** until the seam is wired to real proof
> verification and the contract is re-audited.

## Model

A subscription is a **note**: `commitment = Poseidon(subscriber_secret, plan_id,
expires_at, salt)`. Active commitments live in an append-only incremental
Poseidon Merkle tree; subscribing inserts a commitment, renewing spends the old
one (publishes its **nullifier**) and inserts a fresh one with extended expiry,
and cancelling publishes the nullifier without re-inserting. Every access-granting
call is gated by a confidential-payment proof whose public facts bind the payment
to `(plan_id, recipient, price, commitment, payment_nullifier)`. Access is proven
against a published Merkle root — on-chain via `verify_tier`, or off-chain by
reading `current_root` / `is_known_root`.

## Invariants

- **Ownerless & immutable** — no owner, admin, upgrade, pause, or fee.
- **No custody** — the contract never holds, moves, or can confiscate funds.
- **No plaintext subscriber** — subscribers appear only as commitments and
  nullifiers; no subscriber address is ever stored or emitted.
- **Zero external calls** — payments are witnessed, not executed, so there is no
  reentrancy surface.

## Entrypoints

| Call | Who | Effect |
|---|---|---|
| `create_plan(price, duration, payment_token, recipient, tier_id, metadata_uri)` | anyone | Registers a public plan, returns a monotonic `plan_id`. |
| `set_plan_active(plan_id, active)` | plan creator | Toggles new subscriptions (existing paid time is never confiscated). |
| `subscribe(plan_id, commitment, payment_nullifier)` | anyone | Witnesses payment, inserts the commitment, spends the payment nullifier. |
| `renew(plan_id, old_nullifier, commitment, payment_nullifier)` | anyone | Spends the prior subscription + payment nullifiers, inserts the extended commitment. |
| `cancel(plan_id, old_nullifier)` | note owner (via proof) | Spends the subscription nullifier without re-inserting. |
| `set_public_optin(plan_id, opted_in)` | plan creator | Opt in to a public active-subscriber counter. |

Views: `verify_tier`, `get_plan`, `get_last_plan_id`, `current_root`,
`is_known_root`, `is_nullifier_spent`, `plan_active_count`, `is_public_optin`,
`is_reference_build`, `contract_version`.

## Build & test

```bash
scarb build
snforge test
```

## Design

Full architecture and contract spec live in `medialane-core`:
`docs/specs/2026-07-04-private-subscriptions-system-architecture.md` and
`docs/specs/2026-07-04-private-subscription-contract-design.md`.
