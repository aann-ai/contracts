const { ethers } = require('hardhat');

async function main () {
    const DataKeeper = await ethers.getContractFactory("DataKeeper");
    const dataKeeper = await DataKeeper.deploy();
    await dataKeeper.waitForDeployment();
    console.log("Deployed to:", dataKeeper.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
