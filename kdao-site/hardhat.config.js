require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-deploy");
require("hardhat-contract-sizer");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("dotenv").config();

// Tasks
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  for (const account of accounts) {
    console.log(account.address);
  }
});

task("balance", "Prints an account's balance")
  .addParam("account", "The account's address")
  .setAction(async (taskArgs, hre) => {
    const balance = await hre.ethers.provider.getBalance(taskArgs.account);
    console.log(hre.ethers.formatEther(balance), "ETH");
  });

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yul: true,
          yulDetails: {
            stackAllocation: true,
            optimizerSteps: "dhfoDgvulfnTUtnIf"
          }
        }
      },
      viaIR: false,
      metadata: {
        bytecodeHash: "ipfs"
      }
    }
  },
  
  networks: {
    // Local development network
    hardhat: {
      chainId: 31337,
      gasPrice: "auto",
      gas: "auto",
      allowUnlimitedContractSize: true,
      mining: {
        auto: true,
        interval: 5000
      }
    },
    
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    },
    
    // Kasplex Testnet (EVM-compatible Layer 2)
    kasplex_testnet: {
      url: process.env.KASPLEX_TESTNET_RPC || "https://testnet-rpc.kasplex.org",
      chainId: 98765, // Replace with actual Kasplex testnet chain ID
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: "auto",
      gas: "auto",
      timeout: 60000,
      confirmations: 2
    },
    
    // Kasplex Mainnet (EVM-compatible Layer 2)
    kasplex: {
      url: process.env.KASPLEX_MAINNET_RPC || "https://rpc.kasplex.org",
      chainId: 12345, // Replace with actual Kasplex mainnet chain ID
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: "auto",
      gas: "auto",
      timeout: 60000,
      confirmations: 6
    },
    
    // Ethereum Sepolia Testnet (for testing bridges)
    sepolia: {
      url: process.env.SEPOLIA_RPC || `https://sepolia.infura.io/v3/${process.env.INFURA_KEY}`,
      chainId: 11155111,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: "auto"
    },
    
    // Ethereum Mainnet (for future bridge)
    ethereum: {
      url: process.env.ETHEREUM_RPC || `https://mainnet.infura.io/v3/${process.env.INFURA_KEY}`,
      chainId: 1,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: "auto"
    }
  },
  
  // Contract verification
  etherscan: {
    apiKey: {
      kasplex: process.env.KASPLEX_EXPLORER_API || "YOUR_KASPLEX_API_KEY",
      sepolia: process.env.ETHERSCAN_API_KEY || "YOUR_ETHERSCAN_API_KEY"
    },
    customChains: [
      {
        network: "kasplex",
        chainId: 12345, // Replace with actual chain ID
        urls: {
          apiURL: "https://api.kasplex-explorer.org/api",
          browserURL: "https://explorer.kasplex.org"
        }
      },
      {
        network: "kasplex_testnet",
        chainId: 98765, // Replace with actual chain ID
        urls: {
          apiURL: "https://api-testnet.kasplex-explorer.org/api",
          browserURL: "https://testnet.explorer.kasplex.org"
        }
      }
    ]
  },
  
  // Gas reporter configuration
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    gasPrice: 21,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    token: "KAS",
    outputFile: "gas-report.txt",
    noColors: false,
    excludeContracts: ["test/", "node_modules/"]
  },
  
  // Contract sizer
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
    only: ["KDAOGovernance", "TreasuryManager", "StakingRewards", "ElectionManager"]
  },
  
  // Paths
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
    deploy: "./scripts/deploy"
  },
  
  // Mocha test configuration
  mocha: {
    timeout: 100000,
    reporter: "spec"
  },
  
  // Named accounts for deployment
  namedAccounts: {
    deployer: {
      default: 0,
      1: 0, // mainnet
      11155111: 0, // sepolia
      12345: 0, // kasplex mainnet
      98765: 0 // kasplex testnet
    },
    treasury: {
      default: 1,
      1: "0x1234567890123456789012345678901234567890", // Replace with actual treasury
      12345: "0x1234567890123456789012345678901234567890" // Replace with actual treasury
    },
    governance: {
      default: 2
    },
    staking: {
      default: 3
    }
  },
  
  // Compiler warnings
  warnings: {
    "*": {
      "code-size": true,
      default: "error"
    }
  }
};