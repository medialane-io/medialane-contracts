pub mod errors {
    pub const INVALID_SIGNATURE: felt252 = 'Invalid signature';
    pub const ORDER_EXPIRED: felt252 = 'Order expired';
    pub const ORDER_NOT_YET_VALID: felt252 = 'Order not yet valid';
    pub const ORDER_NOT_FOUND: felt252 = 'Order not found';
    pub const ORDER_ALREADY_CREATED: felt252 = 'Order already created';
    pub const ORDER_ALREADY_FILLED: felt252 = 'Order already filled';
    pub const ORDER_CANCELLED: felt252 = 'Order cancelled';
    pub const TRANSFER_FAILED: felt252 = 'Transfer failed';
    pub const ROYALTY_TRANSFER_FAILED: felt252 = 'Royalty transfer failed';
    pub const CALLER_NOT_OFFERER: felt252 = 'Caller not offerer';
    pub const CALLER_NOT_FULFILLER: felt252 = 'Caller not fulfiller';
    pub const END_AMOUNT_MISMATCH: felt252 = 'End amount must equal start';
    pub const INVALID_OFFERER: felt252 = 'Offerer cannot be zero';
    pub const INVALID_AMOUNT: felt252 = 'Amount must be nonzero';
    pub const INVALID_PRICE: felt252 = 'Price must be nonzero';
    pub const INVALID_NFT_CONTRACT: felt252 = 'NFT contract cannot be zero';
    pub const ROYALTY_EXCEEDS_PRICE: felt252 = 'Royalty exceeds sale price';
}
