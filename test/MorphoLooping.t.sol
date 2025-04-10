// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

interface IMorpho {
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    struct Market {
        uint128 totalSupplyAssets;
        uint128 totalSupplyShares;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
        uint128 lastUpdate;
        uint128 fee;
    }

    function market(bytes32 id) external view returns (Market memory);
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory);
}

contract MorphoLoopingTest is Test {
    // Market struct to store market parameters
    struct MarketInfo {
        bytes32 id;  // Market ID from Morpho Blue
        string name; // Human readable name for logging
        address loanToken;
        address collateralToken;
    }

    // Morpho Blue address on Mainnet
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    
    // Markets from SPEC.md
    bytes32 constant MARKET_PT_SUSDE = 0x8d177cc2597296e8ff4816be51fe2482add89de82bdfaba3118c7948a6b2bc02;
    bytes32 constant MARKET_USD0_USDC = 0xa59b6c3c6d1df322195bfb48ddcdcca1a4c0890540e8ee75815765096c1e8971;

    // Token addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PT_SUSDE = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;  // PT-sUSDe-29MAY2025
    address constant USD0 = 0x1d08E7adC263CfC70b1BaBe6dC5Bb339c16Eec52;  // USD0

    IMorpho public morpho;
    MarketInfo[] public markets;

    function setUp() public {
        // Create Mainnet fork
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Initialize Morpho interface
        morpho = IMorpho(MORPHO);

        // First add the required markets from SPEC.md
        markets.push(MarketInfo({
            id: MARKET_PT_SUSDE,
            name: "PT-sUSDe/USDC",
            loanToken: USDC,
            collateralToken: PT_SUSDE
        }));

        markets.push(MarketInfo({
            id: MARKET_USD0_USDC,
            name: "USD0/USDC",
            loanToken: USDC,
            collateralToken: USD0
        }));
    }

    function testQueryMarketData() public {
        console.log("\n=== Querying Market Data ===");
        
        for (uint i = 0; i < markets.length; i++) {
            MarketInfo memory marketInfo = markets[i];
            IMorpho.Market memory market = morpho.market(marketInfo.id);
            IMorpho.MarketParams memory params = morpho.idToMarketParams(marketInfo.id);
            
            console.log("\nMarket:", marketInfo.name);
            console.log("ID:", uint256(marketInfo.id));
            console.log("Market Data:");
            console.log("  Total Supply Assets:", market.totalSupplyAssets);
            console.log("  Total Borrow Assets:", market.totalBorrowAssets);
            console.log("  Utilization:", market.totalBorrowAssets * 100 / market.totalSupplyAssets, "%");
            console.log("  Fee:", market.fee);
            console.log("Market Params:");
            console.log("  LLTV:", params.lltv);
            console.log("  Oracle:", params.oracle);
            console.log("  IRM:", params.irm);
        }
    }
}
