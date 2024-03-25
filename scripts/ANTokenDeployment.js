const { ethers } = require('hardhat');

async function main () {
    const ANToken = await ethers.getContractFactory("ANToken");
    const anToken = await ANToken.deploy();
    await anToken.waitForDeployment();
    console.log("Deployed to:", anToken.target);
    await anToken.transferOwnership("0x69E08874Eaf3eF3AF428F7F4Da2156028B3EaD90");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
