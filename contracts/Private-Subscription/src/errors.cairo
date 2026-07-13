pub mod errors {
    pub const PLAN_NOT_FOUND: felt252 = 'Plan does not exist';
    pub const PLAN_INACTIVE: felt252 = 'Plan is inactive';
    pub const ONLY_CREATOR: felt252 = 'Only plan creator';
    pub const ZERO_DURATION: felt252 = 'Duration cannot be zero';
    pub const ZERO_RECIPIENT: felt252 = 'Recipient is zero address';
    pub const BAD_URI: felt252 = 'URI must be ipfs or ar';
    pub const FREE_PLAN_TOKEN: felt252 = 'Free plan cannot use token';
    pub const PAID_PLAN_NO_TOKEN: felt252 = 'Paid plan requires token';
    pub const ZERO_TOKEN: felt252 = 'Payment token is zero';
    pub const INVALID_PROOF: felt252 = 'Invalid payment proof';
    pub const INVALID_TIER_PROOF: felt252 = 'Invalid tier proof';
    pub const NULLIFIER_SPENT: felt252 = 'Nullifier spent';
    pub const UNKNOWN_ROOT: felt252 = 'Unknown merkle root';
    pub const TREE_FULL: felt252 = 'Tree is full';
}
