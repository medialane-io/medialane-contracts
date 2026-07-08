use private_subscription::proof_facts::{facts_contain, proof_verified};

// Encoding under test: facts = [program, n, input_0, .., input_{n-1}, ...more records].
#[test]
fn test_facts_contain_matches_program_and_inputs() {
    let facts = array![777, 3, 10, 20, 30].span();
    assert!(facts_contain(facts, 777, array![10, 20, 30].span()), "should match");
}

#[test]
fn test_facts_contain_rejects_wrong_program() {
    let facts = array![777, 3, 10, 20, 30].span();
    assert!(!facts_contain(facts, 888, array![10, 20, 30].span()), "wrong program");
}

#[test]
fn test_facts_contain_rejects_wrong_input() {
    let facts = array![777, 3, 10, 20, 30].span();
    assert!(!facts_contain(facts, 777, array![10, 20, 99].span()), "wrong input");
}

#[test]
fn test_facts_contain_rejects_wrong_length() {
    let facts = array![777, 2, 10, 20].span();
    assert!(!facts_contain(facts, 777, array![10, 20, 30].span()), "wrong length");
}

#[test]
fn test_reference_proof_verified_is_true() {
    // Reference build: the seam is permissive. This is INSECURE by design and
    // exists only until STRK20/SNIP-36 lands. Production flips this branch.
    assert!(proof_verified(777, array![1, 2].span()), "reference build permits");
}
