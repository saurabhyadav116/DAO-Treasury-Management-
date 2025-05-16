const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying DAO Treasury Management contract...");

  // Get the contract factory
  const DAOTreasury = await ethers.getContractFactory("DAOTreasury");
  
  // Set deployment parameters
  const quorum = 51; // 51% quorum required for proposals to pass
  const votingPeriod = 7 * 24 * 60 * 60; // 1 week voting period in seconds
  
  // Deploy the contract
  const daoTreasury = await DAOTreasury.deploy(quorum, votingPeriod);
  
  // Wait for deployment to finish
  await daoTreasury.deployed();
  
  console.log(`DAOTreasury deployed to: ${daoTreasury.address}`);
  console.log(`Quorum set to: ${quorum}%`);
  console.log(`Voting period: ${votingPeriod} seconds (${votingPeriod / (24 * 60 * 60)} days)`);
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error during deployment:", error);
    process.exit(1);
  });
