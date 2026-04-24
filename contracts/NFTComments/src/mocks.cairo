// Mock ERC-721 for NFTComments tests.
// Implements supports_interface (SRC5) and owner_of (ERC-721).
// All tokens are "owned" by a sentinel address so owner_of never reverts.

use starknet::ContractAddress;

const IERC721_ID: felt252 = 0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943;
const ISRC5_ID: felt252 = 0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055;

#[starknet::interface]
trait IMockERC721<TContractState> {
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
}

#[starknet::contract]
pub mod MockERC721 {
    use starknet::ContractAddress;
    use super::{IERC721_ID, ISRC5_ID};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MockERC721Impl of super::IMockERC721<ContractState> {
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            interface_id == IERC721_ID || interface_id == ISRC5_ID
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            0x1234.try_into().unwrap()
        }
    }
}
