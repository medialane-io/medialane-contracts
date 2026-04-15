/**
 * compute_signatures.mjs
 *
 * Computes SNIP-12 (revision 1 / Poseidon) typed-data signatures for the
 * Medialane1155 test suite.
 *
 * Outputs:
 *   - Public keys to paste into tests/tests.cairo (setup_accounts)
 *   - Signature arrays to paste into erc20_erc1155_order_signature(),
 *     erc20_erc1155_fulfillment_signature(), and erc20_erc1155_cancel_signature()
 *
 * Run:
 *   node --experimental-vm-modules scripts/compute_signatures.mjs
 * or
 *   node scripts/compute_signatures.mjs
 */

import { ec, typedData, num, hash } from '/Users/medialane/dev/medialane-io/node_modules/starknet/dist/index.js';

// ---------------------------------------------------------------------------
// Test private keys (simple known values; public keys derived below)
// ---------------------------------------------------------------------------
const OFFERER_PRIVATE_KEY  = '0x1a2b3c4d5e6f';
const FULFILLER_PRIVATE_KEY = '0xdeadbeef1234';

// ---------------------------------------------------------------------------
// Fixed contract addresses (from deploy_at in tests/tests.cairo)
// ---------------------------------------------------------------------------
const MEDIALANE_ADDRESS = '0x2a0626d1a71fab6c6cdcb262afc48bff92a6844700ebbd16297596e6c53da29';
const ERC20_ADDRESS     = '0x0589edc6e13293530fec9cad58787ed8cff1fce35c3ef80342b7b00651e04d1f';
const ERC1155_ADDRESS   = '0x07ca2d381f55b159ea4c80abf84d4343fde9989854a6be2f02585daae7d89d76';

// Fixed account addresses (from setup_accounts in tests/tests.cairo)
const OFFERER_ADDRESS   = '0x040204472aef47d0aa8d68316e773f09a6f7d8d10ff6d30363b353ef3f2d1305';
const FULFILLER_ADDRESS = '0x01d0c57c28e34bf6407c2fbfadbda7ae59d39ff9c8f9ac4ec3fa32ec784fb549';

// ---------------------------------------------------------------------------
// Chain ID read from snforge test env (probe_chain_id_and_order_hash test)
// ---------------------------------------------------------------------------
const CHAIN_ID_DECIMAL = 393402133025997798000961n;
const CHAIN_ID_HEX     = num.toHex(CHAIN_ID_DECIMAL);

// ---------------------------------------------------------------------------
// Derive public keys
// ---------------------------------------------------------------------------
function getStarkPublicKey(privateKeyHex) {
  // starkCurve.getPublicKey returns uncompressed point; we want the x-coordinate
  const fullPub = ec.starkCurve.getPublicKey(privateKeyHex, false);
  // fullPub is a Uint8Array: [0x04, x (32 bytes), y (32 bytes)]
  const xBytes = fullPub.slice(1, 33);
  return '0x' + Buffer.from(xBytes).toString('hex');
}

const offererPubKey   = getStarkPublicKey(OFFERER_PRIVATE_KEY);
const fulfillerPubKey = getStarkPublicKey(FULFILLER_PRIVATE_KEY);

// ---------------------------------------------------------------------------
// SNIP-12 domain (revision 1 = Poseidon)
// ---------------------------------------------------------------------------
const domain = {
  name:     'Medialane1155',
  version:  '1',
  chainId:  CHAIN_ID_HEX,
  revision: '1',
};

// ---------------------------------------------------------------------------
// Type definitions
// ---------------------------------------------------------------------------
const allTypes = {
  StarknetDomain: [
    { name: 'name',     type: 'shortstring' },
    { name: 'version',  type: 'shortstring' },
    { name: 'chainId',  type: 'shortstring' },
    { name: 'revision', type: 'shortstring' },
  ],
  OrderParameters: [
    { name: 'offerer',        type: 'ContractAddress' },
    { name: 'nft_contract',   type: 'ContractAddress' },
    { name: 'token_id',       type: 'felt' },
    { name: 'amount',         type: 'felt' },
    { name: 'payment_token',  type: 'ContractAddress' },
    { name: 'price_per_unit', type: 'felt' },
    { name: 'start_time',     type: 'felt' },
    { name: 'end_time',       type: 'felt' },
    { name: 'salt',           type: 'felt' },
    { name: 'nonce',          type: 'felt' },
  ],
  OrderFulfillment: [
    { name: 'order_hash', type: 'felt' },
    { name: 'fulfiller',  type: 'ContractAddress' },
    { name: 'nonce',      type: 'felt' },
  ],
  OrderCancellation: [
    { name: 'order_hash', type: 'felt' },
    { name: 'offerer',    type: 'ContractAddress' },
    { name: 'nonce',      type: 'felt' },
  ],
};

// ---------------------------------------------------------------------------
// Order parameters (matching default_order_params in tests/tests.cairo)
// ---------------------------------------------------------------------------
const orderMessage = {
  offerer:        OFFERER_ADDRESS,
  nft_contract:   ERC1155_ADDRESS,
  token_id:       '1',
  amount:         '10',
  payment_token:  ERC20_ADDRESS,
  price_per_unit: '1000000',
  start_time:     '1000000000',
  end_time:       '1000003600',
  salt:           '0',
  nonce:          '0',
};

// ---------------------------------------------------------------------------
// Compute order hash and verify it matches the on-chain value
// ---------------------------------------------------------------------------
const orderTypedData = {
  domain,
  types: { StarknetDomain: allTypes.StarknetDomain, OrderParameters: allTypes.OrderParameters },
  primaryType: 'OrderParameters',
  message: orderMessage,
};

const computedOrderHash = typedData.getMessageHash(orderTypedData, OFFERER_ADDRESS);

const EXPECTED_ORDER_HASH = '3110670139233262231903000756360861682602290397471925822924889523112288324268';

console.log('\n=== Order Hash Verification ===');
console.log('Computed :', computedOrderHash);
console.log('Expected :', '0x' + BigInt(EXPECTED_ORDER_HASH).toString(16));
console.log('Match    :', BigInt(computedOrderHash) === BigInt(EXPECTED_ORDER_HASH));

// ---------------------------------------------------------------------------
// Fulfillment hash
// ---------------------------------------------------------------------------
const fulfillmentMessage = {
  order_hash: computedOrderHash,
  fulfiller:  FULFILLER_ADDRESS,
  nonce:      '0',
};

const fulfillmentTypedData = {
  domain,
  types: { StarknetDomain: allTypes.StarknetDomain, OrderFulfillment: allTypes.OrderFulfillment },
  primaryType: 'OrderFulfillment',
  message: fulfillmentMessage,
};

const fulfillmentHash = typedData.getMessageHash(fulfillmentTypedData, FULFILLER_ADDRESS);

// ---------------------------------------------------------------------------
// Cancellation hash
// ---------------------------------------------------------------------------
const cancellationMessage = {
  order_hash: computedOrderHash,
  offerer:    OFFERER_ADDRESS,
  nonce:      '0',
};

const cancellationTypedData = {
  domain,
  types: { StarknetDomain: allTypes.StarknetDomain, OrderCancellation: allTypes.OrderCancellation },
  primaryType: 'OrderCancellation',
  message: cancellationMessage,
};

const cancellationHash = typedData.getMessageHash(cancellationTypedData, OFFERER_ADDRESS);

// ---------------------------------------------------------------------------
// Sign all three hashes
// ---------------------------------------------------------------------------
function sign(privateKeyHex, msgHash) {
  const sig = ec.starkCurve.sign(msgHash, privateKeyHex);
  return { r: num.toHex(sig.r), s: num.toHex(sig.s) };
}

const orderSig        = sign(OFFERER_PRIVATE_KEY,   computedOrderHash);
const fulfillmentSig  = sign(FULFILLER_PRIVATE_KEY, fulfillmentHash);
const cancellationSig = sign(OFFERER_PRIVATE_KEY,   cancellationHash);

// ---------------------------------------------------------------------------
// Verify signatures locally before printing
// ---------------------------------------------------------------------------
function verify(privateKeyHex, msgHash, r, s) {
  // Use the full uncompressed public key for verification (noble-starknet expects it)
  try {
    const fullPubKey = ec.starkCurve.getPublicKey(privateKeyHex, false);
    return ec.starkCurve.verify({ r: BigInt(r), s: BigInt(s) }, msgHash, fullPubKey);
  } catch (e) {
    return false;
  }
}

const orderOk        = verify(OFFERER_PRIVATE_KEY,   computedOrderHash, orderSig.r, orderSig.s);
const fulfillmentOk  = verify(FULFILLER_PRIVATE_KEY, fulfillmentHash,   fulfillmentSig.r, fulfillmentSig.s);
const cancellationOk = verify(OFFERER_PRIVATE_KEY,   cancellationHash,  cancellationSig.r, cancellationSig.s);

console.log('\n=== Signature Verification ===');
console.log('Order sig valid       :', orderOk);
console.log('Fulfillment sig valid :', fulfillmentOk);
console.log('Cancellation sig valid:', cancellationOk);

// ---------------------------------------------------------------------------
// Output: Cairo code to paste
// ---------------------------------------------------------------------------
console.log('\n=== Paste into tests/tests.cairo: setup_accounts() ===');
console.log(`
    fn setup_accounts() -> Accounts {
        let offerer_pub_key: ContractAddress =
            ${offererPubKey}
            .try_into()
            .unwrap();
        let offerer_address: ContractAddress =
            0x040204472aef47d0aa8d68316e773f09a6f7d8d10ff6d30363b353ef3f2d1305
            .try_into()
            .unwrap();
        let offerer = deploy_account(offerer_pub_key, offerer_address);

        let fulfiller_pub_key: ContractAddress =
            ${fulfillerPubKey}
            .try_into()
            .unwrap();
        let fulfiller_address: ContractAddress =
            0x01d0c57c28e34bf6407c2fbfadbda7ae59d39ff9c8f9ac4ec3fa32ec784fb549
            .try_into()
            .unwrap();
        let fulfiller = deploy_account(fulfiller_pub_key, fulfiller_address);
        ...
    }
`);

console.log('=== Paste into tests/tests.cairo: signature functions ===');
console.log(`
    fn erc20_erc1155_order_signature() -> Array<felt252> {
        array![
            ${orderSig.r},
            ${orderSig.s},
        ]
    }

    fn erc20_erc1155_fulfillment_signature() -> Array<felt252> {
        array![
            ${fulfillmentSig.r},
            ${fulfillmentSig.s},
        ]
    }

    fn erc20_erc1155_cancel_signature() -> Array<felt252> {
        array![
            ${cancellationSig.r},
            ${cancellationSig.s},
        ]
    }
`);

console.log('\n=== Raw values ===');
console.log('chain_id hex         :', CHAIN_ID_HEX);
console.log('offerer pub key      :', offererPubKey);
console.log('fulfiller pub key    :', fulfillerPubKey);
console.log('order hash           :', computedOrderHash);
console.log('fulfillment hash     :', fulfillmentHash);
console.log('cancellation hash    :', cancellationHash);
console.log('order sig r          :', orderSig.r);
console.log('order sig s          :', orderSig.s);
console.log('fulfillment sig r    :', fulfillmentSig.r);
console.log('fulfillment sig s    :', fulfillmentSig.s);
console.log('cancellation sig r   :', cancellationSig.r);
console.log('cancellation sig s   :', cancellationSig.s);
