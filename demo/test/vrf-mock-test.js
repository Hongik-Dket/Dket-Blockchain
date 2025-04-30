// test/vrf-mock-test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DketNFT with VRF Mock", function () {
    let deployer;
    let dketNFT;
    let vrfMock;
    let requestId;

    beforeEach(async () => {
        [deployer] = await ethers.getSigners();

        // VRFMock 배포
        const VRFMock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
        vrfMock = await VRFMock.deploy(1000000000000000000, 0);
        await vrfMock.deployed();

        // DketNFT 배포
        const DketNFT = await ethers.getContractFactory("DketNFT");
        dketNFT = await DketNFT.deploy(vrfMock.address, 1, "0x121a5b46c4f6c7f7d88d93f30d3ea25f4a47af6c040f8da0a27c4e02474f8c32");
        await dketNFT.deployed();
    });

    it("should fulfill random words correctly", async () => {
        // 랜덤값 요청
        const applications = [deployer.address, "0x1234567890abcdef1234567890abcdef12345678"];
        await dketNFT.createSession(1, 1, 2, applications);
        
        // Mock VRF를 통해 랜덤값 설정
        requestId = 1; // 테스트용 requestId
        const randomWords = [12345];
        await vrfMock.fulfillRandomWords(requestId, dketNFT.address);

        // VRF가 정상적으로 동작하는지 확인
        const session = await dketNFT.sessions(1, 1);
        expect(session.winners.length).to.equal(2); // 당첨자 수가 맞는지 확인
    });
});
