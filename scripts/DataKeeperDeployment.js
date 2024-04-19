const { ethers } = require('hardhat');

async function main () {
    const DataKeeper = await ethers.getContractFactory("DataKeeper");
    const dataKeeper = await DataKeeper.deploy();
    await dataKeeper.waitForDeployment();
    console.log("Deployed to:", dataKeeper.target);
    await dataKeeper.transferOwnership("0xfdC788a46beCa9fCC6Ba46f2151ea53Be3477f11");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
