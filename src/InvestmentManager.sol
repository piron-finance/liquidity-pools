// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import "./interfaces/IERC20.sol";
import "./tokens/ERC20.sol"; 


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

    uint256 Deposits;
    uint256 totalShares;
    
    uint256 pendingDeposit;
    uint256 pendingShares;

    uint256 pendingRedeem;
    uint256 maxWithdraw;

    uint256 investorContribution;

    bool exists;
}

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

    function deposit(address liquidityPool, uint256 assets, uint256 shares, address receiver) external returns (bool) {
          totalDeposits += assets;

          InvestmentState storage state = investments[liquidityPool][receiver];
          state.pendingDeposit = state.pendingDeposit + assets;
          state.pendingShares = shares;
          
          state.exists = true;

          return true;
    }

    

    function processDeposit(address liquidityPool,   address receiver) public returns (uint256) {
       
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);

        ERC20Like share = ERC20Like(lp.share_());
        InvestmentState storage state = investments[liquidityPool][receiver];   

        state.totalShares = state.pendingShares;
         state.pendingShares = 0;
        require(state.totalShares  > 0, "ZERO_SHARES");

        state.Deposits = state.pendingDeposit;
        state.pendingDeposit = 0;

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


   
    function withdraw(address liquidityPool,  address receiver, address owner, uint256 assets)
        public
        returns (uint256 shares)
    {
        require(owner == receiver, "Manager/not owner");
    
        InvestmentState storage state = investments[liquidityPool][owner];
        require(state.exists, "Manager/ Investor does not exist");

        uint256 amount =  convertToExitAssets(liquidityPool, owner, assets);
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

        uint256 amount = convertToExitAssets(liquidityPool, owner, shares);
        assets = processRedeem(liquidityPool, owner, state, amount);

      
 
      return assets;
    }

    function processRedeem(address liquidityPool, address owner, InvestmentState storage state, uint256 assets) internal returns (uint256) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        ERC20Like share = ERC20Like(lp.share_());
      

        require(state.totalShares != 0, "Manager/ Invalid amount");

        share.burn(owner, state.totalShares);
         
        EscrowLike(poolEscrow).approve(lp.asset_(), owner, assets);
        EscrowLike(poolEscrow).transferOut(owner, assets);

        return assets;
    }


    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/




 function convertToAssets(uint256 shares_, address liquidityPool) public view  returns (uint256 assets_) {
        LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 totalShares = ERC20(lp.share_()).totalSupply();
         uint256 totalAssets = ERC20(lp.asset_()).balanceOf(address(escrow));
        uint256 totalSupply_ = totalShares;


        assets_ = totalSupply_ == 0 ? shares_ : (shares_ * totalAssets) / totalSupply_;
    }

     function convertToShares(uint256 assets_, address liquidityPool) public view  returns (uint256 shares_) {
         LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
        uint256 totalShares = ERC20(lp.share_()).totalSupply();
         uint256 totalAssets = ERC20(lp.asset_()).balanceOf(address(escrow));
        uint256 totalSupply_ = totalShares;

        shares_ = totalSupply_ == 0 ? assets_ : (assets_ * totalSupply_) / totalAssets;
    }




    function convertToExitAssets(address liquidityPool, address receiver, uint256 shares) public view virtual returns (uint256 assets) {
    LiquidityPoolLike lp = LiquidityPoolLike(liquidityPool);
    uint256 totalReturns = ERC20(lp.asset_()).balanceOf(address(poolEscrow));
    uint256 totalInvestorShares = ERC20(lp.share_()).balanceOf(address(receiver));
    uint256 totalShares = ERC20(lp.share_()).totalSupply();
    require(totalInvestorShares >= shares, "Manager/ Invalid shares");


    uint256 investorContributionPercentage = totalInvestorShares * 100 / totalShares;

    assets = investorContributionPercentage * totalReturns /100;
    return assets;

}


   
    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxRedeem(address liquidityPool, address owner, uint256 shares) public view virtual returns (uint256) {
        return convertToExitAssets(liquidityPool, owner, shares);
    }

    function maxWithdraw(address liquidityPool, address owner) public view virtual returns (uint256) {
        return uint256(investments[liquidityPool][owner].maxWithdraw);
    }
}
