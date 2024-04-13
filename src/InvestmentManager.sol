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
    function asset_() external view returns (address);
    function share_() external view returns (address);
    function epochInProgress() external view returns (bool);
    function totalAssets() external view returns (uint256);
    function emitDeposit(address owner, uint256 assets, uint256 shares) external;
    function emitRedeem(address owner, uint256 assets, uint256 shares) external;
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
    function transferOut(address receiver, uint256 amount) external returns (bool);
}

interface TrancheTokenLike is ERC20Like {
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
}

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(address _asset, string memory _name, string memory _symbol, uint64 poolId_)
        external
        returns (address);
}

struct InvestmentState {

    uint256 totalDeposits;
    uint256 totalShares;
    
    uint128 pendingDeposit;
    uint128 pendingWithdraw;


    uint128 pendingRedeem;
    uint128 maxWithdraw;

    bool pendingCancelDeposit;
    bool pendingCancelRedeem;

    bool exists;
}

contract InvestmentManager {
    using FixedPointMathLib for uint256; 

 mapping (address liquidityPool => mapping(address investor => InvestmentState)) public investments;


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

    function deposit(address liquidityPool, uint256 assets, address receiver) public returns (bool) {
        //   LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
          uint128 amount = uint128(assets);

          InvestmentState storage state = investments[liquidityPool][receiver];
          state.pendingDeposit = state.pendingDeposit + amount;
          state.exists = true;

          return true;
    }

    function processDeposit(address liquidityPool,  address receiver) external returns (uint256 shares) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share_());

        InvestmentState storage state = investments[liquidityPool][receiver];
        uint128 amount = state.pendingDeposit;


        require((shares = previewDeposit(address(lp), amount, receiver)) != 0, "ZERO_SHARES");

        shares = convertToShares(address(lp), amount, receiver);

        state.pendingDeposit = 0;
        state.totalDeposits = amount;

        share.mint(receiver, shares);
        return shares;
      
    }

    function cancelPendingDeposit(address liquidityPool, address owner) external returns(uint128) {
          LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
          require (lp.epochInProgress(), "Manager/Epoch has closed");

          InvestmentState storage state = investments[liquidityPool][owner];
          uint128 amount = state.pendingDeposit;

         EscrowLike(escrow).approve(lp.asset_(), owner, amount);
         require ( EscrowLike(escrow).transferOut(owner, amount), "Manager/ deposit refund failed");

         state.pendingDeposit = 0;

        return amount;
    }

    function increaseDepositOrder(address liquidityPool, address receiver, uint256 additionalAssets) public returns(bool) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
          require (lp.epochInProgress(), "Manager/Epoch has closed");

          InvestmentState storage state = investments[liquidityPool][receiver];

          require(state.exists && state.pendingDeposit != 0, "Manager/Error increasing deposit");
          uint128 amount = uint128(additionalAssets);

         state.pendingDeposit += amount;

          return true;
    }

     function decreaseDepositOrder(address liquidityPool, address receiver, uint256 assets) public returns(bool) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
          require (lp.epochInProgress(), "Manager/Epoch has closed");


          InvestmentState storage state = investments[liquidityPool][receiver];

          require(state.exists && state.pendingDeposit != 0, "Manager/Error increasing deposit");
          require(state.pendingDeposit > assets, "Manager/ Not enough assets");
          uint128 amount = uint128(assets);

         state.pendingDeposit -= amount;

          return true;
    }


    function mint(address liquidityPool, uint256 shares, address receiver) public returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share_());

        // mint shares to receiver
        share.mint(receiver, shares);

        return convertToAssets(address(lp), shares, receiver);
    }

    function withdraw(address liquidityPool, uint256 assets, address receiver, address owner)
        public
        returns (uint256 shares)
    {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share_());

        shares = previewWithdraw(address(lp), assets); // No need to check for rounding error, previewMint rounds up.

        // burn shares from receiver
        share.burn(owner, shares);

        // transfer assets to owner
        EscrowLike(escrow).approve(lp.asset_(), receiver, assets);
        EscrowLike(escrow).transferOut(receiver, assets);
    }

    function redeem(address liquidityPool, uint256 shares, address receiver, address owner)
        public
        returns (uint256 assets)
    {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share_());

        assets = previewRedeem(address(lp), shares, receiver); // No need to check for rounding error, previewMint rounds up.

        // burn shares from receiver
        share.burn(owner, shares);

        // transfer assets to owner
        EscrowLike(escrow).approve(lp.asset_(), receiver, assets);

        EscrowLike(escrow).transferOut(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function convertToShares(address liquidityPool, uint256 assets, address receiver) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 totalAssets = ERC20(lp.asset_()).balanceOf(address(escrow));
        uint256 investorContribution = calculateInvestorContribution(liquidityPool, receiver);
        
        // Ensure investorContribution is not zero to avoid division by zero
        require(investorContribution > 0, "Investor contribution cannot be zero");

        return assets.mulDivDown(investorContribution, totalAssets); 
    }



    function convertToAssets(address liquidityPool, uint256 shares, address receiver) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 totalShares = ERC20(lp.share_()).totalSupply(); // Total supply of shares in the pool
        uint256 totalAssets = ERC20(lp.asset_()).balanceOf(address(escrow));
        uint256 investorContribution = calculateInvestorContribution(liquidityPool, receiver);
        
        // Ensure investorContribution is not zero to avoid division by zero
        require(investorContribution > 0, "Investor contribution cannot be zero");

        // Convert shares back to assets based on the investor's contribution
        return shares.mulDivDown(totalAssets, investorContribution).mulDivDown(totalShares, totalAssets);
    }


    function calculateInvestorContribution(address liquidityPool, address investor) public view returns (uint256) {
         LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        require(lp.epochInProgress(), "Manager/ Epoch in progress");

        InvestmentState storage state = investments[liquidityPool][investor];
        require(state.exists && state.totalDeposits != 0, "Manager/You have no fufilled orders");

        uint256 investorBalance = state.totalDeposits;
        uint256 totalInvestments = ERC20(lp.asset_()).balanceOf(address(escrow));

        return investorBalance * 100 / totalInvestments;
    }

    function previewDeposit(address liquidityPool, uint256 assets_, address receiver) public view virtual returns (uint256) {
        return convertToShares(liquidityPool, assets_, receiver);
    }

    function previewMint(address liquidityPool, uint256 shares_, address receiver) public view virtual returns (uint256) {
        return convertToAssets(liquidityPool, shares_, receiver);
    }

    function previewRedeem(address liquidityPool, uint256 shares_, address receiver) public view virtual returns (uint256) {
        return convertToAssets(liquidityPool, shares_, receiver);
    }

    function previewWithdraw(address liquidityPool, uint256 assets_) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 supply = ERC20(lp.asset_()).balanceOf(address(lp));

        return supply == 0 ? assets_ : assets_.mulDivUp(supply, lp.totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxRedeem(address liquidityPool, address owner) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        return ERC20Like(lp.share_()).balanceOf(owner);
    }

    function maxWithdraw(address liquidityPool, address owner) public view virtual returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 assets = ERC20Like(lp.share_()).balanceOf(owner);

        return convertToAssets(address(lp), assets, owner);
    }
}
