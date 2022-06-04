require("@nomiclabs/hardhat-waffle");
require("hardhat-tracer");
require('@openzeppelin/hardhat-upgrades');
require('hardhat-contract-sizer')
require('hardhat-abi-exporter');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    networks: {
        // hardhat: {
        //     allowUnlimitedContractSize: true,
        // },
        local: {
            url: "http://127.0.0.1:8545",
            accounts: ['53083ce384b7cb81370800973d79c0412261310ba5c9c0cd35d7c6ec7926d0a0'],
            timeout: 100000,
        },
        BNBTest: {
            url: "http://tf-dex-preview-validator-nlb-6fd109ac8b9d390a.elb.ap-northeast-1.amazonaws.com:8545",
            accounts: ['107f9d2a50ce2d8337e0c5220574e9fcf2bf60002da5acf07718f4d531ea3faa'],
            timeout: 100000,
            gas: 6000000
        },
        BSCTestnet: {
            url: "http://tf-dex-preview-validator-nlb-6fd109ac8b9d390a.elb.ap-northeast-1.amazonaws.com:8545",
            accounts: ['107f9d2a50ce2d8337e0c5220574e9fcf2bf60002da5acf07718f4d531ea3faa'],
            timeout: 100000,
            gas: 6000000
        }
    },
    solidity: {
        version: "0.7.6",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    // contractSizer: {
    //     alphaSort: true,
    //     disambiguatePaths: false,
    //     runOnCompile: true,
    //     strict: true,
    // },
    abiExporter: {
        path: './data/abi',
        clear: true,
        flat: true,
        only: [':OldZecreyLegend$'],
        spacing: 2
    }
};
