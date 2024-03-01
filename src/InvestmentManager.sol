// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import "./interfaces/IERC20.sol";
import "./tokens/ERC20.sol";
import "forge-std/console.sol";

interface ERC20Like {
    function approve(address token, address spender, uint256 value) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
    function decimals() external view returns (uint8);
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

interface LiquidityPoolLike is ERC20Like {
    function poolId() external view returns (uint64);
    function trancheId() external view returns (bytes16);
    function asset() external view returns (address);
    function share() external view returns (address);
    function totalAssets() external view returns (uint256);
    function emitDeposit(address owner, uint256 assets, uint256 shares) external;
    function emitRedeem(address owner, uint256 assets, uint256 shares) external;
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
    function transferOut(address receiver, uint256 amount) external;
}

interface TrancheTokenLike is ERC20Like {
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
}

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(address _asset, string memory _name, string memory _symbol, uint64 poolId_)
        external
        returns (address);
}

contract InvestmentManager {
    using FixedPointMathLib for uint256;

    // factories
    LiquidityPoolFactoryLike public liquidityPoolFactory;

    // Immutables
    EscrowLike public immutable escrow;

    constructor(address escrow_) {
        escrow = EscrowLike(escrow_);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(address liquidityPool, uint256 assets, address receiver) public returns (uint256 shares) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share());

        require((shares = previewDeposit(address(lp), assets)) != 0, "ZERO_SHARES");

        // mint shares to receiver
        shares = convertToShares(address(lp), assets);

        share.mint(receiver, shares);
    }

    function mint(address liquidityPool, uint256 shares, address receiver) public returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share());

        // mint shares to receiver
        share.mint(receiver, shares);

        return convertToAssets(address(lp), shares);
    }

    function withdraw(address liquidityPool, uint256 assets, address receiver, address owner)
        public
        returns (uint256 shares)
    {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share());

        shares = previewWithdraw(address(lp), assets); // No need to check for rounding error, previewMint rounds up.

        // burn shares from receiver
        share.burn(owner, shares);

        // transfer assets to owner
        EscrowLike(escrow).approve(lp.asset(), receiver, assets);
        EscrowLike(escrow).transferOut(receiver, assets);
    }

    function redeem(address liquidityPool, uint256 shares, address receiver, address owner)
        public
        returns (uint256 assets)
    {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share());

        assets = previewRedeem(address(lp), shares); // No need to check for rounding error, previewMint rounds up.

        // burn shares from receiver
        share.burn(owner, shares);

        // transfer assets to owner
        EscrowLike(escrow).approve(lp.asset(), receiver, assets);

        EscrowLike(escrow).transferOut(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function convertToShares(address liquidityPool, uint256 assets_) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 supply = ERC20(lp.asset()).balanceOf(address(lp));

        return supply == 0 ? assets_ : assets_.mulDivDown(supply, lp.totalAssets());
    }
    //  fix this . for eg line 139 should be ERC20Like(lp.share()).balanceOf(escrow). balance will always be zero as funds are not transferrede to this contract.  change it to asset too;

    function convertToAssets(address liquidityPool, uint256 shares_) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 supply = ERC20(lp.share()).balanceOf(address(lp));

        return supply == 0 ? shares_ : shares_.mulDivDown(lp.totalAssets(), supply);
    }

    function previewDeposit(address liquidityPool, uint256 assets_) public view virtual returns (uint256) {
        return convertToShares(liquidityPool, assets_);
    }

    function previewMint(address liquidityPool, uint256 shares_) public view virtual returns (uint256) {
        return convertToAssets(liquidityPool, shares_);
    }

    function previewRedeem(address liquidityPool, uint256 shares_) public view virtual returns (uint256) {
        return convertToAssets(liquidityPool, shares_);
    }

    function previewWithdraw(address liquidityPool, uint256 assets_) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 supply = ERC20(lp.asset()).balanceOf(address(lp));

        return supply == 0 ? assets_ : assets_.mulDivUp(supply, lp.totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxRedeem(address liquidityPool, address owner) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        return ERC20Like(lp.share()).balanceOf(owner);
    }

    function maxWithdraw(address liquidityPool, address owner) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 assets = ERC20Like(lp.asset()).balanceOf(owner);

        return convertToAssets(address(lp), assets);
    }
}
