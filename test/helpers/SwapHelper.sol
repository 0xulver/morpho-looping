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
    address constant SUSDE_PENDLE_MARKET = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
    
    // Router addresses
    address constant UNIV4_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
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
        // Transfer USDC from recipient to this contract
        IERC20(USDC).safeTransferFrom(recipient, address(this), amountIn);

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
            currency0: Currency.wrap(SUSDE),
            currency1: Currency.wrap(USDC),
            fee: 300,
            tickSpacing: 6,
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

        bytes[] memory params = new bytes[](3);
        params[0] = paramsBytes;
        params[1] = abi.encode(key.currency1, amountIn);
        params[2] = abi.encode(key.currency0, 1);

        // Combine actions and parameters into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actionsBytes, params);

        uint256 deadline = block.timestamp + 20;

        console.log("block.timestamp:", block.timestamp);

        try uniRouter.execute(commands, inputs, deadline) {
            amountOut = IERC20(SUSDE).balanceOf(address(this));
            console.log("sUSDe balance after swap:", amountOut);
            IERC20(SUSDE).transfer(recipient, amountOut);   
        } catch (bytes memory reason) {
            console.log("Swap failed with error:");
            console.logBytes(reason);
            revert("Swap failed");
        }

        return amountOut;
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

    // function swapSUSDeToPTSUSDe(
    //     address recipient,
    //     uint256 amountIn
    // ) external returns (uint256 amountOut) {
    //     console.log("Swapping sUSDe to PT-sUSDe");
    //     console.log("Amount in:", amountIn);

    //     // Transfer sUSDe from recipient to this contract
    //     IERC20(SUSDE).safeTransferFrom(recipient, address(this), amountIn);

    //     // Approve sUSDe spending by Pendle Router
    //     IERC20(SUSDE).safeIncreaseAllowance(address(pendleRouter), amountIn);

    //     // Create TokenInput struct
    //     IPendleRouter.TokenInput memory tokenInput = IPendleRouter.TokenInput({
    //         tokenIn: SUSDE,
    //         netTokenIn: amountIn,
    //         tokenMintSy: 0xD288755556c235afFfb6316702719C32bD8706e8,
    //         pendleSwap: address(0),  // No aggregator needed
    //         swapData: IPendleRouter.SwapData({
    //             extRouter: address(0),
    //             needScale: false,
    //             swapType: 0,
    //             extCalldata: ""
    //         })
    //     });

    //     // Create ApproxParams struct using recommended values from docs
    //     IPendleRouter.ApproxParams memory approxParams = IPendleRouter.ApproxParams({
    //         guessMin: 0,
    //         guessMax: type(uint256).max,
    //         guessOffchain: 0,  // Strictly 0 as per docs
    //         maxIteration: 256,
    //         eps: 1e14  // 0.01% unused as per docs
    //     });

    //     // Create empty LimitOrderData
    //     IPendleRouter.LimitOrderData memory limitOrderData = IPendleRouter.LimitOrderData({
    //         limitRouter: address(0),
    //         epsSkipMarket: 0,
    //         normalFills: new IPendleRouter.FillOrderParams[](0),
    //         flashFills: new IPendleRouter.FillOrderParams[](0),
    //         optData: ""
    //     });

    //     // Perform swap using Pendle Router
    //     try pendleRouter.swapExactTokenForPt(
    //         address(this),           // receiver
    //         SUSDE_PENDLE_MARKET, // market
    //         1,                   // minPtOut (1 = no slippage protection)
    //         approxParams,        // approxParams
    //         tokenInput,          // tokenInput
    //         limitOrderData       // limitOrderData
    //     ) returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm) {
    //         amountOut = netPtOut;
    //         console.log("PT-sUSDe received:", amountOut);
    //     } catch (bytes memory reason) {
    //         console.log("Swap failed with error:");
    //         console.logBytes(reason);
    //         console.logBytes4(bytes4(reason));
    //         console.log("sUSDe balance:", IERC20(SUSDE).balanceOf(address(this)));
    //         console.log("PT-sUSDe balance:", IERC20(PT_SUSDE).balanceOf(address(this)));
    //         revert("Swap failed");
    //     }

    //     return amountOut;
    // }

    function swapSUSDeToPTSUSDe(
        address recipient,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        console.log("Swapping sUSDe to PT-sUSDe");
        console.log("Amount in:", amountIn);

        // Transfer sUSDe from recipient to this contract
        IERC20(SUSDE).safeTransferFrom(recipient, address(this), amountIn);

        // Approve sUSDe spending by Pendle Router
        IERC20(SUSDE).safeIncreaseAllowance(address(pendleRouter), amountIn);

        // Create TokenInput struct with similar structure to successful tx
        IPendleRouter.TokenInput memory tokenInput = IPendleRouter.TokenInput({
            tokenIn: SUSDE,
            netTokenIn: amountIn,
            tokenMintSy: SUSDE,  // Using same token as tokenMintSy like in successful tx
            pendleSwap: address(0),
            swapData: IPendleRouter.SwapData({
                swapType: 0,
                extRouter: address(0),
                extCalldata: "",
                needScale: false
            })
        });

        // Create ApproxParams struct using values similar to successful tx
        IPendleRouter.ApproxParams memory approxParams = IPendleRouter.ApproxParams({
            guessMin: amountIn / 2,  // Conservative estimate
            guessMax: amountIn * 2,  // Conservative estimate
            guessOffchain: amountIn,  // Use input amount as guess
            maxIteration: 30,         // Same as successful tx
            eps: 10000000000000      // Same as successful tx
        });

        // Create empty LimitOrderData matching successful tx format
        IPendleRouter.LimitOrderData memory limitOrderData = IPendleRouter.LimitOrderData({
            limitRouter: address(0),
            epsSkipMarket: 0,
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });

        // Perform swap using Pendle Router
        try pendleRouter.swapExactTokenForPt(
            recipient,
            SUSDE_PENDLE_MARKET,
            1,  // minPtOut - consider setting this to a reasonable minimum based on amountIn
            approxParams,
            tokenInput,
            limitOrderData
        ) returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm) {
            amountOut = netPtOut;
            console.log("PT-sUSDe received:", amountOut);
        } catch (bytes memory reason) {
            console.log("Swap failed with error:");
            console.logBytes(reason);
            console.logBytes4(bytes4(reason));
            console.log("sUSDe balance:", IERC20(SUSDE).balanceOf(address(this)));
            console.log("PT-sUSDe balance:", IERC20(PT_SUSDE).balanceOf(address(this)));
            revert("Swap failed");
        }

        return amountOut;
    }
}
