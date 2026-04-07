const { ethers } = require("ethers");

const wallet = ethers.Wallet.createRandom();

console.log("=== New Deployer Wallet ===");
console.log("Address    :", wallet.address);
console.log("Private Key:", wallet.privateKey);
console.log("Mnemonic   :", wallet.mnemonic.phrase);
console.log("\nSave the private key in contracts/MDLN/.env as DEPLOYER_PRIVATE_KEY");
console.log("Fund this address with Sepolia ETH before deploying.");
console.log("\nFaucets:");
console.log("  https://sepoliafaucet.com");
console.log("  https://faucet.quicknode.com/ethereum/sepolia");
