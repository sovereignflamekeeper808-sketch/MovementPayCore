/**
 * 1CMC RLRJ — Movement Pay Core Deployment Script
 * Copyright (c) 2026 Robert Lee Russell Jr. All rights reserved.
 *
 * Usage:
 *   npx hardhat run scripts/deploy.js --network ethereum
 *   npx hardhat run scripts/deploy.js --network bsc
 *   npx hardhat run scripts/deploy.js --network avalanche
 */

const hre = require("hardhat");

const CONFIG = {
  USDT: {
    ethereum: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    goerli: "0x509Ee0d083DdF8AC028f2a56731412edD63223B9",
    bsc: "0x55d398326f99059fF775485246999027B3197955",
    avalanche: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7",
  },
  FEE_BASIS_POINTS: 50,
  MULTISIG_REQUIRED: 2,
};

async function main() {
  const network = hre.network.name;
  console.log(`\n${"\u2550".repeat(60)}`);
  console.log(`  1CMC RLRJ \u2014 Movement Pay Core Deployment`);
  console.log(`  Network: ${network}`);
  console.log(`  Time: ${new Date().toISOString()}`);
  console.log(`${"\u2550".repeat(60)}\n`);

  const [deployer, ...signers] = await hre.ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log(`Deployer:  ${deployerAddress}`);
  console.log(`Balance:   ${hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployerAddress))} ETH\n`);

  const usdtAddress = CONFIG.USDT[network];
  if (!usdtAddress) {
    throw new Error(`No USDT address configured for network: ${network}`);
  }
  console.log(`USDT:      ${usdtAddress}`);

  // Step 1: Deploy Multi-Sig Treasury
  console.log(`\n[1/2] Deploying MovementPayMultiSig...`);

  const multiSigSigners = [deployerAddress];
  if (signers.length > 0) {
    multiSigSigners.push(await signers[0].getAddress());
  } else {
    console.log(`  Warning: Only one signer available. Add a second signer for production.`);
    multiSigSigners.push(deployerAddress);
  }

  const MultiSig = await hre.ethers.getContractFactory("MovementPayMultiSig");
  const multiSig = await MultiSig.deploy(
    multiSigSigners,
    Math.min(CONFIG.MULTISIG_REQUIRED, multiSigSigners.length)
  );
  await multiSig.waitForDeployment();

  const multiSigAddress = await multiSig.getAddress();
  console.log(`  MovementPayMultiSig deployed: ${multiSigAddress}`);
  console.log(`  Signers: ${multiSigSigners.join(", ")}`);
  console.log(`  Required confirmations: ${Math.min(CONFIG.MULTISIG_REQUIRED, multiSigSigners.length)}`);

  // Step 2: Deploy Settlement Engine
  console.log(`\n[2/2] Deploying MovementPayCoreSettlement...`);

  const Settlement = await hre.ethers.getContractFactory("MovementPayCoreSettlement");
  const settlement = await Settlement.deploy(
    usdtAddress,
    multiSigAddress,
    CONFIG.FEE_BASIS_POINTS,
    deployerAddress
  );
  await settlement.waitForDeployment();

  const settlementAddress = await settlement.getAddress();
  console.log(`  MovementPayCoreSettlement deployed: ${settlementAddress}`);
  console.log(`  USDT:     ${usdtAddress}`);
  console.log(`  Treasury: ${multiSigAddress}`);
  console.log(`  Fee:      ${CONFIG.FEE_BASIS_POINTS / 100}%`);
  console.log(`  Founder:  ${deployerAddress}`);

  // Deployment Summary
  console.log(`\n${"\u2550".repeat(60)}`);
  console.log(`  DEPLOYMENT COMPLETE`);
  console.log(`${"\u2550".repeat(60)}`);
  console.log(`\n  Network:                ${network}`);
  console.log(`  MovementPayMultiSig:    ${multiSigAddress}`);
  console.log(`  MovementPaySettlement:  ${settlementAddress}`);
  console.log(`  USDT Token:             ${usdtAddress}`);
  console.log(`  Protocol Fee:           ${CONFIG.FEE_BASIS_POINTS} bps (${CONFIG.FEE_BASIS_POINTS / 100}%)`);
  console.log(`  Founder:                ${deployerAddress}`);
  console.log(`\n  Update ADDRESSES in MovementPayClient.js:`);
  console.log(`    SETTLEMENT.${network}: "${settlementAddress}"`);
  console.log(`\n${"\u2550".repeat(60)}\n`);

  // Verify Contracts
  if (network !== "hardhat" && network !== "localhost") {
    console.log(`\nVerifying contracts on block explorer...\n`);

    try {
      await hre.run("verify:verify", {
        address: multiSigAddress,
        constructorArguments: [
          multiSigSigners,
          Math.min(CONFIG.MULTISIG_REQUIRED, multiSigSigners.length),
        ],
      });
      console.log(`  MovementPayMultiSig verified`);
    } catch (e) {
      console.log(`  MultiSig verification: ${e.message}`);
    }

    try {
      await hre.run("verify:verify", {
        address: settlementAddress,
        constructorArguments: [
          usdtAddress,
          multiSigAddress,
          CONFIG.FEE_BASIS_POINTS,
          deployerAddress,
        ],
      });
      console.log(`  MovementPayCoreSettlement verified`);
    } catch (e) {
      console.log(`  Settlement verification: ${e.message}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
