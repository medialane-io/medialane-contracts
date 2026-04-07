const hre = require("hardhat");

// Medialane DAO Gnosis Safe (3-of-5 multisig) — receives all MDLN at deploy
const TREASURY = "0xA7603783edD8ee6FF4B085f90Af53341282d244C";

const TOTAL_SUPPLY    = hre.ethers.parseUnits("21000000",  18); // 21M MDLN
const VESTING_DEPOSIT = hre.ethers.parseUnits("18900000",  18); // 18.9M — locked in vesting

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("=== Medialane MDLN Deploy ===");
  console.log("Deployer :", deployer.address);
  console.log("Treasury :", TREASURY);
  console.log("Network  :", hre.network.name);
  console.log("Balance  :", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH\n");

  // ── 1. Deploy MDLN token ──────────────────────────────────────────────────
  console.log("1. Deploying MedialaneToken...");
  const Token = await hre.ethers.getContractFactory("MedialaneToken");
  const token = await Token.deploy(TREASURY);
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log("   MDLN:", tokenAddress);

  // ── 2. Deploy vesting contract ────────────────────────────────────────────
  console.log("2. Deploying MDLNVesting...");
  const Vesting = await hre.ethers.getContractFactory("MDLNVesting");
  const vesting = await Vesting.deploy(tokenAddress, TREASURY);
  await vesting.waitForDeployment();
  const vestingAddress = await vesting.getAddress();
  console.log("   Vesting:", vestingAddress);

  // ── 3. Verify supply ──────────────────────────────────────────────────────
  const safeBalance = await token.balanceOf(TREASURY);
  console.log("\n3. Supply check:");
  console.log("   Safe holds:", hre.ethers.formatUnits(safeBalance, 18), "MDLN");
  console.log("   Expected  :", hre.ethers.formatUnits(TOTAL_SUPPLY, 18), "MDLN");

  // ── 4. Instructions for Gnosis Safe ───────────────────────────────────────
  console.log("\n=== ACTION REQUIRED (from Gnosis Safe) ===");
  console.log("Transfer 18,900,000 MDLN from the Safe to the vesting contract:");
  console.log("  To     :", vestingAddress);
  console.log("  Amount : 18900000000000000000000000 (18.9M with 18 decimals)");
  console.log("  Safe retains 2,100,000 MDLN as operational runway.\n");

  // ── 5. Verification commands ──────────────────────────────────────────────
  console.log("=== Etherscan Verification ===");
  console.log(`npx hardhat verify --network ${hre.network.name} ${tokenAddress} "${TREASURY}"`);
  console.log(`npx hardhat verify --network ${hre.network.name} ${vestingAddress} "${tokenAddress}" "${TREASURY}"`);

  console.log("\n=== Next Steps ===");
  console.log("1. Execute Gnosis Safe transfer above.");
  console.log("2. Verify both contracts on Etherscan.");
  console.log("3. Register MDLN on StarkGate for L2 bridging.");
  console.log("4. Create Snapshot space at https://snapshot.org");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
