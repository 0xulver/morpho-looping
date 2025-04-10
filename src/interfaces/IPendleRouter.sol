// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPendleRouter {
    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain;
        uint256 maxIteration;
        uint256 eps;
        bool useStableConfig;
        bool useStablePrice;
        bool doApprox;
    }

    struct TokenInput {
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        address bulk;
        bytes data;
    }

    struct SwapData {
        address extRouter;
        bool needScale;
        uint8 swapType;
        bytes extCalldata;
    }

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        bytes calldata // limitOrderData
    ) external returns (uint256 netPtOut);

    function swapExactTokenForYt(
        address receiver,
        address market,
        uint256 minYtOut,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        bytes calldata // limitOrderData
    ) external returns (uint256 netYtOut);

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        uint256 minTokenOut,
        ApproxParams calldata approxParams,
        address tokenOut,
        bytes calldata // limitOrderData
    ) external returns (uint256 netTokenOut);
}