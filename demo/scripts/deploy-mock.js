require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // 1. VRFCoordinatorV2Mock 배포
  const baseFee = ethers.utils.parseEther("1"); // 1 LINK
  const gasPriceLink = 0; // 테스트용
  const VRFMock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
  const vrfMock = await VRFMock.deploy(baseFee, gasPriceLink);
  await vrfMock.deployed();
  console.log("✅ VRFMock deployed to:", vrfMock.address);

  // 2. Subscription 생성 및 자금 추가
  const tx = await vrfMock.createSubscription();
  const receipt = await tx.wait();
  const subscriptionId = receipt.events[0].args.subId;
  console.log("✅ Subscription created with ID:", subscriptionId.toString());

  await vrfMock.fundSubscription(subscriptionId, ethers.utils.parseEther("5"));
  console.log("✅ Subscription funded with 5 LINK");

  // 3. DketNFT 배포
  const keyHash = "0x121a5b46c4f6c7f7d88d93f30d3ea25f4a47af6c040f8da0a27c4e02474f8c32";
  const DketNFT = await ethers.getContractFactory("DketNFT");
  const dketNFT = await DketNFT.deploy(vrfMock.address, subscriptionId, keyHash);
  await dketNFT.deployed();
  console.log("✅ DketNFT deployed to:", dketNFT.address);

  // 4. Consumer 등록
  await vrfMock.addConsumer(subscriptionId, dketNFT.address);
  console.log("✅ DketNFT added as consumer");

  // 5. requestRandomWords 호출 (랜덤 요청)
  const reqTx = await dketNFT.requestRandomWinner(); // ← 이 함수는 스마트컨트랙트 내에 있어야 함
  const reqReceipt = await reqTx.wait();

  const requestId = reqReceipt.events.find((e) => e.event === "RandomnessRequested").args.requestId;
  console.log("✅ Randomness requested. Request ID:", requestId.toString());

  // 6. fulfillRandomWords 호출 (응답 시뮬레이션)
  const fulfillTx = await vrfMock.fulfillRandomWords(requestId, dketNFT.address);
  await fulfillTx.wait();
  console.log("✅ Randomness fulfilled");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
