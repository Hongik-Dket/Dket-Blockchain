// const { expect } = require("chai");
// const { ethers } = require("hardhat");
// const { utils } = require("ethers");

// describe("DketNFT", function () {
//   let DketNFT;
//   let dketNFT;
//   let owner;
//   let addr1;
//   let addr2;
//   let addr3;
//   let addr4;

//   const vrfCoordinatorMockAddress = "0x0000000000000000000000000000000000000000"; // Mock VRF address
//   const subscriptionId = 1; // Subscription ID
//   const keyHash = utils.formatBytes32String("keyhash"); 

//   beforeEach(async () => {
//     [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();

//     DketNFT = await ethers.getContractFactory("DketNFT");
//     dketNFT = await DketNFT.deploy(vrfCoordinatorMockAddress, subscriptionId, keyHash);
//     await dketNFT.deployed();
//   });

//   it("should create an event", async function () {
//     const photoCardURIs = ["uri1", "uri2", "uri3"];
//     await dketNFT.createEvent(1, "Concert", photoCardURIs);
    
//     const event = await dketNFT.events(1);
//     expect(event.title).to.equal("Concert");
//     expect(event.photoCardURIs.length).to.equal(3);
//   });

//   it("should create a session and request randomness", async function () {
//     const applications = [addr1.address, addr2.address, addr3.address];
//     await dketNFT.createSession(1, 1, 2, applications);
    
//     const session = await dketNFT.sessions(1, 1);
//     expect(session.applications.length).to.equal(3);
//     expect(session.maxWinners).to.equal(2);
//     expect(session.raffleDone).to.be.false;
//   });

//   it("should draw winners and emit WinnersDrawn event", async function () {
//     const applications = [addr1.address, addr2.address, addr3.address];
//     await dketNFT.createSession(1, 1, 3, applications);
    
//     // Simulate fulfilling random words (normally done via Chainlink VRF callback)
//     const randomWords = [ethers.BigNumber.from("10000000000000000000000000000000000000000000000000000000000000000")];
//     await dketNFT.fulfillRandomWords(1, randomWords);

//     const session = await dketNFT.sessions(1, 1);
//     expect(session.raffleDone).to.be.true;
    
//     // Test WinnersDrawn event
//     await expect(dketNFT.fulfillRandomWords(1, randomWords))
//       .to.emit(dketNFT, "WinnersDrawn")
//       .withArgs(1, 1, session.winners, session.photoCardIndices);
//   });

//   it("should mint ticket for a winner", async function () {
//     const applications = [addr1.address, addr2.address, addr3.address];
//     await dketNFT.createSession(1, 1, 2, applications);
    
//     // Simulate fulfilling random words
//     const randomWords = [ethers.BigNumber.from("10000000000000000000000000000000000000000000000000000000000000000")];
//     await dketNFT.fulfillRandomWords(1, randomWords);
    
//     // Mint ticket for winner
//     await dketNFT.mintTicket(addr1.address, 1, 1);
//     expect(await dketNFT.ownerOf(0)).to.equal(addr1.address); // Check if addr1 received the ticket
    
//     const tokenURI = await dketNFT.tokenURI(0);
//     expect(tokenURI).to.equal("uri1"); // Check if the correct photo card URI is assigned
//   });

//   it("should revert minting for non-winner", async function () {
//     const applications = [addr1.address, addr2.address, addr3.address];
//     await dketNFT.createSession(1, 1, 2, applications);
    
//     // Simulate fulfilling random words
//     const randomWords = [ethers.BigNumber.from("10000000000000000000000000000000000000000000000000000000000000000")];
//     await dketNFT.fulfillRandomWords(1, randomWords);

//     // Attempt minting for addr4 (non-winner)
//     await expect(dketNFT.mintTicket(addr4.address, 1, 1))
//       .to.be.revertedWith("Not a winner");
//   });

//   it("should validate winner correctly", async function () {
//     const applications = [addr1.address, addr2.address, addr3.address];
//     await dketNFT.createSession(1, 1, 2, applications);
    
//     // Simulate fulfilling random words
//     const randomWords = [ethers.BigNumber.from("10000000000000000000000000000000000000000000000000000000000000000")];
//     await dketNFT.fulfillRandomWords(1, randomWords);

//     // Validate winner
//     expect(await dketNFT.validateWinner(addr1.address, 1, 1)).to.be.true;
//     expect(await dketNFT.validateWinner(addr2.address, 1, 1)).to.be.true;

//     // Validate non-winner
//     expect(await dketNFT.validateWinner(addr3.address, 1, 1)).to.be.false;
//   });
// });
