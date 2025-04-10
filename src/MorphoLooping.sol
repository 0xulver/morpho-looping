// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMorpho} from "./interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "./interfaces/IMorphoCallbacks.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MorphoLooping is IMorphoFlashLoanCallback {
    using SafeERC20 for IERC20;

    IMorpho public immutable morpho;
    ISwapRouter public immutable swapRouter;

    constructor(address _morpho, address _swapRouter) {
        morpho = IMorpho(_morpho);
        swapRouter = ISwapRouter(_swapRouter);
    }

    struct FlashLoanParams {
        address loanToken;
        address collateralToken;
        uint256 flashLoanAmount;
        uint256 initialCollateral;
        bytes swapData;
        IMorpho.MarketParams marketParams;
    }

    function executeStrategy(
        uint256 initialCollateral,
        FlashLoanParams calldata params
    ) external {
        // Transfer initial collateral from user
        IERC20(params.collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            initialCollateral
        );

        // Execute flash loan
        morpho.flashLoan(
            params.loanToken,
            params.flashLoanAmount,
            abi.encode(params, msg.sender)
        );
    }

    function onMorphoFlashLoan(
        uint256 assets,
        bytes calldata data
    ) external {
        require(msg.sender == address(morpho), "UNAUTHORIZED");
        
        (FlashLoanParams memory params, address user) = abi.decode(
            data,
            (FlashLoanParams, address)
        );

        // 1. Swap flash loaned assets to collateral
        IERC20(params.loanToken).safeIncreaseAllowance(address(swapRouter), assets);
        (bool success, ) = address(swapRouter).call(params.swapData);
        require(success, "SWAP_FAILED");

        // 2. Supply all collateral
        uint256 totalCollateral = IERC20(params.collateralToken).balanceOf(address(this));
        IERC20(params.collateralToken).safeIncreaseAllowance(address(morpho), totalCollateral);
        morpho.supplyCollateral(params.marketParams, totalCollateral, user, "");

        // 3. Borrow to repay flash loan
        morpho.borrow(params.marketParams, assets, 0, address(this), address(this));

        // 4. Approve flash loan repayment
        IERC20(params.loanToken).safeIncreaseAllowance(address(morpho), assets);
    }
}
