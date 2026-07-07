#![cfg(test)]

use soroban_sdk::{
    contract, contractimpl, contracttype,
    testutils::{Address as _, Ledger},
    token, Address, Env, String,
};

use crate::{MedialaneMarketplace, MedialaneMarketplaceClient, Side};

// Minimal NFT with the royalty_info interface, for venue tests.
#[contract]
pub struct MockNft;

#[contracttype]
pub enum NftKey {
    Owner(u32),
    Operator(Address, Address),
    Royalty,
}

#[contractimpl]
impl MockNft {
    pub fn mint(e: Env, to: Address, token_id: u32) {
        e.storage().persistent().set(&NftKey::Owner(token_id), &to);
    }

    pub fn owner_of(e: Env, token_id: u32) -> Address {
        e.storage().persistent().get(&NftKey::Owner(token_id)).unwrap()
    }

    pub fn approve_for_all(e: Env, owner: Address, operator: Address, _live_until: u32) {
        owner.require_auth();
        e.storage().persistent().set(&NftKey::Operator(owner, operator), &true);
    }

    pub fn transfer_from(e: Env, spender: Address, from: Address, to: Address, token_id: u32) {
        spender.require_auth();
        let owner: Address = e.storage().persistent().get(&NftKey::Owner(token_id)).unwrap();
        assert!(owner == from, "not owner");
        if spender != from {
            let approved: bool = e
                .storage()
                .persistent()
                .get(&NftKey::Operator(from.clone(), spender.clone()))
                .unwrap_or(false);
            assert!(approved, "not approved");
        }
        e.storage().persistent().set(&NftKey::Owner(token_id), &to);
    }

    pub fn set_royalty(e: Env, receiver: Address, bps: u32) {
        e.storage().persistent().set(&NftKey::Royalty, &(receiver, bps));
    }

    pub fn royalty_info(e: Env, _token_id: u32, sale_price: i128) -> (Address, i128) {
        let (receiver, bps): (Address, u32) =
            e.storage().persistent().get(&NftKey::Royalty).unwrap();
        (receiver, sale_price * (bps as i128) / 10_000)
    }
}

// An NFT without royalty_info at all (absent-interface case).
#[contract]
pub struct BareNft;

#[contractimpl]
impl BareNft {
    pub fn mint(e: Env, to: Address, token_id: u32) {
        e.storage().persistent().set(&NftKey::Owner(token_id), &to);
    }

    pub fn owner_of(e: Env, token_id: u32) -> Address {
        e.storage().persistent().get(&NftKey::Owner(token_id)).unwrap()
    }

    pub fn approve_for_all(e: Env, owner: Address, operator: Address, _live_until: u32) {
        owner.require_auth();
        e.storage().persistent().set(&NftKey::Operator(owner, operator), &true);
    }

    pub fn transfer_from(e: Env, spender: Address, from: Address, to: Address, token_id: u32) {
        spender.require_auth();
        let owner: Address = e.storage().persistent().get(&NftKey::Owner(token_id)).unwrap();
        assert!(owner == from, "not owner");
        if spender != from {
            let approved: bool = e
                .storage()
                .persistent()
                .get(&NftKey::Operator(from.clone(), spender.clone()))
                .unwrap_or(false);
            assert!(approved, "not approved");
        }
        e.storage().persistent().set(&NftKey::Owner(token_id), &to);
    }
}

pub struct Setup {
    pub env: Env,
    pub venue: MedialaneMarketplaceClient<'static>,
    pub nft: Address,
    pub nft_client: MockNftClient<'static>,
    pub pay: Address,
    pub pay_admin: token::StellarAssetClient<'static>,
    pub pay_client: token::Client<'static>,
    pub seller: Address,
    pub buyer: Address,
    pub royalty_receiver: Address,
}

pub fn setup(royalty_bps: u32) -> Setup {
    let env = Env::default();
    env.mock_all_auths();
    env.ledger().set_timestamp(1_000_000);
    let venue_id = env.register(MedialaneMarketplace, ());
    let venue = MedialaneMarketplaceClient::new(&env, &venue_id);
    let nft = env.register(MockNft, ());
    let nft_client = MockNftClient::new(&env, &nft);
    let sac = env.register_stellar_asset_contract_v2(Address::generate(&env));
    let pay = sac.address();
    let pay_admin = token::StellarAssetClient::new(&env, &pay);
    let pay_client = token::Client::new(&env, &pay);
    let seller = Address::generate(&env);
    let buyer = Address::generate(&env);
    let royalty_receiver = Address::generate(&env);
    nft_client.mint(&seller, &7u32);
    if royalty_bps > 0 {
        nft_client.set_royalty(&royalty_receiver, &royalty_bps);
    }
    pay_admin.mint(&buyer, &1_000_000_000i128);
    Setup { env, venue, nft, nft_client, pay, pay_admin, pay_client, seller, buyer, royalty_receiver }
}

pub fn register_listing(s: &Setup, salt: u64, amount: i128, max_bps: u32, start: u64, end: u64, counter: u64) {
    s.venue.register_order(
        &s.seller, &salt, &Side::Listing, &s.nft, &7u32, &s.pay, &amount, &max_bps, &start, &end, &counter,
    );
}

#[test]
fn register_listing_and_bid() {
    let s = setup(500);
    register_listing(&s, 1, 100_000_000, 1000, 1_000_000, 0, 0);
    let order = s.venue.get_order(&s.seller, &1u64);
    assert_eq!(order.offerer, s.seller);
    assert_eq!(order.side, Side::Listing);
    assert_eq!(order.amount, 100_000_000);
    assert_eq!(order.royalty_max_bps, 1000);

    // Bid in the same SAC token (the XLM model) — no direction restriction.
    s.venue.register_order(
        &s.buyer, &9u64, &Side::Bid, &s.nft, &7u32, &s.pay, &50_000_000i128, &1000u32,
        &1_000_000u64, &0u64, &0u64,
    );
    let bid = s.venue.get_order(&s.buyer, &9u64);
    assert_eq!(bid.side, Side::Bid);
}

#[test]
#[should_panic]
fn register_rejects_wrong_counter() {
    let s = setup(0);
    register_listing(&s, 1, 1, 0, 1_000_000, 0, 5);
}

#[test]
#[should_panic]
fn register_rejects_high_bps() {
    let s = setup(0);
    register_listing(&s, 1, 1, 10_001, 1_000_000, 0, 0);
}

#[test]
#[should_panic]
fn register_rejects_inverted_window() {
    let s = setup(0);
    register_listing(&s, 1, 1, 0, 2_000_000, 1_500_000, 0);
}

#[test]
#[should_panic]
fn register_rejects_expired() {
    let s = setup(0);
    register_listing(&s, 1, 1, 0, 500_000, 900_000, 0);
}

#[test]
fn register_allows_no_expiry() {
    let s = setup(0);
    register_listing(&s, 1, 1, 0, 1_000_000, 0, 0);
}

#[test]
#[should_panic]
fn register_rejects_duplicate_salt() {
    let s = setup(0);
    register_listing(&s, 1, 1, 0, 1_000_000, 0, 0);
    register_listing(&s, 1, 2, 0, 1_000_000, 0, 0);
}

#[test]
#[should_panic]
fn register_rejects_negative_amount() {
    let s = setup(0);
    register_listing(&s, 1, -5, 0, 1_000_000, 0, 0);
}
