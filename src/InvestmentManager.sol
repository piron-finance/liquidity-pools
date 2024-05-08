// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import "./interfaces/IERC20.sol";
import "./tokens/ERC20.sol"; //what does it dop again?


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
    
    uint256 pendingDeposit;
    uint256 pendingWithdraw;


    uint256 pendingRedeem;
    uint256 maxWithdraw;

    bool pendingCancelDeposit;
    bool pendingCancelRedeem;

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
          uint256 amount = assets;
          totalDeposits += amount;

          InvestmentState storage state = investments[liquidityPool][receiver];
          state.pendingDeposit = state.pendingDeposit + amount;
          
          state.exists = true;

          return true;
    }

    function processDeposit(address liquidityPool, uint256 assets,  address receiver) internal returns (uint256 shares) {
       
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);

        ERC20Like share = ERC20Like(lp.share_());


        InvestmentState storage state = investments[liquidityPool][receiver];
        require(state.pendingDeposit == assets, "Mananger/partial execution prohibited");     

        shares = convertToShares(address(lp),  receiver);
        require(shares  > 0, "ZERO_SHARES");


        state.totalDeposits = state.pendingDeposit;
        state.pendingDeposit = 0;

        share.mint(receiver, shares);

        return shares;
      
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

    function withdraw(address liquidityPool, uint256 assets, address receiver, address owner)
        public
        returns (uint256 shares)
    {
    
        InvestmentState storage state = investments[liquidityPool][owner];
        processRedeem(liquidityPool, assets, owner, state);

        shares = convertToShares(liquidityPool,  receiver);
      
    }

    function redeem(address liquidityPool, uint256 shares, address receiver, address owner)
        public
        returns (uint256 assets)
    {
         InvestmentState storage state = investments[liquidityPool][owner];
        processRedeem(liquidityPool, shares, owner, state);

        assets = convertToAssets(liquidityPool, shares, receiver);
 
    }

    function processRedeem(address liquidityPool, uint256 assets, address owner, InvestmentState storage state) internal {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share_());

        require(assets != 0, "Manager/ Invalid amount");
        require(state.maxWithdraw >= assets, "Manager/ Insufficient balance");

        state.maxWithdraw = state.maxWithdraw - assets;
        share.burn(owner, assets);

         
        EscrowLike(escrow).approve(lp.asset_(), owner, assets);
        EscrowLike(escrow).transferOut(owner, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/





function convertToShares(address liquidityPool, address receiver) public view virtual returns (uint256 shares) {
    LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
    uint256 totalAssets = ERC20(lp.asset_()).balanceOf(address(escrow));

    // Calculate the total investments including interest
    uint256 totalInvestmentsWithInterest = totalAssets + totalAssets * interestRate / 100;

    // Calculate the investor's contribution considering the interest rate
    uint256 investorContribution = calculateInvestorContribution(liquidityPool, receiver);

    // Calculate shares based on investor contribution percentage
    shares = investorContribution * totalInvestmentsWithInterest / 100;

    // Ensure shares are not greater than total assets
    require(shares <= totalAssets, "Shares cannot exceed total assets");

    return shares;
}



// fix. 
 

    function convertToAssets(address liquidityPool, uint256 shares, address receiver) public view virtual returns (uint256) {
    LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
    uint256 totalShares = ERC20(lp.share_()).totalSupply(); // Total supply of shares in the pool
    uint256 totalAssets = ERC20(lp.asset_()).balanceOf(address(escrow));

    // Calculate the total investments including interest
    uint256 totalInvestmentsWithInterest = totalAssets + totalAssets * interestRate / 100;

    // Calculate the investor's contribution considering the interest rate
    uint256 investorContribution = calculateInvestorContribution(liquidityPool, receiver) * totalInvestmentsWithInterest / 100;

    // Ensure investorContribution is not zero to avoid division by zero
    require(investorContribution > 0, "Investor contribution cannot be zero");

    // Convert shares back to assets based on the investor's contribution
    return shares.mulDivDown(totalAssets, investorContribution).mulDivDown(totalShares, totalInvestmentsWithInterest);
}


    function calculateInvestorContribution(address liquidityPool, address investor) public view returns (uint256) {
         LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);

        InvestmentState storage state = investments[liquidityPool][investor];


        require(state.exists , "Manager/You have no pending orders");

        uint256 investorBalance = state.pendingDeposit;

        uint256 totalInvestments = ERC20(lp.asset_()).balanceOf(address(escrow));
        uint256 contribution = investorBalance * 100 / totalInvestments;
        return contribution;
    }

   
    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxRedeem(address liquidityPool, address owner) public view virtual returns (uint256) {
        return convertToShares(liquidityPool,  owner); // wonrg
    }

    function maxWithdraw(address liquidityPool, address owner) public view virtual returns (uint256) {
        return uint256(investments[liquidityPool][owner].maxWithdraw);
    }
}
