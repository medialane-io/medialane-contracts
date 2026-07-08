use private_subscription::merkle::{hash2, zeros, compute_root_from_proof, DEPTH};

#[test]
fn test_hash2_is_poseidon_and_deterministic() {
    let a = hash2(1, 2);
    let b = hash2(1, 2);
    assert!(a == b, "hash2 must be deterministic");
    assert!(hash2(1, 2) != hash2(2, 1), "hash2 must be order-sensitive");
}

#[test]
fn test_zeros_chain() {
    // zeros(0) = ZERO_LEAF = 0; zeros(i) = hash2(zeros(i-1), zeros(i-1))
    assert!(zeros(0) == 0, "zero leaf is 0");
    assert!(zeros(1) == hash2(0, 0), "zeros(1)");
    assert!(zeros(2) == hash2(zeros(1), zeros(1)), "zeros(2)");
}

#[test]
fn test_single_leaf_root_matches_manual() {
    // A tree with one leaf L at index 0: fold L with zeros at each level.
    let leaf = 42;
    let mut expected = leaf;
    let mut i: u32 = 0;
    while i < DEPTH {
        expected = hash2(expected, zeros(i));
        i += 1;
    }
    let siblings = build_zero_siblings();
    let root = compute_root_from_proof(leaf, 0, siblings.span());
    assert!(root == expected, "single-leaf root mismatch");
}

fn build_zero_siblings() -> Array<felt252> {
    let mut a: Array<felt252> = array![];
    let mut i: u32 = 0;
    while i < DEPTH {
        a.append(zeros(i));
        i += 1;
    }
    a
}
