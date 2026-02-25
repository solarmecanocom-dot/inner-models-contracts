/**
 * Deploy only PoolManager, linking to an existing NFT contract.
 */
const hre = require("hardhat");

const NFT_ADDRESS = "0xB032B7053138cedFB3d948Ab5Beeb42eA0549195";

const MODEL_TIERS = [
  0, 0, 1, 1, 1, 2, 3, 1, 2, 0,
  1, 2, 2,
  0, 1, 1, 1, 2, 3,
  1, 0, 1, 0, 0,
];

function buildTierAssignments() {
  const tiers = [];
  for (const modelTier of MODEL_TIERS) {
    for (let q = 0; q < 11; q++) {
      tiers.push(modelTier);
    }
  }
  if (tiers.length !== 264) throw new Error(`Expected 264 tiers, got ${tiers.length}`);
  return tiers;
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying PoolManager with:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");
  console.log("NFT address:", NFT_ADDRESS);

  const priceFeedAddr = "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70";
  const sequencerFeedAddr = "0xBCF85224fC0756b9fA45AAb7d157a8263913fDa1";

  const tierAssignments = buildTierAssignments();

  const Pool = await hre.ethers.getContractFactory("PoolManager");
  const pool = await Pool.deploy(
    NFT_ADDRESS,
    priceFeedAddr,
    sequencerFeedAddr,
    deployer.address,
    tierAssignments
  );
  await pool.waitForDeployment();
  const poolAddr = await pool.getAddress();
  console.log("PoolManager:", poolAddr);

  // Link NFT to PoolManager
  console.log("Linking NFT to PoolManager...");
  const nft = await hre.ethers.getContractAt("InnerModelsNFT", NFT_ADDRESS);
  const linkTx = await nft.setPoolManager(poolAddr);
  await linkTx.wait();
  console.log("NFT linked to PoolManager");

  console.log("\n" + "=".repeat(50));
  console.log("DEPLOYMENT COMPLETE");
  console.log("=".repeat(50));
  console.log(`InnerModelsNFT:   ${NFT_ADDRESS}`);
  console.log(`PoolManager:      ${poolAddr}`);
  console.log("=".repeat(50));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
