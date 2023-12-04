const { ethers } = require('hardhat');

async function main () {
    const relayer = "0x27428DD2d3DD32A4D7f7C497eAaa23130d894911";
    const commissionRecipient = "0xc42c98D43facfB74Fb1E818B8A7571b1f584D2cc";
    const liquidityProvider = "0x9494FfCF3dBeD4a67FCACD3419fb987f4cc0EAaC";
    const ANToken = await ethers.getContractFactory("ANToken");
    const anToken = await ANToken.deploy(relayer, commissionRecipient, liquidityProvider);
    await anToken.waitForDeployment();
    console.log("Deployed to:", anToken.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
