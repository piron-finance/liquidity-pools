pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../BaseTest.t.sol";

contract InvestmentManagerTest is BaseTest {
    function setUp() public virtual override {
        BaseTest.setUp();
        console.log("Liquidity pool deployed");
    }
}
