// 1CMC RLRJ - Movement Pay Core | Settlement Tests
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MovementPaySettlement", function () {
  let settlement, mockUsdt;
  let owner, treasury, sender, recipient, settler;
  const USDT_DECIMALS = 6;
  const parseUSDT = (amount) => ethers.parseUnits(amount.toString(), USDT_DECIMALS);

  beforeEach(async function () {
    [owner, treasury, sender, recipient, settler] = await ethers.getSigners();

    const MockUSDT = await ethers.getContractFactory("MockUSDT");
    mockUsdt = await MockUSDT.deploy();

    const Settlement = await ethers.getContractFactory("MovementPayCoreSettlement");
    settlement = await Settlement.deploy(
      await mockUsdt.getAddress(),
      treasury.address,
      50,
      owner.address
    );

    const OPERATOR_ROLE = await settlement.OPERATOR_ROLE();
    await settlement.grantRole(OPERATOR_ROLE, settler.address);

    await mockUsdt.faucet(sender.address, parseUSDT(100_000));
    await mockUsdt.connect(sender).approve(
      await settlement.getAddress(),
      parseUSDT(100_000)
    );
  });

  describe("Deployment", function () {
    it("should set USDT address correctly", async function () {
      expect(await settlement.usdt()).to.equal(await mockUsdt.getAddress());
    });

    it("should set fee to 50 bps", async function () {
      expect(await settlement.feeBasisPoints()).to.equal(50);
    });
  });

  describe("Payment Initiation", function () {
    it("should initiate a payment and escrow USDT", async function () {
      const amount = parseUSDT(1000);
      const biometricHash = ethers.keccak256(ethers.toUtf8Bytes("ML-AUTH-001"));

      await settlement.connect(sender).initiatePayment(
        recipient.address,
        amount,
        biometricHash,
        "ethereum"
      );

      const contractBalance = await mockUsdt.balanceOf(await settlement.getAddress());
      expect(contractBalance).to.equal(amount);
    });

    it("should reject zero address payee", async function () {
      const biometricHash = ethers.keccak256(ethers.toUtf8Bytes("ML-AUTH-002"));
      await expect(
        settlement.connect(sender).initiatePayment(
          ethers.ZeroAddress,
          parseUSDT(100),
          biometricHash,
          "ethereum"
        )
      ).to.be.reverted;
    });

    it("should reject self-payment", async function () {
      const biometricHash = ethers.keccak256(ethers.toUtf8Bytes("ML-AUTH-003"));
      await expect(
        settlement.connect(sender).initiatePayment(
          sender.address,
          parseUSDT(100),
          biometricHash,
          "ethereum"
        )
      ).to.be.reverted;
    });
  });

  describe("Settlement Confirmation", function () {
    let settlementId;

    beforeEach(async function () {
      const amount = parseUSDT(1000);
      const biometricHash = ethers.keccak256(ethers.toUtf8Bytes("ML-AUTH-004"));

      const tx = await settlement.connect(sender).initiatePayment(
        recipient.address,
        amount,
        biometricHash,
        "ethereum"
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find(
        (log) => {
          try {
            const parsed = settlement.interface.parseLog(log);
            return parsed.name === "PaymentInitiated";
          } catch { return false; }
        }
      );
      const parsed = settlement.interface.parseLog(event);
      settlementId = parsed.args.settlementId;
    });

    it("should settle and transfer USDT to recipient", async function () {
      const before = await mockUsdt.balanceOf(recipient.address);
      await settlement.connect(settler).confirmSettlement(settlementId);
      const after = await mockUsdt.balanceOf(recipient.address);
      expect(after - before).to.equal(parseUSDT(995));
    });

    it("should transfer fee to treasury", async function () {
      const before = await mockUsdt.balanceOf(treasury.address);
      await settlement.connect(settler).confirmSettlement(settlementId);
      const after = await mockUsdt.balanceOf(treasury.address);
      expect(after - before).to.equal(parseUSDT(5));
    });
  });

  describe("Refunds", function () {
    it("should refund full amount to sender", async function () {
      const amount = parseUSDT(500);
      const biometricHash = ethers.keccak256(ethers.toUtf8Bytes("ML-AUTH-005"));

      const tx = await settlement.connect(sender).initiatePayment(
        recipient.address,
        amount,
        biometricHash,
        "ethereum"
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find(
        (log) => {
          try {
            const parsed = settlement.interface.parseLog(log);
            return parsed.name === "PaymentInitiated";
          } catch { return false; }
        }
      );
      const parsed = settlement.interface.parseLog(event);
      const settlementId = parsed.args.settlementId;

      const before = await mockUsdt.balanceOf(sender.address);
      await settlement.connect(settler).refundSettlement(settlementId);
      const after = await mockUsdt.balanceOf(sender.address);
      expect(after - before).to.equal(amount);
    });
  });

  describe("Admin Controls", function () {
    it("should update fee", async function () {
      await settlement.setFeeBasisPoints(100);
      expect(await settlement.feeBasisPoints()).to.equal(100);
    });

    it("should reject fee above 5% cap", async function () {
      await expect(settlement.setFeeBasisPoints(600)).to.be.reverted;
    });

    it("should pause and unpause", async function () {
      await settlement.pause();
      const biometricHash = ethers.keccak256(ethers.toUtf8Bytes("ML-AUTH-006"));
      await expect(
        settlement.connect(sender).initiatePayment(
          recipient.address,
          parseUSDT(100),
          biometricHash,
          "ethereum"
        )
      ).to.be.reverted;
      await settlement.unpause();
    });
  });
});
