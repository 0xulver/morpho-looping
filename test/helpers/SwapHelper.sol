// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniversalRouter} from "universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPendleRouter} from "../../src/interfaces/IPendleRouter.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";

contract SwapHelper is Test {
    using SafeERC20 for IERC20;

    // Constants for sqrt price limits
    uint160 constant MIN_SQRT_RATIO = 4295128739;
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

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
        console.log("Amount in:", amountIn);

        // Mint initial collateral for testing
        deal(USDC, address(this), amountIn);

        IPermit2 permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        // Approve USDC spending by Permit2
        uint256 currentAllowance = IERC20(USDC).allowance(address(this), address(permit2));
        if (currentAllowance < amountIn) {
            IERC20(USDC).approve(address(permit2), type(uint256).max);
        }

        // Use Permit2 to grant allowance to Universal Router
        uint160 allowanceAmount = uint160(amountIn);
        uint48 expiration = uint48(block.timestamp + 3600);
        IPermit2(permit2).approve(
            USDC,
            address(uniRouter),
            allowanceAmount,
            expiration
        );

        // Step 1: USDC -> sUSDe (via Uniswap V4)
        bytes memory commands = abi.encodePacked(uint8(0x10));

        // Encode V4Router actions
        bytes memory actionsBytes = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Configure the pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(SUSDE),
            fee: 300,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Check token ordering and set zeroForOne accordingly
        bool zeroForOne = uint256(uint160(USDC)) < uint256(uint160(SUSDE));

        // Encode parameters for SWAP_EXACT_IN_SINGLE
        bytes memory paramsBytes = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: uint128(amountIn),
                amountOutMinimum: 1,
                hookData: bytes("")
            })
        );

        // Combine actions and parameters into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actionsBytes, paramsBytes);

        uint256 deadline = block.timestamp + 20;

        try uniRouter.execute(commands, inputs, deadline) {
            amountOut = IERC20(SUSDE).balanceOf(recipient);
            console.log("sUSDe balance after swap:", amountOut);
        } catch (bytes memory reason) {
            console.log("Swap failed with error:");
            console.logBytes(reason);
            revert("Swap failed");
        }

        return amountOut;
    }

    function _generateUniV4Swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (bytes memory) {
        // Command for V4 swap
        bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Encode the parameters for the swap
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            actions,
            tokenIn,
            tokenOut,
            3000, // fee
            address(this), // recipient
            amountIn,
            0 // amountOutMinimum
        );

        return abi.encode(commands, inputs);
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
