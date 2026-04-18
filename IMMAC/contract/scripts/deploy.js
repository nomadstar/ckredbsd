async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deploying with', deployer.address);
  const IMMAC = await ethers.getContractFactory('IMMAC');
  const immac = await IMMAC.deploy();
  await immac.deployed();
  console.log('IMMAC deployed to', immac.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
