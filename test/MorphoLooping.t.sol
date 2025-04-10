// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MorphoLooping.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SwapHelper} from "./helpers/SwapHelper.sol";

contract MorphoLoopingTest is Test {
    using SafeERC20 for IERC20;
    
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

    // Time and block constants
    uint256 constant ETHEREUM_BLOCKS_PER_DAY = 7151;
    uint256 constant TEST_PERIOD_DAYS = 7;
    uint256 constant WAD = 1e18;
    uint256 constant SAFETY_BUFFER = 0.03e18; // 3%
    
    // Add these constants near the other constants at the top of the contract
    uint256 constant INITIAL_COLLATERAL_AMOUNT = 1000;  // Base units (e.g. 1000 USDC = 1000 * 10^6)
    
    IMorpho public morpho;
    MorphoLooping public looping;
    MarketInfo[] public markets;
    SwapHelper public swapHelper;

    struct Position {
        bytes32 marketId;
        uint256 initialCollateral;
        uint256 flashLoanAmount;
        uint256 leverageAchieved;
        uint256 entryTimestamp;
    }
    Position[] private positions;

    function setUp() public {
        // Create Mainnet fork
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Initialize SwapHelper
        swapHelper = new SwapHelper();
        
        // Initialize contracts
        morpho = IMorpho(MORPHO);
        looping = new MorphoLooping(MORPHO, address(swapHelper));

        // Initialize markets array
        markets.push(MarketInfo({
            id: MARKET_PT_SUSDE,
            name: "PT-sUSDe/USDC",
            loanToken: USDC,
            collateralToken: PT_SUSDE
        }));

        // markets.push(MarketInfo({
        //     id: MARKET_USD0_USDC,
        //     name: "USD0/USDC",
        //     loanToken: USDC,
        //     collateralToken: USD0
        // }));

        // Initialize positions array with same length as markets
        delete positions; // Clear any existing positions
        positions = new Position[](markets.length);
    }

    function testQueryMarketData() public view {
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

    function getOraclePrice(address oracle) internal view returns (uint256) {
        // For testing purposes, we'll return a mock price
        // In production, this would call the actual oracle
        return 1e18; // 1:1 price ratio for simplicity
    }

    function estimateSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal view returns (uint256) {
        // For testing purposes, we'll return a fixed slippage estimate
        // In production, this would query the DEX for actual slippage estimates
        return 0.01e18; // 1% slippage
    }

    function generateSwapCalldata(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal pure returns (bytes memory) {
        // For testing purposes, we'll return empty bytes
        // In production, this would generate actual DEX swap calldata
        return "";
    }

    function calculateOptimalParams(
        MarketInfo memory market,
        uint256 initialCollateral
    ) internal view returns (
        uint256 flashLoanAmount,
        uint256 expectedCollateral,
        uint256 leverageAchieved,
        bytes memory swapData
    ) {
        IMorpho.MarketParams memory params = morpho.idToMarketParams(market.id);
        IMorpho.Market memory marketData = morpho.market(market.id);
        
        // Get current market conditions
        uint256 availableLiquidity = marketData.totalSupplyAssets - marketData.totalBorrowAssets;
        uint256 currentPrice = getOraclePrice(params.oracle);
        uint256 expectedSlippage = estimateSlippage(market.loanToken, market.collateralToken, initialCollateral);

        // Calculate optimal flash loan amount with safety buffer
        uint256 safeLltv = params.lltv - ((params.lltv * SAFETY_BUFFER) / WAD);
        
        // Prevent division by zero
        if (WAD <= safeLltv) {
            return (0, initialCollateral, WAD, ""); // Return 1x leverage if LLTV is too high
        }
        
        flashLoanAmount = (initialCollateral * safeLltv) / (WAD - safeLltv);
        
        // Cap flash loan amount based on available liquidity
        if (flashLoanAmount > availableLiquidity) {
            flashLoanAmount = availableLiquidity;
        }
        
        // Calculate expected collateral after swap
        expectedCollateral = initialCollateral + ((flashLoanAmount * (WAD - expectedSlippage)) / WAD);
        
        // Calculate achieved leverage
        leverageAchieved = (expectedCollateral * WAD) / initialCollateral;
        
        // Generate swap data (empty in test environment)
        swapData = generateSwapCalldata(
            market.loanToken,
            market.collateralToken,
            flashLoanAmount
        );
        
        return (flashLoanAmount, expectedCollateral, leverageAchieved, swapData);
    }

    function testHistoricalLoopingPerformance() public {
        // Get current block
        uint256 currentBlock = block.number;
        uint256 pastBlock = currentBlock - (ETHEREUM_BLOCKS_PER_DAY * TEST_PERIOD_DAYS);
        
        // Fork from past block FIRST
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), pastBlock);
        
        // AFTER forking, initialize all contracts and dependencies
        swapHelper = new SwapHelper();
        morpho = IMorpho(MORPHO);
        looping = new MorphoLooping(MORPHO, address(swapHelper));
        require(address(looping) != address(0), "Looping deployment failed");
        
        console.log("\n=== Historical Performance Test ===");
        console.log("Current Block:", currentBlock);
        console.log("Past Block:", pastBlock);
        console.log("Testing Period:", TEST_PERIOD_DAYS, "days");
        
        // Initial setup and measurements
        for (uint i = 0; i < markets.length; i++) {
            MarketInfo memory marketInfo = markets[i];
            
            // Get token decimals using IERC20Metadata
            uint256 decimals = IERC20Metadata(marketInfo.collateralToken).decimals();
            uint256 initialCollateral = INITIAL_COLLATERAL_AMOUNT * (10 ** decimals);
            
            // Mint initial collateral for testing
            deal(marketInfo.collateralToken, address(this), initialCollateral);
            
            // Approve looping contract to pull collateral
            IERC20(marketInfo.collateralToken).safeIncreaseAllowance(address(looping), initialCollateral);
            
            // Calculate optimal parameters for leverage
            (
                uint256 flashLoanAmount,
                ,  // expectedCollateral
                uint256 leverageAchieved,
                bytes memory swapData
            ) = calculateOptimalParams(marketInfo, initialCollateral);

            // Execute leverage strategy
            IMorpho.MarketParams memory marketParams = morpho.idToMarketParams(marketInfo.id);
            looping.executeStrategy(
                initialCollateral,
                MorphoLooping.FlashLoanParams({
                    loanToken: marketInfo.loanToken,
                    collateralToken: marketInfo.collateralToken,
                    flashLoanAmount: flashLoanAmount,
                    initialCollateral: initialCollateral,
                    swapData: swapData,
                    marketParams: marketParams
                })
            );

            // // Store position details
            // positions[i] = Position({
            //     marketId: marketInfo.id,
            //     initialCollateral: initialCollateral,
            //     flashLoanAmount: flashLoanAmount,
            //     leverageAchieved: leverageAchieved,
            //     entryTimestamp: block.timestamp
            // });
        }
        
        // Roll forward to present and measure results
        // vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // for (uint i = 0; i < markets.length; i++) {
        //     MarketInfo memory marketInfo = markets[i];
        //     Position memory position = positions[i];
            
        //     // Calculate final values
        //     uint256 finalCollateralBalance = IERC20(marketInfo.collateralToken).balanceOf(address(this));
        //     uint256 finalLoanBalance = IERC20(marketInfo.loanToken).balanceOf(address(this));
            
        //     // Calculate profit/loss in USD terms
        //     (uint256 profitUsd, bool isProfit) = _calculateProfitLoss(
        //         marketInfo,
        //         position,
        //         finalCollateralBalance,
        //         finalLoanBalance
        //     );
            
        //     console.log("\nMarket Performance:", marketInfo.name);
        //     console.log("Leverage Used:", position.leverageAchieved);
        //     console.log("Profit/Loss (USD):", isProfit ? "+" : "-", profitUsd);
        //     console.log("APR:", _calculateAPR(profitUsd, position.initialCollateral));
        // }
    }

    function _executeLoopingStrategy(MarketInfo memory market) internal {
        // Implement looping logic here
        // 1. Supply initial collateral
        // 2. Borrow loan token
        // 3. Swap loan for more collateral
        // 4. Repeat until desired leverage reached
        // 5. Maintain safe health factor
    }

    function _calculateProfitLoss(
        MarketInfo memory market,
        Position memory position,
        uint256 finalCollateral,
        uint256 finalLoan
    ) internal view returns (uint256 profitUsd, bool isProfit) {
        // Use oracle prices to convert all values to USD
        // Calculate net profit/loss considering:
        // - Change in collateral value
        // - Outstanding loan value
        // - Accrued interest
    }

    function _calculateAPR(uint256 profitUsd, uint256 initialLoan) internal pure returns (uint256) {
        // Convert the test period (7 days) to an annual rate
        uint256 daysInYear = 365;
        uint256 annualizationFactor = daysInYear * 1e18 / TEST_PERIOD_DAYS;
        
        // Calculate APR: (profit / initial_loan) * annualization_factor
        // Note: profitUsd and initialLoan should be in the same decimals
        if (initialLoan == 0) return 0;
        
        // Add safety check for division
        if (profitUsd == 0) return 0;
        
        return (profitUsd * annualizationFactor) / initialLoan;
    }
}
