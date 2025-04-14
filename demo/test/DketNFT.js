const { expect } = require("chai");

describe("DketNFT", function () {
  let DketNFT;
  let dketNFT;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async () => {
    [owner, addr1, addr2] = await ethers.getSigners();
    DketNFT = await ethers.getContractFactory("DketNFT");
    dketNFT = await DketNFT.deploy();
    await dketNFT.waitForDeployment();

    console.log("Contract deployed to:", dketNFT.target);
  });

  describe("Event Creation", function () {
    it("Should create an event", async function () {
        const title = "test event1"
        const photoCards = ["ipfs://photo1", "ipfs://photo2"];
        await dketNFT.createEvent(1, title, photoCards);

        const event = await dketNFT.events(1);
        expect(event.eventId).to.equal(1);
        expect(event.photoCardURIs).to.deep.equal(photoCards);
    });

    it("Should fail to create an event that already exists", async function () {
      const photoCards = ["ipfs://photo1", "ipfs://photo2"];
      const title = "test event1"
      await dketNFT.createEvent(1, title, photoCards);

      await expect(dketNFT.createEvent(1, title, photoCards)).to.be.revertedWith("Event already exists");
    });
  });

  describe("Session Creation and Raffle", function () {
    it("Should create a session and perform raffle", async function () {
      const photoCards = ["ipfs://photo1", "ipfs://photo2"];
      const title = "test event1"
      await dketNFT.createEvent(1, title, photoCards);

      const applications = [addr1.address, addr2.address];
      await dketNFT.createSession(1, 1, 1, applications);

      await dketNFT.drawWinnersAndAssignPhotoCards(1, 1);

      const winners = await dketNFT.getWinners(1, 1);
      expect(winners.length).to.equal(1);
      expect(applications).to.include(winners[0]);
    });
  });

  describe("Minting Tickets", function () {
    it("Should mint a ticket with correct photo card", async function () {
      const photoCards = ["ipfs://photo1", "ipfs://photo2"];
      const title = "test event1"
      await dketNFT.createEvent(1, title, photoCards);

      const applications = [addr1.address, addr2.address];
      await dketNFT.createSession(1, 1, 1, applications);

      await dketNFT.drawWinnersAndAssignPhotoCards(1, 1);

      await dketNFT.mintTicket(addr1.address, 1, 1);

      const tokenURI = await dketNFT.tokenURI(0);
      expect(tokenURI).to.include("ipfs://photo1");
    });
  });
});
