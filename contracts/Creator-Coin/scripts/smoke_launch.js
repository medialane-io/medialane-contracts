// Creator Coin — team smoke launch (Ekubo). Atomic multicall: create -> fund Factory -> launch.
// Read-only/plan by default; set CONFIRM=1 to broadcast. Run with: bun scripts/smoke_launch.js
// (uses dapp's starknet.js v8.9.2 + Lava RPC + medialane-deployer key from the accounts file)
const fs = require('fs');
const SJS = '/Users/medialane/dev/medialane-dapp/node_modules/starknet';
const { RpcProvider, Account, json, hash, num, shortString, uint256, CallData } = require(SJS);

const RPC = 'https://rpc.starknet.lava.build/';
const ACCOUNTS = '/Users/medialane/.starknet_accounts/starknet_open_zeppelin_accounts.json';
const TARGET = '/Users/medialane/dev/medialane-contracts/contracts/Creator-Coin/target/dev';

const FACTORY  = '0x50fa807b5274079fb19374673d7bab6d2dc3af7e1032ea43eb6e44bcbde4c3c';
const CC_CLASS = '0x743e4c8a5b96bb83bbf4af04edbbb482d5ece89eed9b729a79fb7df0cd0b6b6';
const STRK     = '0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d';

// --- economics (tiny throwaway) ---
const NAME = 'SmokeTest', SYMBOL = 'SMOKE';
const SUPPLY      = 1000n * 10n ** 18n;   // 1,000 coins
const TEAM_AMOUNT = 10n   * 10n ** 18n;   // 10 coins (1%) to the owner
const QUOTE_FUND  = 15n   * 10n ** 16n;   // 0.15 STRK to Factory (buyback ~0.1, leftover returned)
// --- validated Ekubo params (from passing fork test: 0.01 quote/coin) ---
const EK = { fee:'0xc49ba5e353f7d00000000000000000', tick_spacing:'5982', sp_mag:'4600158', sp_sign:'1', bound:'88719042' };
const RESTRICTION_DELAY = '0', MAX_PCT_BUY = '200'; // 2% (>= 0.5% min)

const u256 = (v) => { const x = uint256.bnToUint256(v); return [x.low, x.high]; };

(async () => {
  const acct = json.parse(fs.readFileSync(ACCOUNTS,'ascii'))['alpha-mainnet']['medialane-deployer'];
  const owner = acct.address;
  const provider = new RpcProvider({ nodeUrl: RPC });
  const account = new Account({ provider, address: owner, signer: acct.private_key, cairoVersion: '1' });

  const salt = '0x' + Date.now().toString(16);
  const nameF = shortString.encodeShortString(NAME);
  const symF  = shortString.encodeShortString(SYMBOL);

  // precompute the coin address (deploy_syscall from_zero=false -> deployer = Factory)
  const ctor = [owner, nameF, symF, ...u256(SUPPLY)];
  const coin = hash.calculateContractAddressFromHash(salt, CC_CLASS, ctor, FACTORY);

  const calls = [
    { contractAddress: FACTORY, entrypoint: 'create_creator_coin', calldata: [owner, nameF, symF, ...u256(SUPPLY), salt] },
    { contractAddress: STRK,    entrypoint: 'transfer',            calldata: [FACTORY, ...u256(QUOTE_FUND)] },
    { contractAddress: FACTORY, entrypoint: 'launch_on_ekubo',     calldata: [
        coin, RESTRICTION_DELAY, MAX_PCT_BUY, STRK,
        '1', owner,                       // initial_holders
        '1', ...u256(TEAM_AMOUNT),        // initial_holders_amounts
        EK.fee, EK.tick_spacing, EK.sp_mag, EK.sp_sign, EK.bound ] },
  ];

  console.log('PLAN: create', NAME, '(', (SUPPLY/10n**18n).toString(), 'supply ) -> fund', (Number(QUOTE_FUND)/1e18), 'STRK -> launch @ 0.01 STRK/coin');
  console.log('precomputed coin address:', coin);
  if (process.env.CONFIRM !== '1') { console.log('\nDRY RUN (set CONFIRM=1 to broadcast). Not sent.'); return; }

  console.log('\nBroadcasting atomic multicall ...');
  const { transaction_hash } = await account.execute(calls);
  console.log('tx:', transaction_hash);
  const r = await provider.waitForTransaction(transaction_hash);
  console.log('status:', r.execution_status ?? r.finality_status);
  console.log('\nSMOKE LAUNCH DONE. coin:', coin);
})().catch(e => { console.log('SMOKE LAUNCH ERROR:', String(e.message||e).slice(0,800)); process.exit(1); });
