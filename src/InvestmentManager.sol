// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import "./interfaces/IERC20.sol";
import "./tokens/ERC20.sol"; //what does it dop again?
import "hardhat/console.sol";

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



interface LiquidityPoolFactoryLike {
    function newLiquidityPool(address _asset, string memory _name, string memory _symbol, uint64 poolId_)
        external
        returns (address);
}

struct InvestmentState {

    uint256 totalDeposits;
    uint256 totalShares;
    
    uint256 pendingDeposit;
    uint256 pendingWithdraw;


    uint256 pendingRedeem;
    uint256 maxWithdraw;

    uint256 investorContribution;

    bool exists;
}
// what works
// deposit, increase, decrease, cancel, mint, withdraw
//doesnt work convert to assets
contract InvestmentManager {
    using FixedPointMathLib for uint256; 
    uint256 public totalDeposits;

 mapping (address liquidityPool => mapping(address investor => InvestmentState)) public investments;


    // factories
    LiquidityPoolFactoryLike public liquidityPoolFactory;

    // Immutables
    EscrowLike public immutable escrow;
    EscrowLike public immutable poolEscrow;
    uint256 public immutable interestRate;

    constructor(address escrow_, address poolEscrow_, uint256 interestRate_) {
        escrow = EscrowLike(escrow_);
        poolEscrow = EscrowLike(poolEscrow_);
        interestRate = interestRate_;

    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(address liquidityPool, uint256 assets, address receiver) public returns (bool) {
          totalDeposits += assets;

          InvestmentState storage state = investments[liquidityPool][receiver];
          state.pendingDeposit = state.pendingDeposit + assets;
          
          state.exists = true;

          return true;
    }

    function processDeposit(address liquidityPool, uint256 assets,  address receiver) internal returns (uint256 shares) {
       
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);

        ERC20Like share = ERC20Like(lp.share_());
        InvestmentState storage state = investments[liquidityPool][receiver];
        require(state.pendingDeposit == assets, "Mananger/partial execution prohibited");     

        state.totalShares = convertToShares(address(lp),  receiver, assets);
         console.log("f", shares);
        require(shares  > 0, "ZERO_SHARES");

        state.totalDeposits = state.pendingDeposit;
        state.pendingDeposit = 0;
        console.log("f");

        share.mint(receiver, state.totalShares);

        return state.totalShares;
      
    }

    function cancelPendingDeposit(address liquidityPool, address owner) external returns(uint256) {
          LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
          require (lp.epochInProgress(), "Manager/Epoch has closed");


          InvestmentState storage state = investments[liquidityPool][owner];
          uint256 amount = state.pendingDeposit;
          totalDeposits -= amount;

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
        uint256 amount =  additionalAssets;
        totalDeposits += amount;
        state.pendingDeposit += amount;

          return true;
    }

     function decreaseDepositOrder(address liquidityPool, address receiver, uint256 assets) public returns(bool) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        require (lp.epochInProgress(), "Manager/Epoch has closed");

          InvestmentState storage state = investments[liquidityPool][receiver];
          require(state.exists && state.pendingDeposit != 0, "Manager/Error increasing deposit");
          require(state.pendingDeposit > assets, "Manager/ Not enough assets");
          uint256 amount  = assets;

         totalDeposits -= amount;
         state.pendingDeposit -= amount;
          EscrowLike(escrow).approve(lp.asset_(), receiver, amount);
         require ( EscrowLike(escrow).transferOut(receiver, amount), "Manager/ decrease deposit order failed");
          return true;
    }


    function mint(address liquidityPool, uint256 assets,  address receiver) public returns (uint256 shares) {
       shares = processDeposit(liquidityPool, assets,  receiver);
        return shares;
    }

//share and assets are just numbers
    function withdraw(address liquidityPool,  address receiver, address owner, uint256 assets)
        public
        returns (uint256 shares)
    {
        require(owner == receiver, "Manager/not owner");
    
        InvestmentState storage state = investments[liquidityPool][owner];
        require(state.exists, "Manager/ Investor does not exist");

        uint256 amount =  convertToAssets(liquidityPool, owner, assets);
        shares = processRedeem(liquidityPool, owner,state, amount);
       
      return shares;
    }

    function redeem(address liquidityPool,  address receiver, address owner, uint256 shares)
        public
        returns (uint256 assets)
    {
          require(owner == receiver, "Manager/not owner");
           
         InvestmentState storage state = investments[liquidityPool][owner];
       require(state.exists, "Manager/ Investor does not exist");

        uint256 amount = convertToAssets(liquidityPool, owner, shares);
        assets = processRedeem(liquidityPool, owner, state, amount);

      
 
      return assets;
    }

    function processRedeem(address liquidityPool, address owner, InvestmentState storage state, uint256 assets) internal returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share_());
      

        require(state.totalShares != 0, "Manager/ Invalid amount");

        // uint256 assets = convertToAssets(liquidityPool, owner, shares);
        share.burn(owner, state.totalShares);
         
        EscrowLike(poolEscrow).approve(lp.asset_(), owner, assets);
        EscrowLike(poolEscrow).transferOut(owner, assets);

        return assets;
    }


    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/



function convertToShares(address liquidityPool, address receiver, uint256 assets) public view virtual returns (uint256 shares) {
    LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
    uint256 totalAssets = ERC20(lp.asset_()).balanceOf(address(escrow));

    uint256 totalInvestmentsWithInterest = totalAssets + totalAssets * interestRate / 100;
    uint256 investorContribution = calculateInvestorContribution(liquidityPool, receiver, assets);
    shares = investorContribution * totalInvestmentsWithInterest / 100;
    
    return shares;
}



    function convertToAssets(address liquidityPool, address receiver, uint256 shares) public view virtual returns (uint256 assets) {
    LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
    uint256 totalReturns = ERC20(lp.asset_()).balanceOf(address(poolEscrow));
    console.log("stage1", totalReturns);
    uint256 totalInvestorShares = ERC20(lp.share_()).balanceOf(address(receiver));
    console.log("stage2", totalInvestorShares);
    uint256 totalShares = ERC20(lp.share_()).totalSupply();
    console.log("stage3", totalShares);
    require(totalInvestorShares >= shares, "Manager/ Invalid shares");


    uint256 investorContributionPercentage = totalInvestorShares * 100 / totalShares;

    console.log("stage4", investorContributionPercentage);

    assets = investorContributionPercentage * totalReturns /100;
     console.log("stage5", assets);

    return assets;

}



    function calculateInvestorContribution(address liquidityPool, address investor, uint256 assets) public view returns (uint256) {
         LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        InvestmentState storage state = investments[liquidityPool][investor];
        console.log("b", state.pendingDeposit);

        require(state.exists , "Manager/You have no pending orders");
        console.log("c");

        require(state.pendingDeposit >= assets, "Manager/asset mismatch");

        uint256 investorBalance = state.pendingDeposit;
        console.log("d", investorBalance);

        uint256 totalInvestments = ERC20(lp.asset_()).balanceOf(address(escrow));
        console.log("e", totalInvestments);
        uint256 contribution = investorBalance * 100 / totalInvestments;
        console.log("e", contribution);

    
        return contribution;
    }

   
    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxRedeem(address liquidityPool, address owner, uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(liquidityPool, owner, shares);
    }

    function maxWithdraw(address liquidityPool, address owner) public view virtual returns (uint256) {
        return uint256(investments[liquidityPool][owner].maxWithdraw);
    }
}
