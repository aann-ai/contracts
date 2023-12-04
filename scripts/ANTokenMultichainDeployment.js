const { ethers } = require('hardhat');

async function main () {
    const relayer = "0x706f82e9bb5b0813501714ab5974216704980e31";
    const commissionRecipient = "0x04903Ae59f8038E13598f81854241558d9F132D5";
    const ANTokenMultichain = await ethers.getContractFactory("ANTokenMultichain");
    const anTokenMultichain = await ANTokenMultichain.deploy(relayer, commissionRecipient);
    await anTokenMultichain.waitForDeployment();
    console.log("Deployed to:", anTokenMultichain.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
