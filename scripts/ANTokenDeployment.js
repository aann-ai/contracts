const { ethers } = require('hardhat');

async function main () {
    const relayer = "0x80aC94316391752A193C1c47E27D382b507c93F3";
    const liquidityProvider = "0x437C143d2033199AB974d78a5412cE047758fF11";
    const ANToken = await ethers.getContractFactory("ANToken");
    const anToken = await ANToken.deploy(relayer, liquidityProvider);
    await anToken.waitForDeployment();
    console.log("Deployed to:", anToken.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
