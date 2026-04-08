const hre = require("hardhat");

// ── Config ───────────────────────────────────────────────────────────────────
const MDLN_L1        = "0x0DC90d57F3Aa3E836Ffd6E777E543a43A487dB15";
const STARKGATE_BRIDGE = "0xF5b6Ee2CAEb6769659f6C091D209DfdCaF3F69Eb";

// !! Set these before running !!
// L2 recipient: your Starknet wallet address (as a uint256 felt)
const L2_RECIPIENT   = process.env.L2_RECIPIENT   ?? "";
// Amount to bridge in MDLN (human-readable, e.g. "1000" = 1000 MDLN)
const BRIDGE_AMOUNT  = process.env.BRIDGE_AMOUNT  ?? "";

const BRIDGE_ABI = [
  "function estimateDepositFeeWei() external view returns (uint256)",
  "function deposit(address token, uint256 amount, uint256 l2Recipient) external payable",
  "function depositWithMessage(address token, uint256 amount, uint256 l2Recipient, bytes calldata message) external payable",
];
const ERC20_ABI = [
  "function balanceOf(address) external view returns (uint256)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)",
];

async function main() {
  // ── Validate inputs ─────────────────────────────────────────────────────
  if (!L2_RECIPIENT || !BRIDGE_AMOUNT) {
    console.error("Usage:");
    console.error("  L2_RECIPIENT=0x<starknet_address> BRIDGE_AMOUNT=<mdln_amount> npx hardhat run scripts/bridge-to-starknet.js --network mainnet");
    console.error("");
    console.error("Example (bridge 100 MDLN to your Starknet wallet):");
    console.error('  L2_RECIPIENT=0x04cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b BRIDGE_AMOUNT=100 npx hardhat run scripts/bridge-to-starknet.js --network mainnet');
    process.exit(1);
  }

  const [deployer] = await hre.ethers.getSigners();
  const provider   = hre.ethers.provider;

  const amount = hre.ethers.parseUnits(BRIDGE_AMOUNT, 18);

  console.log("=== Bridge MDLN → Starknet ===");
  console.log("Network      :", hre.network.name);
  console.log("From (L1)    :", deployer.address);
  console.log("To (L2)      :", L2_RECIPIENT);
  console.log("Amount       :", BRIDGE_AMOUNT, "MDLN");
  console.log("ETH balance  :", hre.ethers.formatEther(await provider.getBalance(deployer.address)), "ETH\n");

  const bridge = new hre.ethers.Contract(STARKGATE_BRIDGE, BRIDGE_ABI, deployer);
  const token  = new hre.ethers.Contract(MDLN_L1, ERC20_ABI, deployer);

  // ── Check MDLN balance ───────────────────────────────────────────────────
  const balance = await token.balanceOf(deployer.address);
  console.log("MDLN balance :", hre.ethers.formatUnits(balance, 18), "MDLN");
  if (balance < amount) {
    throw new Error(`Insufficient MDLN. Have ${hre.ethers.formatUnits(balance, 18)}, need ${BRIDGE_AMOUNT}`);
  }

  // ── Estimate bridge fee ──────────────────────────────────────────────────
  console.log("\n1. Estimating deposit fee...");
  const fee = await bridge.estimateDepositFeeWei();
  const feeWithBuffer = fee * 120n / 100n;
  console.log("   Fee (exact) :", hre.ethers.formatEther(fee), "ETH");
  console.log("   Fee (+20%)  :", hre.ethers.formatEther(feeWithBuffer), "ETH");

  const ethBalance = await provider.getBalance(deployer.address);
  if (ethBalance < feeWithBuffer) {
    throw new Error(`Insufficient ETH for bridge fee. Need ${hre.ethers.formatEther(feeWithBuffer)} ETH`);
  }

  // ── Approve bridge to spend MDLN ─────────────────────────────────────────
  const allowance = await token.allowance(deployer.address, STARKGATE_BRIDGE);
  if (allowance < amount) {
    console.log("\n2. Approving bridge to spend", BRIDGE_AMOUNT, "MDLN...");
    const approveTx = await token.approve(STARKGATE_BRIDGE, amount);
    console.log("   Approve tx:", approveTx.hash);
    await approveTx.wait();
    console.log("   Approved ✓");
  } else {
    console.log("\n2. Allowance already sufficient ✓");
  }

  // ── Deposit ──────────────────────────────────────────────────────────────
  console.log("\n3. Depositing", BRIDGE_AMOUNT, "MDLN to Starknet...");
  const depositTx = await bridge.deposit(
    MDLN_L1,
    amount,
    L2_RECIPIENT,
    { value: feeWithBuffer }
  );
  console.log("   Tx sent   :", depositTx.hash);
  console.log("   Waiting for confirmation...");

  const receipt = await depositTx.wait();
  console.log("\n=== Bridge Confirmed ===");
  console.log("Tx hash  :", receipt.hash);
  console.log("Block    :", receipt.blockNumber);
  console.log("Gas used :", receipt.gasUsed.toString());
  console.log("Status   :", receipt.status === 1 ? "SUCCESS ✓" : "FAILED ✗");

  console.log("\n=== What happens next ===");
  console.log("- L1→L2 message will be consumed by Starknet in ~5–15 minutes.");
  console.log("- MDLN will appear in your Starknet wallet at:");
  console.log("  Token :", "0x6730d6a357690cebffad800219e9630e15b6f44d35526e0fc9ee52bdf7418e8");
  console.log("  Check : https://voyager.online/contract/0x6730d6a357690cebffad800219e9630e15b6f44d35526e0fc9ee52bdf7418e8");
}

main().catch((err) => {
  console.error("\nError:", err.message ?? err);
  process.exitCode = 1;
});
