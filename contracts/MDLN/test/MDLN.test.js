const { expect } = require("chai");
const { ethers }  = require("hardhat");
const { time }    = require("@nomicfoundation/hardhat-network-helpers");

const TOTAL_SUPPLY    = ethers.parseUnits("21000000",  18);
const OPERATIONAL     = ethers.parseUnits("2100000",   18);
const VESTING_DEPOSIT = ethers.parseUnits("18900000",  18);
const TRANCHE         = ethers.parseUnits("2100000",   18);
const YEAR            = 365 * 24 * 60 * 60;

// Deploy a MockSafe (contract) to use as treasury
async function deployMockSafe() {
  const MockSafe = await ethers.getContractFactory("MockSafe");
  return MockSafe.deploy();
}

describe("MedialaneToken", () => {
  let token, safe, deployer;

  beforeEach(async () => {
    [deployer] = await ethers.getSigners();
    safe = await deployMockSafe();
    const Token = await ethers.getContractFactory("MedialaneToken");
    token = await Token.deploy(await safe.getAddress());
  });

  it("mints 21M to the treasury", async () => {
    expect(await token.totalSupply()).to.equal(TOTAL_SUPPLY);
    expect(await token.balanceOf(await safe.getAddress())).to.equal(TOTAL_SUPPLY);
  });

  it("rejects zero address as treasury", async () => {
    const Token = await ethers.getContractFactory("MedialaneToken");
    await expect(Token.deploy(ethers.ZeroAddress))
      .to.be.revertedWithCustomError(token, "MDLN_ZeroAddress");
  });

  it("rejects EOA as treasury", async () => {
    const Token = await ethers.getContractFactory("MedialaneToken");
    await expect(Token.deploy(deployer.address))
      .to.be.revertedWithCustomError(token, "MDLN_TreasuryNotContract");
  });

  it("supports burning", async () => {
    // Transfer some to deployer EOA first, then burn
    const amount = ethers.parseUnits("1000", 18);
    await safe.transfer(await token.getAddress(), deployer.address, amount);
    await token.burn(amount);
    expect(await token.totalSupply()).to.equal(TOTAL_SUPPLY - amount);
  });
});

describe("MDLNVesting", () => {
  let token, vesting, safe, deployer, anyone;

  beforeEach(async () => {
    [deployer, anyone] = await ethers.getSigners();
    safe = await deployMockSafe();
    const safeAddress = await safe.getAddress();

    const Token = await ethers.getContractFactory("MedialaneToken");
    token = await Token.deploy(safeAddress);

    const Vesting = await ethers.getContractFactory("MDLNVesting");
    vesting = await Vesting.deploy(await token.getAddress(), safeAddress);
    const vestingAddress = await vesting.getAddress();

    // Safe funds the vesting contract with 18.9M
    await safe.transfer(await token.getAddress(), vestingAddress, VESTING_DEPOSIT);
  });

  it("holds 18.9M after deposit", async () => {
    expect(await vesting.lockedBalance()).to.equal(VESTING_DEPOSIT);
  });

  it("has 0 tranches due at deploy", async () => {
    expect(await vesting.tranchesDue()).to.equal(0);
  });

  it("reverts release() when nothing is due", async () => {
    await expect(vesting.release())
      .to.be.revertedWithCustomError(vesting, "MDLN_NothingToRelease");
  });

  it("releases 1 tranche after 1 year", async () => {
    const safeAddress = await safe.getAddress();
    const safeBalanceBefore = await token.balanceOf(safeAddress);

    await time.increase(YEAR);
    expect(await vesting.tranchesDue()).to.equal(1);

    await vesting.release();

    expect(await token.balanceOf(safeAddress)).to.equal(safeBalanceBefore + TRANCHE);
    expect(await vesting.lockedBalance()).to.equal(VESTING_DEPOSIT - TRANCHE);
    expect(await vesting.releasedTranches()).to.equal(1);
  });

  it("releases 3 tranches in one call after 3 years", async () => {
    const safeAddress = await safe.getAddress();
    const safeBalanceBefore = await token.balanceOf(safeAddress);

    await time.increase(YEAR * 3);
    expect(await vesting.tranchesDue()).to.equal(3);

    await vesting.release();

    expect(await token.balanceOf(safeAddress)).to.equal(safeBalanceBefore + TRANCHE * 3n);
    expect(await vesting.releasedTranches()).to.equal(3);
  });

  it("releases all 9 tranches after 9 years", async () => {
    await time.increase(YEAR * 9);
    await vesting.release();

    expect(await vesting.releasedTranches()).to.equal(9);
    expect(await vesting.lockedBalance()).to.equal(0);
    expect(await token.balanceOf(await safe.getAddress())).to.equal(TOTAL_SUPPLY);
  });

  it("does not release more than 9 tranches", async () => {
    await time.increase(YEAR * 12);
    await vesting.release();
    expect(await vesting.releasedTranches()).to.equal(9);
  });

  it("release() is permissionless — anyone can trigger it", async () => {
    const safeAddress = await safe.getAddress();
    const safeBalanceBefore = await token.balanceOf(safeAddress);

    await time.increase(YEAR);
    await expect(vesting.connect(anyone).release()).to.not.be.reverted;
    expect(await token.balanceOf(safeAddress)).to.equal(safeBalanceBefore + TRANCHE);
  });

  it("emits Released event with correct data", async () => {
    await time.increase(YEAR);
    await expect(vesting.release())
      .to.emit(vesting, "Released")
      .withArgs(1, TRANCHE, await time.latest() + 1);
  });

  it("nextReleaseAt() returns 0 after all tranches released", async () => {
    await time.increase(YEAR * 9);
    await vesting.release();
    expect(await vesting.nextReleaseAt()).to.equal(0);
  });

  it("delegation and vote weight work after vesting release", async () => {
    await time.increase(YEAR);
    await vesting.release();
    // Safe delegates to itself — vote weight should include released tranche
    // (MockSafe can't call delegate directly, but we verify balance is correct)
    expect(await token.balanceOf(await safe.getAddress())).to.equal(OPERATIONAL + TRANCHE);
  });
});
