const { ethers } = require('hardhat');

async function main () {
    const ANTokenMultichain = await ethers.getContractFactory("ANTokenMultichain");
    const anTokenMultichain = await ANTokenMultichain.deploy();
    await anTokenMultichain.waitForDeployment();
    console.log("Deployed to:", anTokenMultichain.target);
    await anTokenMultichain.transferOwnership("0x21331315ebFf1195Daf501279d2A45E37aE381Cf");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
