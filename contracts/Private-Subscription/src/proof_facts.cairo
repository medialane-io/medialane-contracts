/// Checks whether `facts` opens with a record `[program, n, i_0..i_{n-1}]`
/// whose program hash and inputs exactly match. This is the permanent,
/// production-identical matcher. Encoding is a placeholder pending StarkWare
/// confirmation of the real proof_facts layout (see starkware-questions.md Q2).
pub fn facts_contain(
    facts: Span<felt252>, program: felt252, inputs: Span<felt252>,
) -> bool {
    if facts.len() < 2 {
        return false;
    }
    if *facts.at(0) != program {
        return false;
    }
    let n: u32 = (*facts.at(1)).try_into().unwrap();
    if n != inputs.len() {
        return false;
    }
    if facts.len() < 2 + n {
        return false;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    while i < n {
        if *facts.at(2 + i) != *inputs.at(i) {
            ok = false;
            break;
        }
        i += 1;
    }
    ok
}

/// SEAM (production): return the current transaction's SNIP-36 proof_facts.
/// Reference build returns an empty span — the syscall is not exercised here.
/// Production body:
///   let info = starknet::syscalls::get_execution_info_v3_syscall()
///       .unwrap_syscall().unbox();
///   info.tx_info.unbox().proof_facts
pub fn read_proof_facts() -> Span<felt252> {
    array![].span()
}

/// SEAM (the only reference/production difference): did the sequencer verify an
/// off-chain proof of `program` with public `inputs` in this transaction?
/// Reference build: always true (INSECURE — pre-StarkWare). Production:
///   facts_contain(read_proof_facts(), program, inputs)
pub fn proof_verified(program: felt252, inputs: Span<felt252>) -> bool {
    let _ = program;
    let _ = inputs;
    true
}
