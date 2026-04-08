const hre = require("hardhat");

// ── Addresses ────────────────────────────────────────────────────────────────
const MDLN_TOKEN      = "0x0DC90d57F3Aa3E836Ffd6E777E543a43A487dB15";
const STARKGATE_MGR   = "0x0c5aE94f8939182F2D06097025324D1E537d5B60"; // enrollTokenBridge
const STARKGATE_BRIDGE= "0xF5b6Ee2CAEb6769659f6C091D209DfdCaF3F69Eb"; // estimateEnrollmentFeeWei
const STARKGATE_REG   = "0x1268cc171c54F2000402DfF20E93E60DF4c96812"; // getBridge

// Minimal ABIs — only what we need
const MANAGER_ABI = [
  "function enrollTokenBridge(address token) external payable",
];
const BRIDGE_ABI = [
  "function estimateEnrollmentFeeWei() external view returns (uint256)",
];
const REGISTRY_ABI = [
  "function getBridge(address token) external view returns (address)",
];

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const provider   = hre.ethers.provider;

  console.log("=== StarkGate MDLN Enrollment ===");
  console.log("Network  :", hre.network.name);
  console.log("Deployer :", deployer.address);

  const balance = await provider.getBalance(deployer.address);
  console.log("Balance  :", hre.ethers.formatEther(balance), "ETH\n");

  const manager  = new hre.ethers.Contract(STARKGATE_MGR,    MANAGER_ABI,  deployer);
  const bridge   = new hre.ethers.Contract(STARKGATE_BRIDGE, BRIDGE_ABI,   provider);
  const registry = new hre.ethers.Contract(STARKGATE_REG,    REGISTRY_ABI, provider);

  // ── 1. Check if already enrolled ─────────────────────────────────────────
  console.log("1. Checking enrollment status...");
  try {
    const existingBridge = await registry.getBridge(MDLN_TOKEN);
    const ZERO = "0x0000000000000000000000000000000000000000";
    if (existingBridge !== ZERO) {
      console.log("   MDLN is already enrolled.");
      console.log("   Bridge address:", existingBridge);
      console.log("\nNothing to do — MDLN bridge already exists on StarkGate.");
      return;
    }
    console.log("   Not yet enrolled. Proceeding...\n");
  } catch {
    // Registry reverts when token is unknown — treat as not enrolled
    console.log("   Not enrolled (registry returned no entry). Proceeding...\n");
  }

  // ── 2. Estimate enrollment fee ────────────────────────────────────────────
  console.log("2. Estimating enrollment fee...");
  const fee = await bridge.estimateEnrollmentFeeWei();
  // Add 20% buffer to account for gas price fluctuations during L1→L2 messaging
  const feeWithBuffer = fee * 120n / 100n;
  console.log("   Fee (exact) :", hre.ethers.formatEther(fee), "ETH");
  console.log("   Fee (+20%)  :", hre.ethers.formatEther(feeWithBuffer), "ETH\n");

  if (balance < feeWithBuffer) {
    throw new Error(
      `Insufficient ETH. Need ${hre.ethers.formatEther(feeWithBuffer)} ETH, have ${hre.ethers.formatEther(balance)} ETH.`
    );
  }

  // ── 3. Get current gas price ──────────────────────────────────────────────
  const feeData = await provider.getFeeData();
  console.log("3. Current gas:");
  console.log("   Base fee :", hre.ethers.formatUnits(feeData.gasPrice ?? 0n, "gwei"), "gwei\n");

  // ── 4. Enroll MDLN on StarkGate ──────────────────────────────────────────
  console.log("4. Enrolling MDLN on StarkGate...");
  console.log("   MDLN  :", MDLN_TOKEN);
  console.log("   Value :", hre.ethers.formatEther(feeWithBuffer), "ETH\n");

  const tx = await manager.enrollTokenBridge(MDLN_TOKEN, { value: feeWithBuffer });
  console.log("   Tx sent   :", tx.hash);
  console.log("   Waiting for confirmation...\n");

  const receipt = await tx.wait();
  console.log("=== Enrollment Confirmed ===");
  console.log("Tx hash       :", receipt.hash);
  console.log("Block         :", receipt.blockNumber);
  console.log("Gas used      :", receipt.gasUsed.toString());
  console.log("Status        :", receipt.status === 1 ? "SUCCESS" : "FAILED");

  console.log("\n=== Next Steps ===");
  console.log("1. Wait ~5 minutes for the L1→L2 message to be consumed on Starknet.");
  console.log("2. Find the MDLN L2 token address on Starkscan:");
  console.log("   https://starkscan.co — search for the tx hash or TokenEnrollmentInitiated event");
  console.log("3. Share the L2 MDLN address to update medialane.org bridge + Ekubo pool links.");
  console.log("4. (Optional) Submit to StarkGate UI listing:");
  console.log("   https://github.com/starknet-io/starkgate-frontend — open an issue with token details.");
}

main().catch((err) => {
  console.error("\nError:", err.message ?? err);
  process.exitCode = 1;
});
