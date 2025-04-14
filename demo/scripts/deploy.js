require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
  
    const DketNFT = await ethers.getContractFactory("DketNFT");
    const dketNFT = await DketNFT.deploy();
    await dketNFT.waitForDeployment();
    
    console.log("DketNFT contract deployed to:", await dketNFT.getAddress());
    
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
