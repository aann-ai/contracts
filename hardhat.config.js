require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ethers");
require("dotenv").config();
const { REPORT_GAS, PRIVATE_KEY, API_KEY } = process.env;

module.exports = {
    solidity: {
        version: "0.8.19",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    networks: {
        hardhat: {
            forking: {
                url: "https://rpc.ankr.com/eth",
                blockNumber: 18018067
            }
        },
        arbitrum: {
            url: "https://arb1.arbitrum.io/rpc",
            accounts: [PRIVATE_KEY]
        },
        binance: {
            url: "https://rpc.ankr.com/bsc",
            accounts: [PRIVATE_KEY]
        },
        polygon: {
            url: "https://rpc.ankr.com/polygon",
            accounts: [PRIVATE_KEY]
        },
        base: {
            url: "https://rpc.ankr.com/base",
            accounts: [PRIVATE_KEY]
        },
        sepolia: {
            url: "https://rpc.ankr.com/eth_sepolia",
            accounts: [PRIVATE_KEY]
        },
        binance_testnet: {
            url: "https://rpc.ankr.com/bsc_testnet_chapel",
            accounts: [PRIVATE_KEY]
        },
        ethereum: {
            url: "https://rpc.ankr.com/eth",
            accounts: [PRIVATE_KEY]
        },
        base_goerli: {
            url: "https://rpc.ankr.com/base_goerli",
            accounts: [PRIVATE_KEY]
        }
    },
    gasReporter: {
        enabled: REPORT_GAS === "true" ? true : false,
        currency: "USD"
    },
    etherscan: {
        apiKey: API_KEY
    }
};
