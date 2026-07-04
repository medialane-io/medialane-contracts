use starknet::ContractAddress;
use private_subscription::types::PlanRecord;

#[starknet::interface]
pub trait IPrivateSubscription<TState> {
    fn create_plan(
        ref self: TState,
        price: u256,
        duration: u64,
        payment_token: ContractAddress,
        recipient: ContractAddress,
        tier_id: felt252,
        metadata_uri: ByteArray,
    ) -> u256;
    fn set_plan_active(ref self: TState, plan_id: u256, active: bool);
    fn subscribe(ref self: TState, plan_id: u256, commitment: felt252, payment_nullifier: felt252);
    fn renew(
        ref self: TState,
        plan_id: u256,
        old_nullifier: felt252,
        commitment: felt252,
        payment_nullifier: felt252,
    );
    fn cancel(ref self: TState, plan_id: u256, old_nullifier: felt252);
    fn verify_tier(self: @TState, tier_id: felt252, root: felt252, min_expiry: u64) -> bool;
    fn set_public_optin(ref self: TState, plan_id: u256, opted_in: bool);
    fn get_plan(self: @TState, plan_id: u256) -> PlanRecord;
    fn get_last_plan_id(self: @TState) -> u256;
    fn current_root(self: @TState) -> felt252;
    fn is_known_root(self: @TState, root: felt252) -> bool;
    fn is_nullifier_spent(self: @TState, nullifier: felt252) -> bool;
    fn plan_active_count(self: @TState, plan_id: u256) -> u256;
    fn is_public_optin(self: @TState, plan_id: u256) -> bool;
    fn is_reference_build(self: @TState) -> bool;
    fn contract_version(self: @TState) -> felt252;
}
