require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  paths: {
    sources: "./src",
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "cancun",
    },
  },
  networks: {
    ...(process.env.ETH_RPC_URL && {
      mainnet: {
        url: process.env.ETH_RPC_URL,
        accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      },
    }),
    ...(process.env.ETH_SEPOLIA_RPC_URL && {
      sepolia: {
        url: process.env.ETH_SEPOLIA_RPC_URL,
        accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      },
    }),
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
