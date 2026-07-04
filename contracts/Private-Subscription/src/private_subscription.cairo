#[starknet::contract]
pub mod PrivateSubscription {
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use private_subscription::errors::errors;
    use private_subscription::interface::IPrivateSubscription;
    use private_subscription::merkle;
    use private_subscription::proof_facts::proof_verified;
    use private_subscription::types::{PlanRecord, bytearray_starts_with, PAYMENT_PROGRAM, TIER_PROGRAM};

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    const CONTRACT_VERSION: felt252 = '0.1.0-ref';
    const ROOT_WINDOW: u64 = 64;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        last_plan_id: u256,
        plans: Map<u256, PlanRecord>,
        // Merkle accumulator
        current_root: felt252,
        leaf_count: u64,
        filled_subtrees: Map<u32, felt252>,
        known_roots: Map<felt252, bool>,
        root_ring: Map<u64, felt252>,
        root_ring_head: u64,
        // Nullifiers (payment + subscription, one namespace)
        spent_nullifiers: Map<felt252, bool>,
        // Opt-in public counters
        plan_public_optin: Map<u256, bool>,
        plan_active_count: Map<u256, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        PlanCreated: PlanCreated,
        PlanStatusUpdated: PlanStatusUpdated,
        Subscribed: Subscribed,
        SubscriptionRenewed: SubscriptionRenewed,
        SubscriptionCancelled: SubscriptionCancelled,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PlanCreated {
        #[key]
        pub plan_id: u256,
        #[key]
        pub creator: ContractAddress,
        pub recipient: ContractAddress,
        pub price: u256,
        pub duration: u64,
        pub tier_id: felt252,
        pub created_at: u64,
    }
    #[derive(Drop, starknet::Event)]
    pub struct PlanStatusUpdated {
        #[key]
        pub plan_id: u256,
        pub active: bool,
    }
    #[derive(Drop, starknet::Event)]
    pub struct Subscribed {
        #[key]
        pub plan_id: u256,
        pub commitment: felt252,
        pub leaf_index: u64,
        pub root: felt252,
    }
    #[derive(Drop, starknet::Event)]
    pub struct SubscriptionRenewed {
        #[key]
        pub plan_id: u256,
        pub old_nullifier: felt252,
        pub commitment: felt252,
        pub root: felt252,
    }
    #[derive(Drop, starknet::Event)]
    pub struct SubscriptionCancelled {
        #[key]
        pub plan_id: u256,
        pub nullifier: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        // Initialize the empty-tree root = zeros(DEPTH).
        self.current_root.write(merkle::zeros(merkle::DEPTH));
    }

    #[abi(embed_v0)]
    impl Impl of IPrivateSubscription<ContractState> {
        fn create_plan(
            ref self: ContractState,
            price: u256,
            duration: u64,
            payment_token: ContractAddress,
            recipient: ContractAddress,
            tier_id: felt252,
            metadata_uri: ByteArray,
        ) -> u256 {
            let creator = get_caller_address();
            assert(duration > 0, errors::ZERO_DURATION);
            assert(!recipient.is_zero(), errors::ZERO_RECIPIENT);
            let valid_uri = bytearray_starts_with(@metadata_uri, @"ipfs://")
                || bytearray_starts_with(@metadata_uri, @"ar://");
            assert(valid_uri, errors::BAD_URI);
            if price == 0 {
                assert(payment_token.is_zero(), errors::FREE_PLAN_TOKEN);
            } else {
                assert(!payment_token.is_zero(), errors::PAID_PLAN_NO_TOKEN);
            }

            let plan_id = self.last_plan_id.read() + 1;
            self
                .plans
                .entry(plan_id)
                .write(
                    PlanRecord {
                        creator,
                        recipient,
                        payment_token,
                        price,
                        duration,
                        tier_id,
                        metadata_uri: metadata_uri.clone(),
                        active: true,
                    },
                );
            self.last_plan_id.write(plan_id);
            self
                .emit(
                    PlanCreated {
                        plan_id,
                        creator,
                        recipient,
                        price,
                        duration,
                        tier_id,
                        created_at: get_block_timestamp(),
                    },
                );
            plan_id
        }

        fn set_plan_active(ref self: ContractState, plan_id: u256, active: bool) {
            let mut plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), errors::PLAN_NOT_FOUND);
            assert(get_caller_address() == plan.creator, errors::ONLY_CREATOR);
            plan.active = active;
            self.plans.entry(plan_id).write(plan);
            self.emit(PlanStatusUpdated { plan_id, active });
        }

        fn subscribe(
            ref self: ContractState, plan_id: u256, commitment: felt252, payment_nullifier: felt252,
        ) {
            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), errors::PLAN_NOT_FOUND);
            assert(plan.active, errors::PLAN_INACTIVE);
            self._require_payment(plan_id, @plan, commitment, payment_nullifier);
            self._spend(payment_nullifier);
            let (leaf_index, root) = self._insert_commitment(commitment);
            if self.plan_public_optin.entry(plan_id).read() {
                let n = self.plan_active_count.entry(plan_id).read();
                self.plan_active_count.entry(plan_id).write(n + 1);
            }
            self.emit(Subscribed { plan_id, commitment, leaf_index, root });
        }

        fn renew(
            ref self: ContractState,
            plan_id: u256,
            old_nullifier: felt252,
            commitment: felt252,
            payment_nullifier: felt252,
        ) {
            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), errors::PLAN_NOT_FOUND);
            assert(plan.active, errors::PLAN_INACTIVE);
            // Payment for the new period.
            self._require_payment(plan_id, @plan, commitment, payment_nullifier);
            // Spend the prior subscription note and the payment note.
            self._spend(old_nullifier);
            self._spend(payment_nullifier);
            // Insert the extended-expiry commitment (expiry is bound inside the proof).
            let (_leaf, root) = self._insert_commitment(commitment);
            self.emit(SubscriptionRenewed { plan_id, old_nullifier, commitment, root });
        }

        fn cancel(ref self: ContractState, plan_id: u256, old_nullifier: felt252) {
            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), errors::PLAN_NOT_FOUND);
            // Ownership proof: prove the caller controls the note behind old_nullifier
            // (tier program, expiry irrelevant here). Binds plan_id + nullifier.
            let inputs = array![plan_id.low.into(), plan_id.high.into(), old_nullifier];
            assert(proof_verified(TIER_PROGRAM, inputs.span()), errors::INVALID_TIER_PROOF);
            self._spend(old_nullifier);
            if self.plan_public_optin.entry(plan_id).read() {
                let n = self.plan_active_count.entry(plan_id).read();
                if n > 0 {
                    self.plan_active_count.entry(plan_id).write(n - 1);
                }
            }
            self.emit(SubscriptionCancelled { plan_id, nullifier: old_nullifier });
        }

        fn verify_tier(
            self: @ContractState, tier_id: felt252, root: felt252, min_expiry: u64,
        ) -> bool {
            assert(self.known_roots.entry(root).read(), errors::UNKNOWN_ROOT);
            let inputs = array![tier_id, root, min_expiry.into()];
            proof_verified(TIER_PROGRAM, inputs.span())
        }

        fn set_public_optin(ref self: ContractState, plan_id: u256, opted_in: bool) {
            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), errors::PLAN_NOT_FOUND);
            assert(get_caller_address() == plan.creator, errors::ONLY_CREATOR);
            self.plan_public_optin.entry(plan_id).write(opted_in);
        }

        fn get_plan(self: @ContractState, plan_id: u256) -> PlanRecord {
            let plan = self.plans.entry(plan_id).read();
            assert(!plan.creator.is_zero(), errors::PLAN_NOT_FOUND);
            plan
        }
        fn get_last_plan_id(self: @ContractState) -> u256 {
            self.last_plan_id.read()
        }
        fn current_root(self: @ContractState) -> felt252 {
            self.current_root.read()
        }
        fn is_known_root(self: @ContractState, root: felt252) -> bool {
            self.known_roots.entry(root).read()
        }
        fn is_nullifier_spent(self: @ContractState, nullifier: felt252) -> bool {
            self.spent_nullifiers.entry(nullifier).read()
        }
        fn plan_active_count(self: @ContractState, plan_id: u256) -> u256 {
            self.plan_active_count.entry(plan_id).read()
        }
        fn is_public_optin(self: @ContractState, plan_id: u256) -> bool {
            self.plan_public_optin.entry(plan_id).read()
        }
        fn is_reference_build(self: @ContractState) -> bool {
            true
        }
        fn contract_version(self: @ContractState) -> felt252 {
            CONTRACT_VERSION
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn _expected_payment_inputs(
            self: @ContractState,
            plan_id: u256,
            plan: @PlanRecord,
            commitment: felt252,
            payment_nullifier: felt252,
        ) -> Array<felt252> {
            // Public inputs the payment circuit must attest. Binds the payment to
            // this plan's recipient+price and to the inserted commitment.
            array![
                plan_id.low.into(),
                plan_id.high.into(),
                (*plan.recipient).into(),
                (*plan.price).low.into(),
                (*plan.price).high.into(),
                commitment,
                payment_nullifier,
            ]
        }

        fn _require_payment(
            ref self: ContractState,
            plan_id: u256,
            plan: @PlanRecord,
            commitment: felt252,
            payment_nullifier: felt252,
        ) {
            let inputs = self._expected_payment_inputs(plan_id, plan, commitment, payment_nullifier);
            assert(proof_verified(PAYMENT_PROGRAM, inputs.span()), errors::INVALID_PROOF);
        }

        fn _spend(ref self: ContractState, nullifier: felt252) {
            assert(!self.spent_nullifiers.entry(nullifier).read(), errors::NULLIFIER_SPENT);
            self.spent_nullifiers.entry(nullifier).write(true);
        }

        /// Incremental insert. Returns (leaf_index, new_root) and records the root
        /// in the rolling known-roots window.
        fn _insert_commitment(ref self: ContractState, leaf: felt252) -> (u64, felt252) {
            let index = self.leaf_count.read();
            assert(index < pow2_u64(merkle::DEPTH), errors::TREE_FULL);
            let mut current = leaf;
            let mut cur_idx = index;
            let mut i: u32 = 0;
            while i < merkle::DEPTH {
                if cur_idx % 2 == 0 {
                    self.filled_subtrees.entry(i).write(current);
                    current = merkle::hash2(current, merkle::zeros(i));
                } else {
                    let left = self.filled_subtrees.entry(i).read();
                    current = merkle::hash2(left, current);
                }
                cur_idx = cur_idx / 2;
                i += 1;
            }
            self.current_root.write(current);
            self.leaf_count.write(index + 1);
            self._record_root(current);
            (index, current)
        }

        fn _record_root(ref self: ContractState, root: felt252) {
            self.known_roots.entry(root).write(true);
            let head = self.root_ring_head.read();
            // Evict the root leaving the window (keeps `known_roots` bounded).
            if head >= ROOT_WINDOW {
                let evict_slot = (head - ROOT_WINDOW) % ROOT_WINDOW;
                let old = self.root_ring.entry(evict_slot).read();
                if old != 0 {
                    self.known_roots.entry(old).write(false);
                }
            }
            self.root_ring.entry(head % ROOT_WINDOW).write(root);
            self.root_ring_head.write(head + 1);
        }
    }

    fn pow2_u64(exp: u32) -> u64 {
        let mut r: u64 = 1;
        let mut i: u32 = 0;
        while i < exp {
            r = r * 2;
            i += 1;
        }
        r
    }
}
