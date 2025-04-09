// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract MorphoLoopingTest is Test {
    // Market struct to store market parameters
    struct MarketInfo {
        bytes32 id;  // Market ID from Morpho Blue
        string name; // Human readable name for logging
        address loanToken;
        address collateralToken;
    }

    // Markets from SPEC.md
    bytes32 constant MARKET_PT_SUSDE = 0x8d177cc2597296e8ff4816be51fe2482add89de82bdfaba3118c7948a6b2bc02;
    bytes32 constant MARKET_USD0_USDC = 0xa59b6c3c6d1df322195bfb48ddcdcca1a4c0890540e8ee75815765096c1e8971;

    // Token addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PT_SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;  // PT-sUSDe-29MAY2025
    address constant USD0 = 0x0000000000000000000000000000000000000000;  // USD0

    // Sample markets
    MarketInfo[] public markets;

    function setUp() public {
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

        // TODO: Add additional markets here
        // We can add more markets like WETH/WSTETH, USDC/WSTETH, etc.
    }

    function testListMarkets() public {
        console.log("Analyzing", markets.length, "markets:");
        
        for (uint i = 0; i < markets.length; i++) {
            MarketInfo memory market = markets[i];
            console.log("Market", i, "-", market.name);
            console.log("  ID:", uint256(market.id));
            console.log("  Loan Token:", market.loanToken);
            console.log("  Collateral:", market.collateralToken);
        }
    }
}
