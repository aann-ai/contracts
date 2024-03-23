const { ethers } = require('hardhat');

async function main () {
    const relayer = "0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0";
    const ANTokenMultichain = await ethers.getContractFactory("ANTokenMultichain");
    const anTokenMultichain = await ANTokenMultichain.deploy(relayer);
    await anTokenMultichain.waitForDeployment();
    console.log("Deployed to:", anTokenMultichain.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
