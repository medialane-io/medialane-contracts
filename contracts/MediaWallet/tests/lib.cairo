mod test_asserts;
mod test_comp_src5;
mod test_offchain_hashing;
mod test_secp256k1;
mod test_secp256r1;
mod test_signature_malleability;
mod test_transaction_version;
mod test_version;

mod wallet_account {
    mod test_escape;
    mod test_signatures;
    mod test_wallet_account;
}

mod setup {
    pub mod constants;
    pub mod utils;
    pub mod wallet_account_setup;
}

// Re-export the test setup functions to have them all available in one place
use setup::{
    constants::{GUARDIAN, KeyAndSig, OWNER, TX_HASH, WALLET_ACCOUNT_ADDRESS, WRONG_GUARDIAN, WRONG_OWNER},
    utils::{ByteArrayExt, Felt252TryIntoStarknetSigner, to_starknet_signatures, to_starknet_signer_signatures},
    wallet_account_setup::{
        ITestMediaWalletDispatcherTrait, initialize_account, initialize_account_with,
        initialize_account_without_guardian,
    },
};
