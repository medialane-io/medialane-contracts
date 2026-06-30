mod test_asserts;
mod test_factory;
mod test_comp_src5;
mod test_offchain_hashing;
mod test_secp256k1;
mod test_secp256r1;
mod test_signature_malleability;
mod test_transaction_version;
mod test_version;

mod argent_account {
    mod test_argent_account;
    mod test_escape;
    mod test_signatures;
}

mod setup {
    pub mod argent_account_setup;
    pub mod constants;
    pub mod utils;
}

// Re-export the test setup functions to have them all available in one place
use setup::{
    argent_account_setup::{
        ITestMediaWalletDispatcherTrait, initialize_account, initialize_account_with,
        initialize_account_without_guardian,
    },
    constants::{
        ARGENT_ACCOUNT_ADDRESS, GUARDIAN, KeyAndSig, OWNER, TX_HASH, WRONG_GUARDIAN, WRONG_OWNER,
    },
    utils::{ByteArrayExt, Felt252TryIntoStarknetSigner, to_starknet_signatures, to_starknet_signer_signatures},
};
