const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deploying with', deployer.address);
  const IMMAC = await ethers.getContractFactory('IMMAC');
  const immac = await IMMAC.deploy();
  await immac.waitForDeployment();
  console.log('IMMAC deployed to', await immac.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
