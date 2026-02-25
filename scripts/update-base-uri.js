/**
 * Update the baseURI on InnerModelsNFT contract.
 * Run: npx hardhat run scripts/update-base-uri.js --network base
 */
async function main() {
  const NFT_ADDRESS = "0xB032B7053138cedFB3d948Ab5Beeb42eA0549195";
  const NEW_BASE_URI = "https://innermodels.art/metadata/";

  const [deployer] = await hre.ethers.getSigners();
  console.log("Caller:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "ETH");

  const nft = await hre.ethers.getContractAt("InnerModelsNFT", NFT_ADDRESS);

  // Check current tokenURI for token 99 (the minted one)
  try {
    const currentURI = await nft.tokenURI(99);
    console.log("Current tokenURI(99):", currentURI);
  } catch (e) {
    console.log("Could not read tokenURI(99):", e.message);
  }

  console.log("Setting new baseURI:", NEW_BASE_URI);
  const tx = await nft.setBaseURI(NEW_BASE_URI);
  console.log("TX hash:", tx.hash);
  await tx.wait();
  console.log("BaseURI updated successfully!");

  // Verify
  try {
    const newURI = await nft.tokenURI(99);
    console.log("New tokenURI(99):", newURI);
  } catch (e) {
    console.log("Could not verify tokenURI(99):", e.message);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
