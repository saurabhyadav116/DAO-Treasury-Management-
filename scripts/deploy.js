const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Deploying DAO Treasury Management contract...");

  // Get the contract factory
  const DAOTreasury = await ethers.getContractFactory("DAOTreasury");

  // Deployment configuration
  const quorum = 51; // 51% quorum required
  const votingPeriod = 7 * 24 * 60 * 60; // 1 week in seconds

  // Deploy the contract
  const daoTreasury = await DAOTreasury.deploy(quorum, votingPeriod);
  await daoTreasury.deployed();

  // Output deployment info
  console.log("✅ DAOTreasury deployed successfully!");
  console.log(`📜 Contract Address: ${daoTreasury.address}`);
  console.log(`📊 Quorum: ${quorum}%`);
  console.log(`⏳ Voting Period: ${votingPeriod} seconds (${votingPeriod / 86400} days)`);

  // Optional: Check initial admin
  const admin = await daoTreasury.admin();
  console.log(`👑 Admin Address: ${admin}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment error:", error);
    process.exit(1);
  });
