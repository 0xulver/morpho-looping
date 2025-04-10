// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniversalRouter {
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable returns (uint256);

    function executeWithValue(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline,
        uint256 value
    ) external payable returns (uint256);
}