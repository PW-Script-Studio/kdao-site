// scripts/deploy.js
const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Color codes for console output
const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  red: "\x1b[31m"
};

function log(message, color = colors.reset) {
  console.log(`${color}${message}${colors.reset}`);
}

async function main() {
  log("\n========================================", colors.bright);
  log("   KDAO 2.0 CONTRACT DEPLOYMENT", colors.bright + colors.blue);
  log("========================================\n", colors.bright);

  // Get network info
  const network = await ethers.provider.getNetwork();
  const [deployer] = await ethers.getSigners();
  const balance = await ethers.provider.getBalance(deployer.address);

  log(`📍 Network: ${network.name} (Chain ID: ${network.chainId})`, colors.yellow);
  log(`👤 Deployer: ${deployer.address}`, colors.yellow);
  log(`💰 Balance: ${ethers.formatEther(balance)} KAS/ETH\n`, colors.yellow);

  // Deployment addresses storage
  const deployments = {};

  try {
    // ============ 1. Deploy KDAO Token (if not already deployed) ============
    let kdaoTokenAddress = process.env.KDAO_TOKEN_ADDRESS;
    
    if (!kdaoTokenAddress) {
      log("📦 Deploying KDAO Token...", colors.blue);
      const KDAOToken = await ethers.getContractFactory("KDAOToken");
      const kdaoToken = await KDAOToken.deploy(
        "Kaspa DAO",
        "KDAO",
        ethers.parseEther("150000000") // 150M total supply
      );
      await kdaoToken.waitForDeployment();
      kdaoTokenAddress = await kdaoToken.getAddress();
      deployments.kdaoToken = kdaoTokenAddress;
      log(`✅ KDAO Token deployed at: ${kdaoTokenAddress}\n`, colors.green);
    } else {
      deployments.kdaoToken = kdaoTokenAddress;
      log(`✅ Using existing KDAO Token at: ${kdaoTokenAddress}\n`, colors.green);
    }

    // ============ 2. Deploy Governance Contract ============
    log("📦 Deploying KDAOGovernance...", colors.blue);
    const KDAOGovernance = await ethers.getContractFactory("KDAOGovernance");
    const governance = await KDAOGovernance.deploy(kdaoTokenAddress);
    await governance.waitForDeployment();
    const governanceAddress = await governance.getAddress();
    deployments.governance = governanceAddress;
    log(`✅ KDAOGovernance deployed at: ${governanceAddress}\n`, colors.green);

    // ============ 3. Deploy Staking Contract ============
    log("📦 Deploying StakingRewards...", colors.blue);
    const StakingRewards = await ethers.getContractFactory("StakingRewards");
    
    // For now, use KDAO token as LP token placeholder
    // Replace with actual LP token address when available
    const lpTokenAddress = process.env.LP_TOKEN_ADDRESS || kdaoTokenAddress;
    
    const staking = await StakingRewards.deploy(
      kdaoTokenAddress,
      lpTokenAddress
    );
    await staking.waitForDeployment();
    const stakingAddress = await staking.getAddress();
    deployments.staking = stakingAddress;
    log(`✅ StakingRewards deployed at: ${stakingAddress}\n`, colors.green);

    // ============ 4. Deploy Treasury Manager ============
    log("📦 Deploying TreasuryManager...", colors.blue);
    const TreasuryManager = await ethers.getContractFactory("TreasuryManager");
    const treasury = await TreasuryManager.deploy(
      kdaoTokenAddress,
      stakingAddress,
      governanceAddress
    );
    await treasury.waitForDeployment();
    const treasuryAddress = await treasury.getAddress();
    deployments.treasury = treasuryAddress;
    log(`✅ TreasuryManager deployed at: ${treasuryAddress}\n`, colors.green);

    // ============ 5. Deploy Election Manager ============
    log("📦 Deploying ElectionManager...", colors.blue);
    const ElectionManager = await ethers.getContractFactory("ElectionManager");
    const election = await ElectionManager.deploy(
      kdaoTokenAddress,
      stakingAddress,
      governanceAddress
    );
    await election.waitForDeployment();
    const electionAddress = await election.getAddress();
    deployments.election = electionAddress;
    log(`✅ ElectionManager deployed at: ${electionAddress}\n`, colors.green);

    // ============ 6. Setup Contract Permissions ============
    log("🔧 Setting up contract permissions...", colors.blue);

    // Grant governance role to treasury in governance contract
    const EXECUTOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("EXECUTOR_ROLE"));
    await governance.grantRole(EXECUTOR_ROLE, treasuryAddress);
    log("  ✓ Treasury granted EXECUTOR_ROLE in Governance", colors.green);

    // Grant governance role to governance contract in treasury
    const GOVERNANCE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOVERNANCE_ROLE"));
    await treasury.grantRole(GOVERNANCE_ROLE, governanceAddress);
    log("  ✓ Governance granted GOVERNANCE_ROLE in Treasury", colors.green);

    // Grant rewards manager role to treasury in staking
    const REWARDS_MANAGER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("REWARDS_MANAGER_ROLE"));
    await staking.grantRole(REWARDS_MANAGER_ROLE, treasuryAddress);
    log("  ✓ Treasury granted REWARDS_MANAGER_ROLE in Staking", colors.green);

    // Update contracts in treasury
    await treasury.updateContracts(stakingAddress, governanceAddress);
    log("  ✓ Contract addresses updated in Treasury\n", colors.green);

    // ============ 7. Initialize Contracts ============
    log("🚀 Initializing contracts...", colors.blue);

    // Add initial rewards to staking pool (if deployer has KDAO)
    try {
      const kdaoToken = await ethers.getContractAt("IERC20", kdaoTokenAddress);
      const deployerBalance = await kdaoToken.balanceOf(deployer.address);
      
      if (deployerBalance > 0) {
        const rewardAmount = ethers.parseEther("10000"); // 10,000 KDAO initial rewards
        
        // Approve and add rewards
        await kdaoToken.approve(stakingAddress, rewardAmount);
        await staking.addRewards(rewardAmount);
        log(`  ✓ Added ${ethers.formatEther(rewardAmount)} KDAO to reward pool`, colors.green);
      }
    } catch (error) {
      log("  ⚠ Could not add initial rewards (no KDAO balance)", colors.yellow);
    }

    // Set Q4 2025 allocation in Treasury (200,000 KDAO)
    await treasury.setQuarterlyAllocation(
      2025,  // year
      4,     // quarter
      ethers.parseEther("80000"),  // utility (40%)
      ethers.parseEther("20000"),  // token (10%)
      ethers.parseEther("40000"),  // education (20%)
      ethers.parseEther("60000"),  // marketing (30%)
      ethers.parseEther("0")       // infrastructure (0%)
    );
    log("  ✓ Q4 2025 allocation set (200,000 KDAO)\n", colors.green);

    // ============ 8. Save Deployment Addresses ============
    const deploymentInfo = {
      network: network.name,
      chainId: Number(network.chainId),
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      contracts: deployments,
      configuration: {
        minProposalThreshold: "100 KDAO",
        quorumPercentage: "30%",
        votingPeriod: "7 days",
        stakingAPY: {
          base: "15%",
          lpBonus: "25%",
          longTerm: "5%"
        },
        treasuryDistribution: {
          stakers: "70%",
          treasury: "10%",
          restaking: "20%"
        }
      }
    };

    const deploymentsDir = path.join(__dirname, "../deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir);
    }

    const filename = `${network.name}-${Date.now()}.json`;
    fs.writeFileSync(
      path.join(deploymentsDir, filename),
      JSON.stringify(deploymentInfo, null, 2)
    );

    // Also save as latest
    fs.writeFileSync(
      path.join(deploymentsDir, `${network.name}-latest.json`),
      JSON.stringify(deploymentInfo, null, 2)
    );

    // ============ 9. Verify Contracts (if not on localhost) ============
    if (network.name !== "localhost" && network.name !== "hardhat") {
      log("📝 Preparing contract verification...\n", colors.blue);
      
      const verifyCommands = [
        `npx hardhat verify --network ${network.name} ${governanceAddress} ${kdaoTokenAddress}`,
        `npx hardhat verify --network ${network.name} ${stakingAddress} ${kdaoTokenAddress} ${lpTokenAddress}`,
        `npx hardhat verify --network ${network.name} ${treasuryAddress} ${kdaoTokenAddress} ${stakingAddress} ${governanceAddress}`,
        `npx hardhat verify --network ${network.name} ${electionAddress} ${kdaoTokenAddress} ${stakingAddress} ${governanceAddress}`
      ];

      log("Run these commands to verify contracts:", colors.yellow);
      verifyCommands.forEach(cmd => log(`  ${cmd}`, colors.reset));
    }

    // ============ 10. Summary ============
    log("\n========================================", colors.bright);
    log("   DEPLOYMENT COMPLETE! 🎉", colors.bright + colors.green);
    log("========================================\n", colors.bright);

    log("📋 Contract Addresses:", colors.bright);
    log(`  KDAO Token:      ${deployments.kdaoToken}`, colors.green);
    log(`  Governance:      ${deployments.governance}`, colors.green);
    log(`  Treasury:        ${deployments.treasury}`, colors.green);
    log(`  Staking:         ${deployments.staking}`, colors.green);
    log(`  Elections:       ${deployments.election}`, colors.green);

    log("\n💾 Deployment info saved to:", colors.bright);
    log(`  ${path.join(deploymentsDir, filename)}`, colors.blue);

    log("\n🔗 Next Steps:", colors.bright);
    log("  1. Update .env with contract addresses", colors.yellow);
    log("  2. Transfer KDAO tokens to Treasury", colors.yellow);
    log("  3. Create first election for Project Lead", colors.yellow);
    log("  4. Update frontend with contract addresses", colors.yellow);
    log("  5. Verify contracts on explorer\n", colors.yellow);

    return deployments;

  } catch (error) {
    log(`\n❌ Deployment failed: ${error.message}`, colors.red);
    console.error(error);
    process.exit(1);
  }
}

// Execute deployment
main()
  .then((deployments) => {
    log("✅ All contracts deployed successfully!\n", colors.green);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

module.exports = main;