use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare,
    cheat_caller_address, cheat_block_timestamp, CheatSpan,
};
use starknet::ContractAddress;
use nft_comments::{INFTCommentsDispatcher, INFTCommentsDispatcherTrait};

// ── Constants ─────────────────────────────────────────────────────────────────

const OWNER: felt252 = 0x1001;
const COMMENTER: felt252 = 0x2001;
const COMMENTER2: felt252 = 0x2002;
const NFT_CONTRACT: felt252 = 0x3001;
const TOKEN_ID: u256 = 1_u256;

// ── Helpers ───────────────────────────────────────────────────────────────────

fn owner() -> ContractAddress { OWNER.try_into().unwrap() }
fn commenter() -> ContractAddress { COMMENTER.try_into().unwrap() }
fn commenter2() -> ContractAddress { COMMENTER2.try_into().unwrap() }

fn deploy_comments() -> INFTCommentsDispatcher {
    let class = declare("NFTComments").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    let (addr, _) = class.deploy(@cd).unwrap();
    INFTCommentsDispatcher { contract_address: addr }
}

fn deploy_mock_nft() -> ContractAddress {
    let class = declare("MockERC721").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

// ── Validation ────────────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: "invalid nft contract")]
fn test_zero_nft_contract_rejected() {
    let c = deploy_comments();
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(0.try_into().unwrap(), TOKEN_ID, "hello");
}

#[test]
#[should_panic(expected: "comment cannot be empty")]
fn test_empty_comment_rejected() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "");
}

#[test]
#[should_panic(expected: "comment too long")]
fn test_comment_over_1000_bytes_rejected() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();
    // Build a 1001-byte string
    let mut s: ByteArray = "";
    let mut i: u32 = 0;
    loop {
        if i >= 1001 { break; }
        s.append_byte('x');
        i += 1;
    };
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, s);
}

// ── Rate limit ────────────────────────────────────────────────────────────────

#[test]
fn test_first_comment_always_succeeds() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "first comment");
}

#[test]
#[should_panic(expected: "rate limited: wait 60 seconds between comments")]
fn test_second_comment_within_60s_rejected() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();

    // First comment at t=1000
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "first");

    // Second comment at t=1059 (59 seconds later — still rate-limited)
    cheat_block_timestamp(c.contract_address, 1059, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "too soon");
}

#[test]
fn test_second_comment_after_60s_succeeds() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();

    // First comment at t=1000
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "first");

    // Second comment exactly 60s later — should be allowed
    cheat_block_timestamp(c.contract_address, 1060, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "second");
}

// ── Rate limit is per (nft_contract, token_id, caller) ───────────────────────

#[test]
fn test_rate_limit_is_per_token() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();

    // Comment on token 1 at t=1000
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, 1_u256, "comment on token 1");

    // Comment on token 2 at t=1001 — different token, should NOT be rate-limited
    cheat_block_timestamp(c.contract_address, 1001, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, 2_u256, "comment on token 2");
}

#[test]
fn test_rate_limit_is_per_caller() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();

    // COMMENTER comments at t=1000
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "commenter 1");

    // COMMENTER2 comments on same token at t=1001 — different wallet, NOT rate-limited
    cheat_block_timestamp(c.contract_address, 1001, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter2(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "commenter 2");
}

#[test]
fn test_exact_60s_boundary_is_allowed() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();

    // Use t=1000 as base — default snforge timestamp is 0, which fails `0 >= 0+60`.
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "at t=1000");

    // At t=1060 exactly: 1000 + 60 == 1060 >= 1060 → allowed
    cheat_block_timestamp(c.contract_address, 1060, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, "at t=1060");
}

// ── 1000-byte boundary ────────────────────────────────────────────────────────

#[test]
fn test_exactly_1000_bytes_is_allowed() {
    let nft = deploy_mock_nft();
    let c = deploy_comments();
    let mut s: ByteArray = "";
    let mut i: u32 = 0;
    loop {
        if i >= 1000 { break; }
        s.append_byte('x');
        i += 1;
    };
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft, TOKEN_ID, s);
}
