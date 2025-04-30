require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const vrfCoordinator = process.env.VRF_COORDINATOR;
    const subscriptionId = process.env.VRF_SUBSCRIPTION_ID;
    const keyHash = process.env.VRF_KEY_HASH;

    if (!vrfCoordinator || !subscriptionId || !keyHash)
        throw new Error("Missing VRF configuration in .env file.");

    const subId = ethers.BigNumber.from(subscriptionId);

    const DketNFT = await ethers.getContractFactory("DketNFT");
    const dketNFT = await DketNFT.deploy(vrfCoordinator, subId, keyHash);
    await dketNFT.deployed();
    
    console.log("DketNFT contract deployed to:", dketNFT.address);
    
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
