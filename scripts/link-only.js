const hre = require("hardhat");

async function main() {
  const NFT_ADDRESS = "0xB032B7053138cedFB3d948Ab5Beeb42eA0549195";
  const POOL_ADDRESS = "0x3FC012583Ccec0B7f55708e193710b2f533F054e";

  const [deployer] = await hre.ethers.getSigners();
  console.log("Linking with:", deployer.address);

  const nft = await hre.ethers.getContractAt("InnerModelsNFT", NFT_ADDRESS);

  // Check current poolManager
  const current = await nft.poolManager();
  console.log("Current poolManager:", current);

  if (current !== "0x0000000000000000000000000000000000000000") {
    console.log("Already linked!");
    return;
  }

  const tx = await nft.setPoolManager(POOL_ADDRESS);
  console.log("TX hash:", tx.hash);
  await tx.wait();
  console.log("NFT linked to PoolManager!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
