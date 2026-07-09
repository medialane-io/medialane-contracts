import "dotenv/config";
import * as fs from "fs";
import * as path from "path";
import colors from "colors";
import { fileURLToPath } from "url";
import { json } from "starknet";
import { getNetwork, getAccount } from "./network.js";
import { getEkuboConfig } from "./exchange.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const TARGET_PATH = path.join(__dirname, "..", "..", "target", "dev");

// SupportedExchanges enum: a single `Ekubo` variant (index 0).
const SUPPORTED_EXCHANGE_EKUBO = "0";

const getContracts = () => {
  if (!fs.existsSync(TARGET_PATH)) {
    throw new Error(`Target directory not found at path: ${TARGET_PATH}`);
  }
  const contracts = fs
    .readdirSync(TARGET_PATH)
    .filter((contract) => contract.includes(".contract_class.json"));
  if (contracts.length === 0) {
    throw new Error("No build files found. Run `scarb build` first");
  }
  return contracts;
};

const getContractPath = (namePart, label) => {
  const contracts = getContracts();
  const match = contracts.find((contract) => contract.includes(namePart));
  if (!match) {
    throw new Error(`${label} contract not found. Run scarb build first`);
  }
  return path.join(TARGET_PATH, match);
};

const getCreatorCoinPath = () => getContractPath("CreatorCoin", "CreatorCoin");
const getEkuboLauncherPath = () => getContractPath("EkuboLauncher", "EkuboLauncher");
const getFactoryPath = () => getContractPath("Factory", "Factory");

const declare = async (filepath, contract_name) => {
  console.log(`\nDeclaring ${contract_name}...`.magenta);
  const compiledSierraCasm = filepath.replace(
    ".contract_class.json",
    ".compiled_contract_class.json",
  );
  const compiledFile = json.parse(fs.readFileSync(filepath).toString("ascii"));
  const compiledSierraCasmFile = json.parse(
    fs.readFileSync(compiledSierraCasm).toString("ascii"),
  );
  const account = getAccount();
  const contract = await account.declareIfNot({
    contract: compiledFile,
    casm: compiledSierraCasmFile,
  });

  const network = getNetwork(process.env.STARKNET_NETWORK);
  console.log(`- Class Hash: `.magenta, `${contract.class_hash}`);
  if (contract.transaction_hash) {
    console.log(
      "- Tx Hash: ".magenta,
      `${network.explorer_url}/tx/${contract.transaction_hash})`,
    );
    await account.waitForTransaction(contract.transaction_hash);
  } else {
    console.log("- Tx Hash: ".magenta, "Already declared");
  }

  return contract;
};

export const deployEkuboLauncher = async () => {
  const account = getAccount();
  const ekubo = getEkuboConfig(process.env.STARKNET_NETWORK);

  const launcher = await declare(getEkuboLauncherPath(), "EkuboLauncher");

  console.log(`\nDeploying EkuboLauncher...`.green);
  const contract = await account.deployContract({
    classHash: launcher.class_hash,
    // constructor(core, registry, positions, router)
    constructorCalldata: [ekubo.core, ekubo.registry, ekubo.positions, ekubo.router],
  });

  const network = getNetwork(process.env.STARKNET_NETWORK);
  console.log(
    "Tx hash: ".green,
    `${network.explorer_url}/tx/${contract.transaction_hash})`,
  );
  await account.waitForTransaction(contract.transaction_hash);
  console.log("EkuboLauncher: ".green, contract.address);
  return contract.address;
};

export const deployFactory = async (ekuboLauncherAddress) => {
  const account = getAccount();

  // Declare contracts
  const creatorCoin = await declare(getCreatorCoinPath(), "CreatorCoin");
  const factory = await declare(getFactoryPath(), "Factory");

  console.log(`\nDeploying Factory...`.green);
  console.log("CreatorCoin class hash: ".green, creatorCoin.class_hash);
  console.log("EkuboLauncher: ".green, ekuboLauncherAddress);

  const contract = await account.deployContract({
    classHash: factory.class_hash,
    // constructor(creator_coin_class_hash, exchanges: Span<(SupportedExchanges, ContractAddress)>)
    constructorCalldata: [
      creatorCoin.class_hash,
      "1", // exchanges span length
      SUPPORTED_EXCHANGE_EKUBO,
      ekuboLauncherAddress,
    ],
  });

  const network = getNetwork(process.env.STARKNET_NETWORK);
  console.log(
    "Tx hash: ".green,
    `${network.explorer_url}/tx/${contract.transaction_hash})`,
  );
  await account.waitForTransaction(contract.transaction_hash);
  console.log("Factory: ".green, contract.address);
};
