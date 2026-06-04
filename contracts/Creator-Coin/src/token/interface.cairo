use openzeppelin::token::erc20::interface::{IERC20Metadata, IERC20, IERC20Camel};
use starknet::ContractAddress;
use super::creator_coin::{LiquidityType, LiquidityParameters};
use creator_coin::exchanges::SupportedExchanges;

#[starknet::interface]
trait ICreatorCoin<TState> {
    // ************************************
    // * Ownership
    // ************************************
    fn owner(self: @TState) -> ContractAddress;
    fn transfer_ownership(ref self: TState, new_owner: ContractAddress);
    fn renounce_ownership(ref self: TState);

    // ************************************
    // * Metadata
    // ************************************
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;

    // ************************************
    // * snake_case
    // ************************************
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

    // ************************************
    // * camelCase
    // ************************************
    fn totalSupply(self: @TState) -> u256;
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;

    // ************************************
    // * Additional functions
    // ************************************
    /// Checks whether token has launched
    ///
    /// # Returns
    ///     bool: whether token has launched
    fn is_launched(self: @TState) -> bool;
    fn launched_at_block_number(self: @TState) -> u64;
    fn launched_with_liquidity_parameters(self: @TState) -> Option<LiquidityParameters>;
    fn liquidity_type(self: @TState) -> Option<LiquidityType>;
    fn get_team_allocation(self: @TState) -> u256;
    fn creator_coin_factory_address(self: @TState) -> ContractAddress;
    fn set_launched(
        ref self: TState,
        liquidity_type: LiquidityType,
        liquidity_params: LiquidityParameters,
        transfer_restriction_delay: u64,
        max_percentage_buy_launch: u16,
        team_allocation: u256,
    );
}

#[starknet::interface]
trait ICreatorCoinCamel<TState> {
    fn totalSupply(self: @TState) -> u256;
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}

#[starknet::interface]
trait ICreatorCoinSnake<TState> {
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait ICreatorCoinAdditional<TState> {
    /// Returns whether the creator_coin has been launched.
    ///
    /// # Returns
    ///
    /// * `bool` - True if the creator_coin has been launched, false otherwise.
    fn is_launched(self: @TState) -> bool;

    /// Returns the number of the block during which the token has been launched,
    /// or 0 if not launched yet.
    fn launched_at_block_number(self: @TState) -> u64;

    /// Returns the liquidity parameters used to launch the creator_coin.
    fn launched_with_liquidity_parameters(self: @TState) -> Option<LiquidityParameters>;

    /// Returns the type of liquidity the creator_coin was launched with,
    /// along with either the LP tokens addresses or the NFT ID.
    fn liquidity_type(self: @TState) -> Option<LiquidityType>;

    /// Returns the team allocation.
    fn get_team_allocation(self: @TState) -> u256;

    /// Returns the creator_coin factory address.
    fn creator_coin_factory_address(self: @TState) -> ContractAddress;

    /// Sets the creator_coin as launched and transfers ownership to the zero address.
    ///
    /// This function can only be called by the factory contract. It sets the creator_coin as launched, records the liquidity position and the launch time, and transfers ownership of the creator_coin to the zero address.
    ///
    /// # Arguments
    ///
    /// * `liquidity_type` - The liquidity position at the time of launch.
    /// * `transfer_restriction_delay` - The delay in seconds before transfers are no longer limited.
    ///
    /// # Panics
    ///
    /// This function will panic if:
    ///
    /// * The caller's address is not the same as the `factory` of the creator_coin (error code: `errors::CALLER_NOT_FACTORY`).
    /// * The creator_coin has already been launched (error code: `errors::ALREADY_LAUNCHED`).
    ///
    fn set_launched(
        ref self: TState,
        liquidity_type: LiquidityType,
        liquidity_params: LiquidityParameters,
        transfer_restriction_delay: u64,
        max_percentage_buy_launch: u16,
        team_allocation: u256,
    );
}
