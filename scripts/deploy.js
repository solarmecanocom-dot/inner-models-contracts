/**
 * Deploy Inner Models contracts to Base (testnet or mainnet).
 *
 * Usage:
 *   npx hardhat run scripts/deploy.js --network baseSepolia
 *   npx hardhat run scripts/deploy.js --network base
 */

const hre = require("hardhat");

// ═══════════════════════════════════════════
//  Tier assignments: 24 models × 11 questions = 264 tokens
//  0 = Common (0.05 ETH), 1 = Standard (0.1 ETH), 2 = Rare (0.15 ETH), 3 = Legendary (0.2 ETH)
// ═══════════════════════════════════════════

const MODEL_TIERS = [
  0, // gpt-4o — Common
  0, // gpt-4.1 — Common
  1, // gpt-5 — Standard
  1, // gpt-5.1 — Standard
  1, // gpt-5.2 — Standard
  2, // gpt-5-pro — Rare
  3, // gpt-5.2-pro — Legendary
  1, // o1 — Standard
  2, // o3 — Rare
  0, // o4-mini — Common
  1, // grok-3 — Standard
  2, // grok-4 — Rare
  2, // grok-4.1 — Rare
  0, // gemini-2.0-flash — Common
  1, // gemini-2.5-flash — Standard
  1, // gemini-2.5-pro — Standard
  1, // gemini-3-flash — Standard
  2, // gemini-3-pro — Rare
  3, // gemini-3.1-pro — Legendary
  1, // mistral-large — Standard
  0, // mistral-medium — Common
  1, // magistral-medium — Standard
  0, // pixtral-large — Common
  0, // mistral-nemo — Common
];

function buildTierAssignments() {
  // Each model has 11 questions → 11 tokens at the same tier
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
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");

  // ═══════════════════════════════════════════
  //  Configuration per network
  // ═══════════════════════════════════════════

  const network = hre.network.name;
  let priceFeedAddr, sequencerFeedAddr;

  if (network === "base") {
    // Base Mainnet
    priceFeedAddr = "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70"; // Chainlink ETH/USD
    sequencerFeedAddr = "0xBCF85224fC0756b9fA45AAb7d157a8263913fDa1"; // L2 Sequencer Uptime Feed
  } else if (network === "baseSepolia") {
    // Base Sepolia — deploy mock oracles
    console.log("\n--- Deploying mock oracles for testnet ---");

    const MockAgg = await hre.ethers.getContractFactory("MockV3Aggregator");

    const priceFeed = await MockAgg.deploy(270000000000n); // $2,700
    await priceFeed.waitForDeployment();
    priceFeedAddr = await priceFeed.getAddress();
    console.log("MockPriceFeed:", priceFeedAddr);

    const sequencerFeed = await MockAgg.deploy(0); // Sequencer up
    await sequencerFeed.waitForDeployment();
    sequencerFeedAddr = await sequencerFeed.getAddress();
    console.log("MockSequencerFeed:", sequencerFeedAddr);
  } else {
    // Local hardhat — deploy mocks
    console.log("\n--- Deploying mock oracles for local ---");

    const MockAgg = await hre.ethers.getContractFactory("MockV3Aggregator");

    const priceFeed = await MockAgg.deploy(270000000000n);
    await priceFeed.waitForDeployment();
    priceFeedAddr = await priceFeed.getAddress();

    const sequencerFeed = await MockAgg.deploy(0);
    await sequencerFeed.waitForDeployment();
    sequencerFeedAddr = await sequencerFeed.getAddress();
  }

  // ═══════════════════════════════════════════
  //  Deploy NFT contract
  // ═══════════════════════════════════════════

  console.log("\n--- Deploying InnerModelsNFT ---");

  const baseURI = "ipfs://bafybeifggx3tyulmamlg6fvu6lmrszpotgernuptt2vcr7rri5xnllfg2a/metadata_ipfs/";
  const destroyedURI = "ipfs://bafybeifggx3tyulmamlg6fvu6lmrszpotgernuptt2vcr7rri5xnllfg2a/metadata_ipfs/destroyed.json";

  const NFT = await hre.ethers.getContractFactory("InnerModelsNFT");
  const nft = await NFT.deploy(baseURI, destroyedURI);
  await nft.waitForDeployment();
  const nftAddr = await nft.getAddress();
  console.log("InnerModelsNFT:", nftAddr);

  // ═══════════════════════════════════════════
  //  Deploy PoolManager
  // ═══════════════════════════════════════════

  console.log("\n--- Deploying PoolManager ---");

  const tierAssignments = buildTierAssignments();

  const Pool = await hre.ethers.getContractFactory("PoolManager");
  const pool = await Pool.deploy(
    nftAddr,
    priceFeedAddr,
    sequencerFeedAddr,
    deployer.address, // creator
    tierAssignments
  );
  await pool.waitForDeployment();
  const poolAddr = await pool.getAddress();
  console.log("PoolManager:", poolAddr);

  // ═══════════════════════════════════════════
  //  Link NFT to PoolManager
  // ═══════════════════════════════════════════

  console.log("\n--- Linking NFT to PoolManager ---");
  const linkTx = await nft.setPoolManager(poolAddr);
  await linkTx.wait();
  console.log("NFT linked to PoolManager");

  // ═══════════════════════════════════════════
  //  Summary
  // ═══════════════════════════════════════════

  console.log("\n" + "═".repeat(50));
  console.log("DEPLOYMENT COMPLETE");
  console.log("═".repeat(50));
  console.log(`Network:          ${network}`);
  console.log(`InnerModelsNFT:   ${nftAddr}`);
  console.log(`PoolManager:      ${poolAddr}`);
  console.log(`PriceFeed:        ${priceFeedAddr}`);
  console.log(`SequencerFeed:    ${sequencerFeedAddr}`);
  console.log(`Creator:          ${deployer.address}`);
  console.log(`Tier Pricing:     Common 0.05 / Standard 0.08 / Rare 0.12 / Legendary 0.2 ETH`);
  console.log(`Max Supply:       264`);
  console.log(`Surcharge:        6.66%`);
  console.log(`Creator Fee:      6% of surplus (94% to participants)`);
  console.log(`Trigger:          ETH >= $10,000 or 3 years deadline`);
  console.log("═".repeat(50));

  // Save deployment addresses
  const fs = require("fs");
  const deploymentPath = `./deployments-${network}.json`;
  fs.writeFileSync(deploymentPath, JSON.stringify({
    network,
    nft: nftAddr,
    poolManager: poolAddr,
    priceFeed: priceFeedAddr,
    sequencerFeed: sequencerFeedAddr,
    creator: deployer.address,
    tierPricing: "Common 0.05 / Standard 0.08 / Rare 0.12 / Legendary 0.2 ETH",
    surcharge: "6.66%",
    deadline: "3 years",
    deployedAt: new Date().toISOString(),
  }, null, 2));
  console.log(`\nAddresses saved to ${deploymentPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
