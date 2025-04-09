// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract MorphoLoopingTest is Test {
    uint256 internal baseFork;

    function setUp() public {
        // Create Base mainnet fork
        baseFork = vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        
        // Ensure we're on Base mainnet
        require(block.chainid == 8453, "Not forked with Base");
    }

    function testForkBase() public {
        // Verify we're on Base network
        assertEq(block.chainid, 8453);
    }
}