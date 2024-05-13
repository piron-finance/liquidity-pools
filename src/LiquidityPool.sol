// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;


import "hardhat/console.sol";
import {ERC20} from "./tokens/ERC20.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC7575.sol";

interface ManagerLike {
    function deposit(address lp, uint256 assets, address receiver) external returns (bool);
    function processDeposit(address lp,  address receiver) external returns (uint256);
    function cancelPendingDeposit( address lp,address owner) external returns (uint256);
    function increaseDepositOrder( address lp,address receiver, uint256 assets) external returns (bool);
    function decreaseDepositOrder( address lp,address receiver, uint256 assets) external;
    function mint(address lp, uint256 assets,  address receiver) external returns (uint256);
    function withdraw(address lp,  address receiver, address owner) external returns (uint256);
    function redeem(address lp,  address receiver, address owner) external returns (uint256);
    function maxDeposit(address lp, address receiver) external view returns (uint256);
    function maxMint(address lp, address receiver) external view returns (uint256);
    function maxWithdraw(address lp, address receiver) external view returns (uint256);
    function maxRedeem(address lp, address receiver) external view returns (uint256);
    function convertToShares(address lp, address receiver, uint256 assets) external view returns (uint256);
    function convertToAssets(address lp, address receiver) external view returns (uint256);
    function previewMint(address lp, uint256 shares) external view returns (uint256 assets);
    function previewDeposit(address lp, uint256 assets) external view returns (uint256 shares);
    function previewWithdraw(address lp, uint256 assets) external view returns (uint256 shares);
    function previewRedeem(address lp, uint256 shares) external view returns (uint256 assets);
}

contract LiquidityPool is IERC4626 {
    // using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    uint256 constant REQUEST_ID = 0;


    //   Immutables
    address public immutable asset_;
    uint64 public immutable poolId;
    address public immutable share_;
    uint256 public immutable EPOCH_DURATION = 1713143416;
   
      // Duration of the deposit epoch
    uint256 public epochEndTime;
    bool public epochInProgress;


    /// @notice Liquidity Pool implementation contract
    ManagerLike public manager;

    /// @notice Escrow contract for tokens
    address public immutable escrow;

    // Events
    event Deposit( uint256 assets, address receiver);
    event ProcessDeposit(uint256 assets, address receiver, uint256 shares);
    event CancelPendingDeposit(address owner, uint256 refund);


     modifier onlyDuringEpoch {
        require (epochInProgress, "Epoch is not active");    
         _;
     }

     modifier onlyAfterEpoch {
        require(block.timestamp >= epochEndTime, "Epoch is not concluded");
        _;
     }

    

    constructor(uint64 _poolId,  address _asset, address _share, address _manager, address _escrow ) {
        asset_ = _asset;
        share_ = _share;
        escrow = _escrow;
        manager = ManagerLike(_manager);
        poolId = _poolId;
        // EPOCH_DURATION =  block.timestamp + 5 minutes;
    }

  /*//////////////////////////////////////////////////////////////
                        HANDLE EPOCHS
    //////////////////////////////////////////////////////////////*/

    function startNextEpoch() public {
        epochEndTime =  EPOCH_DURATION;
        epochInProgress = true;
    }

    function handleEndOfEpoch() public{
        require(block.timestamp >= epochEndTime, "Epoch is still in progress");

        epochInProgress = false;
    }

    // add request deposit with eip2612. add logic for share

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    // --- ERC-4626 methods ----  // work on visibility of functions
    function deposit(uint256 _assets, address receiver) public onlyDuringEpoch virtual returns (uint256) {
        require(_assets > 0, "Deposit less than Zero");
        require(IERC20(asset_).balanceOf(receiver) >= _assets, "LiquidityPool/Insufficient balance");
       
        SafeTransferLib.safeTransferFrom(ERC20(asset_), receiver, address(escrow), _assets);
        
        require(manager.deposit(address(this), _assets, receiver), "Deposit request failed");

        emit Deposit( _assets, receiver);
        return REQUEST_ID;

        
    }

      function mint(uint256 _shares, address receiver) public virtual returns (uint256 assets) {
        require(_shares > 0, "Deposit less than Zero");
        assets = manager.mint(address(this), _shares,  receiver);
        emit Deposit( assets, receiver);
    } 


    function _mint(uint256 shares, uint256 assets, address receiver, address caller)



    function cancelPendingDeposit(address owner) public onlyDuringEpoch returns(uint256 refund)  {
        refund = manager.cancelPendingDeposit(address(this), owner);

        emit CancelPendingDeposit(owner, refund);
    }


    function increaseDepositOrder(address receiver, uint256 assets) public onlyDuringEpoch {
        require (assets != 0, "Invalid amount");
        require(IERC20(asset_).balanceOf(receiver) >= assets, "LiquidityPool/Insufficient balance");

        SafeTransferLib.safeTransferFrom(ERC20(asset_), receiver, address(escrow), assets);

        manager.increaseDepositOrder(address(this), receiver, assets);
    }

    function decreaseDepositOrder(address receiver, uint256 assets) public onlyDuringEpoch {
        require (assets != 0, "Invalid amount");

        manager.decreaseDepositOrder(address(this), receiver, assets);
    }

 
  

    function withdraw( uint256 assets, address receiver, address owner_) public virtual returns (uint256 shares) {
        require(msg.sender == owner_, "LiquidityPool/not-owner");
        // require(_assets > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
      

        shares = manager.withdraw(address(this),  receiver, owner_);
    }

    function redeem( uint256 shares, address receiver, address owner_) public virtual returns (uint256 assets) {
        require(msg.sender == owner_, "LiquidityPool/not-owner");
        // require(_shares > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
   

        assets = manager.redeem(address(this),  receiver, owner_);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

   
       function totalAssets() external view returns (uint256) {
        uint256 escrowAssets = ERC20(asset_).balanceOf(address(escrow));
        return escrowAssets; 
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        return manager.convertToShares(address(this), msg.sender, assets);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        return manager.convertToAssets(address(this), msg.sender);
    }

    function previewDeposit(uint256) external pure returns (uint256) {
       revert();
    }

    function previewMint(uint256 ) external pure returns (uint256) {
       revert();
    }

    function previewRedeem(uint256) external pure returns (uint256) {
        revert();
    }

    function previewWithdraw(uint256) external pure returns (uint256) {
       revert();
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxRedeem(address _owner) public view returns (uint256) {
        return manager.maxRedeem(address(this), _owner);
    }

    function maxWithdraw(address _owner) public view returns (uint256) {
        return manager.maxWithdraw(address(this), _owner);
    }

    function totalSharesOfUser(address user) public view returns (uint256) {
        return ERC20(share_).balanceOf(user);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

    function afterDeposit(uint256 assets, uint256 shares) internal virtual {}

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {}

    /*//////////////////////////////////////////////////////////////
                     VIEW TOKEN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function asset() external view returns (address assetTokenAddress) {
        return asset_;
    }

    function share() external view returns (address shareTokenAddress) {
        return share_;
    }
}
