pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// import contracts

import {IERC20} from "../src/interfaces/IERC20.sol";
import {IERC7575} from "../src/interfaces/IERC7575.sol";

// tokens
import {AssetToken, Token} from "../src/tokens/AssetToken.sol";
import {ShareToken} from "../src/tokens/ShareToken.sol";

// utils
import {FixedPointMathLib} from "../src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "../src/utils/SafeTransferLib.sol";

// core contracts
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, LiquidityPoolFactoryLike} from "../src/factories/PoolFactory.sol";
import {InvestmentManager, LiquidityPoolLike} from "../src/InvestmentManager.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";

contract BaseTest is Test {
    Token public Token1;
    IERC20 public Token2;

    Escrow public escrow;
    InvestmentManager public investmentManager;
    LiquidityPoolFactory public liquidityPoolFactory;
    LiquidityPool public Pool;

    address investor = makeAddr("investor");
    address nonMember = makeAddr("nonMember");
    address randomUser = makeAddr("randomUser");

    function setUp() public virtual {
        vm.startPrank(investor);
        Token1 = new AssetToken(1000000, "usdss", 18, "usdt");
        vm.stopPrank();
        Token2 = new ShareToken();

        escrow = new Escrow();
        investmentManager = new InvestmentManager(address(escrow));
        liquidityPoolFactory = new LiquidityPoolFactory();

        address pool_ = liquidityPoolFactory.newLiquidityPool(
            1,
            0x00000000000000000000000000000003,
            address(Token1),
            address(Token2),
            address(investmentManager),
            address(escrow)
        );

        Pool = LiquidityPool(pool_);
    }

    // function test_deposit() public {
    //     // LiquidityPool lp = LiquidityPool(Pool);
    //     uint256 amount = 1000;

    //     Token1.approve(address(Pool), amount);
    //     investmentManager.deposit(address(Pool), amount, investor);
    //     console.log("pool", address(Pool));
    //     console.log("investor", Token1.balanceOf(investor));
    // }

    // function test_LiquidityDeposit() public {
    //     // LiquidityPool lp = LiquidityPool(Pool);
    //     uint256 amount = 500000;
    //     vm.startPrank(investor);
    //     Token1.approve(address(Pool), amount);
    //     console.log("balance of investor", Token1.balanceOf(investor));
    //     console.log("allowance", Token1.allowance(investor, address(Pool)));
    //     vm.stopPrank();
    // }
}
