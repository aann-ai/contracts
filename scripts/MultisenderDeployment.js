const { ethers } = require('hardhat');

async function main () {
    const Multisender = await ethers.getContractFactory("Multisender");
    const multisender = await Multisender.deploy("0x9aBc7C604C27622f9CD56bd1628F6321c32bBBf6");
    await multisender.waitForDeployment();
    console.log("Multisender deployed to:", multisender.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
