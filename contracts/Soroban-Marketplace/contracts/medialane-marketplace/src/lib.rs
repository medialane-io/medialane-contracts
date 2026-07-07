#![no_std]
use soroban_sdk::{contract, contractimpl};

#[contract]
pub struct MedialaneMarketplace;

#[contractimpl]
impl MedialaneMarketplace {
    pub fn version_num() -> u32 {
        1
    }
}
