// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/contracts/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/contracts/interfaces/IV4Router.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {IPendleRouter} from "../../src/interfaces/IPendleRouter.sol";

contract SwapHelper is Test {
    using SafeERC20 for IERC20;

    // Token addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant PT_SUSDE = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;  // PT-sUSDe-29MAY2025
    
    // Market ID
    bytes32 constant MARKET_PT_SUSDE = 0x8d177cc2597296e8ff4816be51fe2482add89de82bdfaba3118c7948a6b2bc02;
    
    // Router addresses
    address constant UNIV4_ROUTER = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
    address constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    IUniversalRouter public uniRouter;
    IPendleRouter public pendleRouter;

    constructor() {
        uniRouter = IUniversalRouter(UNIV4_ROUTER);
        pendleRouter = IPendleRouter(PENDLE_ROUTER);
    }

    function swapUSDCtoPTSUSDe(
        address recipient,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        console.log("Swapping USDC to PT-sUSDe");

        // Step 1: USDC -> sUSDe (via Uniswap V4)
        bytes memory uniswapData = _generateUniV4Swap(
            USDC,
            SUSDE,
            amountIn
        );
        
        // Execute Uniswap swap
        IERC20(USDC).safeIncreaseAllowance(UNIV4_ROUTER, amountIn);
        (bool success1, ) = UNIV4_ROUTER.call(uniswapData);
        require(success1, "UNISWAP_SWAP_FAILED");
        
        // Get sUSDe balance after swap
        uint256 sUsdeAmount = IERC20(SUSDE).balanceOf(address(this));
        console.log("sUSDe amount after Uniswap V4 swap:", sUsdeAmount);
        
        // Step 2: sUSDe -> PT-sUSDe (via Pendle)
        // bytes memory pendleData = _generatePendleSwap(
        //     SUSDE,
        //     sUsdeAmount
        // );
        
        // // Execute Pendle swap
        // IERC20(SUSDE).safeIncreaseAllowance(PENDLE_ROUTER, sUsdeAmount);
        // (bool success2, ) = PENDLE_ROUTER.call(pendleData);
        // require(success2, "PENDLE_SWAP_FAILED");
        
        // // Get final PT-sUSDe amount
        // amountOut = IERC20(PT_SUSDE).balanceOf(address(this));
        
        // // Transfer result to recipient
        // IERC20(PT_SUSDE).safeTransfer(recipient, amountOut);
        
        return amountOut;
    }

    function _generateUniV4Swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (bytes memory) {
        // Create pool key for the token pair
        PoolKey memory key = PoolKey({
            currency0: tokenIn < tokenOut ? tokenIn : tokenOut,
            currency1: tokenIn < tokenOut ? tokenOut : tokenIn,
            fee: 3000, // 0.3% fee tier
            tickSpacing: 60,
            hooks: address(0) // No hooks
        });

        // Determine if we're swapping from token0 to token1
        bool zeroForOne = tokenIn == key.currency0;

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: uint128(amountIn),
                amountOutMinimum: 0, // TODO: Add slippage protection
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(tokenIn, amountIn);
        params[2] = abi.encode(tokenOut, 0); // Minimum output amount

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Return the final encoded call data
        return abi.encodeWithSelector(
            IUniversalRouter.execute.selector,
            commands,
            inputs,
            block.timestamp + 20 // deadline: 20 seconds from now
        );
    }

    function _generatePendleSwap(
        address tokenIn,
        uint256 amountIn
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "swapExactTokensForTokens(address,uint256)",
            tokenIn,
            amountIn
        );
    }

    // Mock functions to simulate swaps for testing
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // Mock exchange rate 1:1 for testing
        amountOut = amountIn;
        
        // Simulate token transfer
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        
        return amountOut;
    }

    function swapExactTokensForTokens(
        address tokenIn,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // Mock exchange rate 1:1 for testing
        amountOut = amountIn;
        
        // Simulate token transfer
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(PT_SUSDE).safeTransfer(msg.sender, amountOut);
        
        return amountOut;
    }
}
