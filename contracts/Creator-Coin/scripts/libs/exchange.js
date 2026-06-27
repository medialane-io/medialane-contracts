// Canonical Ekubo infrastructure addresses used to deploy the EkuboLauncher.
// The launcher is deployed by the script; the Factory is then configured with it
// as its only exchange.
const EKUBO = {
  mainnet: {
    core: "0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b",
    positions:
      "0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067",
    registry:
      "0x0013e25867b6eef62703735aa4cfa7754e72f4e94a56c9d3d9ad8ebe86cee4aa",
    router:
      "0x01b6f560def289b32e2a7b0920909615531a4d9d5636ca509045843559dc23d5",
  },
};

export const getEkuboConfig = (network) => {
  const config = EKUBO[network.toLowerCase()];
  if (!config) {
    throw new Error(`Ekubo config for network ${network} not found`);
  }
  return config;
};
