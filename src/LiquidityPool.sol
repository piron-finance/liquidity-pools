// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {ERC20} from "./tokens/ERC20.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC7575.sol";


interface ManagerLike {
    function deposit(address lp, uint256 assets, address receiver) external returns (bool);
    function processDeposit(address lp, uint256 assets, address receiver) external returns (uint256);
    function mint(address lp, uint256 shares, address receiver) external returns (uint256);
    function withdraw(address lp, uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(address lp, uint256 shares, address receiver, address owner) external returns (uint256);
    function maxDeposit(address lp, address receiver) external view returns (uint256);
    function maxMint(address lp, address receiver) external view returns (uint256);
    function maxWithdraw(address lp, address receiver) external view returns (uint256);
    function maxRedeem(address lp, address receiver) external view returns (uint256);
    function convertToShares(address lp, uint256 assets) external view returns (uint256);
    function convertToAssets(address lp, uint256 shares) external view returns (uint256);
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
    uint256 public immutable EPOCH_DURATION = 1712889976;
   
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
        require(manager.deposit(address(this), _assets, receiver), "Deposit request failed");
        console.log("a");

        SafeTransferLib.safeTransferFrom(ERC20(asset_), receiver, address(escrow), _assets);
         console.log("b");

        return REQUEST_ID;
    }

    function processDeposit(uint256 _assets, address receiver) public onlyAfterEpoch returns (uint256 shares)  {
        shares = manager.processDeposit( address(this), _assets,  receiver);

        emit ProcessDeposit(_assets, receiver, shares);
    }

    //    add events

    function mint(uint256 _shares, address receiver) public virtual returns (uint256 assets) {
        require(_shares > 0, "Deposit less than Zero");

        assets = manager.previewMint(address(this), _shares); // No need to check for rounding error, previewMint rounds up.
        SafeTransferLib.safeTransferFrom(ERC20(asset_), msg.sender, address(escrow), assets);

        assets = manager.mint(address(this), _shares, receiver);
       
    }

    function withdraw(uint256 _assets, address receiver, address owner_) public virtual returns (uint256 shares) {
        require(msg.sender == owner_, "LiquidityPool/not-owner");
        require(_assets > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
      

        shares = manager.withdraw(address(this), _assets, receiver, owner_);
    }

    function redeem(uint256 _shares, address receiver, address owner_) public virtual returns (uint256 assets) {
        require(msg.sender == owner_, "LiquidityPool/not-owner");
        require((assets = previewRedeem(_shares)) != 0, "ZERO_ASSETS");
        require(_shares > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
   

        assets = manager.redeem(address(this), _shares, receiver, owner_);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC7575Minimal
       function totalAssets() external view returns (uint256) {
        uint256 escrowAssets = ERC20(asset_).balanceOf(address(escrow));
        return escrowAssets; // rework this
    }

    function convertToShares(uint256 _assets) public view virtual returns (uint256) {
        return manager.convertToShares(address(this), _assets);
    }

    function convertToAssets(uint256 _shares) public view virtual returns (uint256) {
        return manager.convertToAssets(address(this), _shares);
    }

    function previewDeposit(uint256 _assets) public view virtual returns (uint256) {
        return manager.previewDeposit(address(this), _assets);
    }

    function previewMint(uint256 _shares) public view virtual returns (uint256) {
        return manager.previewMint(address(this), _shares);
    }

    function previewRedeem(uint256 _shares) public view virtual returns (uint256) {
        return manager.previewRedeem(address(this), _shares);
    }

    function previewWithdraw(uint256 assets_) public view virtual returns (uint256) {
        return manager.previewWithdraw(address(this), assets_);
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

    function asset() external view override returns (address assetTokenAddress) {
        return asset_;
    }

    function share() external view override returns (address shareTokenAddress) {
        return share_;
    }
}
