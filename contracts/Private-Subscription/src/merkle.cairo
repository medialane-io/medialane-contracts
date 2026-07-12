use core::poseidon::PoseidonTrait;
use core::hash::HashStateTrait;

pub const DEPTH: u32 = 20;

pub fn hash2(left: felt252, right: felt252) -> felt252 {
    PoseidonTrait::new().update(left).update(right).finalize()
}

/// zeros(0) = 0 (empty leaf); zeros(i) = hash2(zeros(i-1), zeros(i-1)).
pub fn zeros(level: u32) -> felt252 {
    let mut z: felt252 = 0;
    let mut i: u32 = 0;
    while i < level {
        z = hash2(z, z);
        i += 1;
    }
    z
}

/// Recomputes the root implied by a Merkle authentication path.
/// `leaf_index` selects left/right at each level; `siblings[i]` is the sibling
/// hash at level `i`. Length of `siblings` must equal `DEPTH`.
pub fn compute_root_from_proof(
    leaf: felt252, leaf_index: u64, siblings: Span<felt252>,
) -> felt252 {
    let mut current = leaf;
    let mut idx = leaf_index;
    let mut i: u32 = 0;
    while i < DEPTH {
        let sibling = *siblings.at(i);
        current =
            if idx % 2 == 0 {
                hash2(current, sibling)
            } else {
                hash2(sibling, current)
            };
        idx = idx / 2;
        i += 1;
    }
    current
}
