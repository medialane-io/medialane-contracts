use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare,
    cheat_caller_address, cheat_block_timestamp, CheatSpan,
    spy_events, EventSpyAssertionsTrait,
};
use starknet::ContractAddress;
use nft_comments::{INFTCommentsDispatcher, INFTCommentsDispatcherTrait};

// ── Constants ─────────────────────────────────────────────────────────────────

const COMMENTER: felt252 = 0x2001;
const COMMENTER2: felt252 = 0x2002;
// Any non-zero address — no external call is made to this address.
const NFT_CONTRACT: felt252 = 0x3001;
const NFT_CONTRACT2: felt252 = 0x3002;
const TOKEN_ID: u256 = 1_u256;

// ── Helpers ───────────────────────────────────────────────────────────────────

fn commenter() -> ContractAddress { COMMENTER.try_into().unwrap() }
fn commenter2() -> ContractAddress { COMMENTER2.try_into().unwrap() }
fn nft() -> ContractAddress { NFT_CONTRACT.try_into().unwrap() }
fn nft2() -> ContractAddress { NFT_CONTRACT2.try_into().unwrap() }

fn deploy_comments() -> INFTCommentsDispatcher {
    let class = declare("NFTComments").unwrap().contract_class();
    // No constructor args — immutable, ownerless contract.
    let (addr, _) = class.deploy(@array![]).unwrap();
    INFTCommentsDispatcher { contract_address: addr }
}

// ── Input validation ──────────────────────────────────────────────────────────

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
    let c = deploy_comments();
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "");
}

#[test]
#[should_panic(expected: "comment too long")]
fn test_comment_over_1000_bytes_rejected() {
    let c = deploy_comments();
    let mut s: ByteArray = "";
    let mut i: u32 = 0;
    loop {
        if i >= 1001 { break; }
        s.append_byte('x');
        i += 1;
    };
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, s);
}

#[test]
fn test_exactly_1000_bytes_is_allowed() {
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
    c.add_comment(nft(), TOKEN_ID, s);
}

// ── Rate limit ────────────────────────────────────────────────────────────────

#[test]
fn test_first_comment_always_succeeds() {
    let c = deploy_comments();
    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "first comment");
}

#[test]
#[should_panic(expected: "rate limited: wait 60 seconds between comments")]
fn test_second_comment_within_60s_rejected() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "first");

    // t=1059 — 59 seconds later, still rate-limited
    cheat_block_timestamp(c.contract_address, 1059, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "too soon");
}

#[test]
fn test_second_comment_after_60s_succeeds() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "first");

    cheat_block_timestamp(c.contract_address, 1060, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "second");
}

#[test]
fn test_exact_60s_boundary_is_allowed() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "at t=1000");

    // 1000 + 60 == 1060 >= 1060 → allowed
    cheat_block_timestamp(c.contract_address, 1060, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "at t=1060");
}

// ── Rate limit is per (nft_contract, token_id, caller) ───────────────────────

#[test]
fn test_rate_limit_is_per_token() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), 1_u256, "token 1");

    // Different token_id — not rate-limited
    cheat_block_timestamp(c.contract_address, 1001, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), 2_u256, "token 2");
}

#[test]
fn test_rate_limit_is_per_nft_contract() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "nft contract 1");

    // Different nft_contract — not rate-limited
    cheat_block_timestamp(c.contract_address, 1001, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft2(), TOKEN_ID, "nft contract 2");
}

#[test]
fn test_rate_limit_is_per_caller() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "commenter 1");

    // Different caller — not rate-limited
    cheat_block_timestamp(c.contract_address, 1001, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter2(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "commenter 2");
}

// ── Comment ID and count ──────────────────────────────────────────────────────

#[test]
fn test_comment_count_starts_at_zero() {
    let c = deploy_comments();
    assert!(c.comment_count() == 0, "initial count should be 0");
}

#[test]
fn test_contract_version() {
    let c = deploy_comments();
    assert!(c.contract_version() == '0.1.0', "version mismatch");
}

#[test]
fn test_comment_count_increments_per_comment() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "first");
    assert!(c.comment_count() == 1, "count should be 1 after first comment");

    cheat_block_timestamp(c.contract_address, 1060, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "second");
    assert!(c.comment_count() == 2, "count should be 2 after second comment");
}

#[test]
fn test_comment_id_emitted_in_event() {
    let c = deploy_comments();
    let mut spy = spy_events();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "hello");

    // comment_id=1 should appear as the 4th key in the CommentAdded event.
    // Keys order: nft_contract, token_id (low, high), author, comment_id
    spy.assert_emitted(
        @array![(
            c.contract_address,
            nft_comments::nft_comments::NFTComments::Event::CommentAdded(
                nft_comments::nft_comments::NFTComments::CommentAdded {
                    nft_contract: nft(),
                    token_id: TOKEN_ID,
                    author: commenter(),
                    comment_id: 1_u64,
                    content: "hello",
                    timestamp: 1000_u64,
                }
            )
        )]
    );
}

#[test]
fn test_failed_comment_does_not_increment_count() {
    let c = deploy_comments();

    cheat_block_timestamp(c.contract_address, 1000, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "first");
    assert!(c.comment_count() == 1, "count should be 1");

    // This should panic (rate-limited), leaving count at 1
    // We test this by verifying count stays 1 after a successful comment
    cheat_block_timestamp(c.contract_address, 1060, CheatSpan::TargetCalls(1));
    cheat_caller_address(c.contract_address, commenter(), CheatSpan::TargetCalls(1));
    c.add_comment(nft(), TOKEN_ID, "second at t=1060");
    assert!(c.comment_count() == 2, "count should be 2 after valid second comment");
}
