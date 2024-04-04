pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../BaseTest.t.sol";

contract LiquidityPoolTest is BaseTest {
    function setUp() public virtual override {
        BaseTest.setUp();
        console.log("Liquidity pool deployed");
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function test_deposit() public {
        uint256 amount = 100;
        vm.startPrank(investor);
        Token1.approve(address(Pool), amount);
        Pool.deposit(amount, investor);
        vm.stopPrank();
        assertEq(Token1.balanceOf(address(escrow)), amount);
    }

    function test_mint() public {
        uint256 amount = 100;
        vm.startPrank(investor);
        Token1.approve(address(Pool), amount);
        Pool.mint(amount, investor);
        vm.stopPrank();
        assertEq(Token2.balanceOf(investor), amount);
    }

    function test_withdraw() public {
        uint256 amount = 100;
        vm.startPrank(investor);
        Token1.approve(address(Pool), amount);
        Pool.deposit(amount, investor);
        vm.stopPrank();
        assertEq(Token1.balanceOf(address(escrow)), amount);
        vm.startPrank(investor);
        Pool.withdraw(amount, investor, investor);
        vm.stopPrank();
        assertEq(Token1.balanceOf(address(escrow)), 0);
    }

    function test_redeem() public {
        uint256 amount = 100;
        vm.startPrank(investor);
        Token1.approve(address(Pool), amount);
        Pool.deposit(amount, investor);
        vm.stopPrank();
        assertEq(Token1.balanceOf(address(escrow)), amount);
        vm.startPrank(investor);
        Pool.redeem(amount, investor, investor);
        vm.stopPrank();
        assertEq(Token2.balanceOf(investor), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // temporary test. refactor convert to assets and shares

    function test_convertToAssets() public {
        uint256 amount = 100;
        assertEq(Pool.convertToAssets(amount), 100);
    }

    function test_convertToShares() public {
        uint256 amount = 100;
        assertEq(Pool.convertToShares(amount), 100);
    }

    function test_previewDeposit() public {
        uint256 amount = 100;
        assertEq(Pool.previewDeposit(amount), 100);
    }

    function test_previewWithdraw() public {
        uint256 amount = 100;
        assertEq(Pool.previewWithdraw(amount), 100);
    }

    function test_previewMint() public {
        uint256 amount = 100;
        assertEq(Pool.previewMint(amount), 100);
    }

    function test_previewRedeem() public {
        uint256 amount = 100;
        assertEq(Pool.previewRedeem(amount), 100);
    }

    // function test_totalAssets() public {
    //     assertEq(Pool.totalAssets(), 0);
    // }

    function test_maxRedeem() public {
        assertEq(Pool.maxRedeem(investor), Token2.balanceOf(investor));
    }

    function test_maxWithdraw() public {
        assertEq(Pool.maxWithdraw(investor), Token1.balanceOf(investor));
    }
}
