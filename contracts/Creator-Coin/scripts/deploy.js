import colors from "colors";
import { deployFactory, deployEkuboLauncher } from "./libs/contract.js";

const main = async () => {
  console.log(`   ____          _         `.red);
  console.log(`  |    \\ ___ ___| |___ _ _ `.red);
  console.log(`  |  |  | -_| . | | . | | |`.red);
  console.log(`  |____/|___|  _|_|___|_  |`.red);
  console.log(`            |_|       |___|`.red);

  // EkuboLauncher (holds the locked LP position; the Factory's only exchange)
  console.log(`\n${"Deploying EkuboLauncher contract".blue}`);
  const ekuboLauncherAddress = await deployEkuboLauncher();

  // Factory
  console.log(`\n${"Deploying Factory contract".blue}`);
  await deployFactory(ekuboLauncherAddress);
};

main();
