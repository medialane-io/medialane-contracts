pub mod errors {
    pub const INVALID_SIGNATURE: felt252 = 'Invalid signature';
    pub const ORDER_EXPIRED: felt252 = 'Order expired';
    pub const ORDER_NOT_YET_VALID: felt252 = 'Order not yet valid';
    pub const ORDER_NOT_FOUND: felt252 = 'Order not found';
    pub const ORDER_ALREADY_CREATED: felt252 = 'Order already created';
    pub const ORDER_ALREADY_FILLED: felt252 = 'Order already filled';
    pub const ORDER_CANCELLED: felt252 = 'Order cancelled';
    pub const TRANSFER_FAILED: felt252 = 'Transfer failed';
    pub const INVALID_ITEM_TYPE: felt252 = 'Invalid item type';
    pub const CALLER_NOT_OFFERER: felt252 = 'Caller not offerer';
    pub const INVALID_OFFERER: felt252 = 'Offerer cannot be zero';
    pub const INVALID_RECIPIENT: felt252 = 'Recipient cannot be zero';
    pub const INVALID_AMOUNT: felt252 = 'Invalid amount';
    pub const INVALID_TOKEN_ADDRESS: felt252 = 'Token address cannot be zero';
    pub const NONZERO_NATIVE_TOKEN: felt252 = 'Token address must be zero';
    pub const INVALID_IDENTIFIER: felt252 = 'Invalid identifier';
    pub const INVALID_TIME_WINDOW: felt252 = 'Invalid time window';
    pub const WRONG_MARKETPLACE: felt252 = 'Wrong marketplace';
    pub const INVALID_COUNTER: felt252 = 'Invalid counter';
    pub const SELF_FILL: felt252 = 'Cannot fill own order';
    pub const UNSUPPORTED_SHAPE: felt252 = 'Unsupported trade shape';
    pub const PAYMENT_TOKEN_IS_NFT: felt252 = 'Payment token is the NFT';
    pub const ROYALTY_BPS_TOO_HIGH: felt252 = 'Royalty bound too high';
    pub const ROYALTY_EXCEEDS_SALE: felt252 = 'Royalty exceeds sale';
    pub const ROYALTY_TRANSFER_FAILED: felt252 = 'Royalty transfer failed';
    pub const REENTRANT_CALL: felt252 = 'Reentrant call';
    // ERC1155-specific (partial fills)
    pub const INVALID_QUANTITY: felt252 = 'Quantity must be nonzero';
    pub const INSUFFICIENT_REMAINING: felt252 = 'Insufficient remaining units';
    pub const PRICE_OVERFLOW: felt252 = 'Price overflow';
}
