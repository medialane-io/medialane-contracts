//! Test-only mock contracts. Compiled only under `#[cfg(test)]` — never shipped.

/// A collection that declares ERC-2981 and reports a flat 5% royalty.
#[starknet::contract]
pub mod MockRoyaltyCollection {
    use starknet::ContractAddress;
    use crate::constants::IERC2981_ID;

    #[storage]
    struct Storage {}

    #[abi(per_item)]
    #[generate_trait]
    pub impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            interface_id == IERC2981_ID
        }

        #[external(v0)]
        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let receiver: ContractAddress = 0x999.try_into().unwrap();
            (receiver, sale_price * 5 / 100)
        }
    }
}

/// A collection that does not declare ERC-2981 — `supports_interface` is false
/// for every id.
#[starknet::contract]
pub mod MockPlainCollection {
    #[storage]
    struct Storage {}

    #[abi(per_item)]
    #[generate_trait]
    pub impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            false
        }
    }
}
