// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC20} from "./tokens/ERC20.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface ManagerLike {
    function requestDeposit(address lp, uint256 assets, address receiver, address owner) external returns (bool);
    function requestRedeem(address lp, uint256 shares, address receiver, address owner) external returns (bool);
    function decreaseDepositRequest(address lp, uint256 assets, address owner) external;
    function decreaseRedeemRequest(address lp, uint256 shares, address owner) external;
    function cancelDepositRequest(address lp, address owner) external;
    function cancelRedeemRequest(address lp, address owner) external;
    function pendingDepositRequest(address lp, address owner) external view returns (uint256);
    function pendingRedeemRequest(address lp, address owner) external view returns (uint256);
    function exchangeRateLastUpdated(address lp) external view returns (uint64);
    function deposit(address lp, uint256 assets, address receiver, address owner) external returns (uint256);
    function mint(address lp, uint256 shares, address receiver, address owner) external returns (uint256);
    function withdraw(address lp, uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(address lp, uint256 shares, address receiver, address owner) external returns (uint256);
    function maxDeposit(address lp, address receiver) external view returns (uint256);
    function maxMint(address lp, address receiver) external view returns (uint256);
    function maxWithdraw(address lp, address receiver) external view returns (uint256);
    function maxRedeem(address lp, address receiver) external view returns (uint256);
    function convertToShares(address lp, uint256 assets) external view returns (uint256);
    function convertToAssets(address lp, uint256 shares) external view returns (uint256);
}

/// @title  Liquidity Pool
/// @notice Liquidity Pool implementation for Piron finance
///         following the ERC-7540 Asynchronous Tokenized Vault standard
///
/// @dev    Each Liquidity Pool is a tokenized vault issuing shares of Centrifuge tranches as restricted ERC-20 tokens
///         against currency deposits based on the current share price.
///
///         ERC-7540 is an extension of the ERC-4626 standard by 'requestDeposit' & 'requestRedeem' methods, where
///         deposit and redeem orders are submitted to the pools to be included in the execution of the following epoch.
///         After execution users can use the deposit, mint, redeem and withdraw functions to get their shares
///         and/or assets from the pools.

contract LiquidityPool is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    mapping(address => uint256) public shareHolders;

    // Events
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    // Immutables

    ERC20 public immutable asset;
    address public immutable owner;
    uint64 public immutable poolId;

    constructor(ERC20 _asset, string memory _name, string memory _symbol, uint64 poolId_)
        ERC20(_name, _symbol, _asset.decimals())
    {
        asset = _asset;
        owner = msg.sender;
        poolId = poolId_;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");

        _;
    }

    // Deposit / Withdrawal logic

    function deposit(uint256 assets_, address receiver) public virtual returns (uint256 shares) {
        require((shares = previewDeposit(assets_)) != 0, "ZERO_SHARES"); //since we round down in previewDeposit, this is a safe check
        require(assets_ > 0, "Deposit less than Zero");
        require(asset.balanceOf(msg.sender) >= assets_, "Insufficient balance");

        asset.safeTransferFrom(msg.sender, address(this), assets_);

        _mint(receiver, shares);
        shareHolders[msg.sender] += shares;
    }

    function mint(uint256 shares_, address receiver) public virtual returns (uint256 assets) {
        require(shares_ > 0, "Mint less than Zero");
        assets = previewMint(shares_); // no need to check for rounding error since we round up

        // we need to transfer assets before minting
        asset.safeTransferFrom(msg.sender, address(this), assets);
        emit Deposit(msg.sender, receiver, assets, shares_);

        _mint(receiver, shares_);
        shareHolders[msg.sender] += shares_;
    }

    function withdraw(uint256 assets_, address receiver, address owner_) public virtual returns (uint256 shares) {
        require(assets_ > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
        require(shareHolders[owner_] >= assets_, "Insufficient balance");
        shares = previewWithdraw(assets_);

        // updating allowance
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; //saves gas for limited approvals
            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares;
            }
        }

        _burn(owner_, shares);
        shareHolders[owner_] -= shares;

        emit Withdraw(msg.sender, receiver, owner_, assets_, shares);
        asset.safeTransfer(receiver, assets_);
    }

    function redeem(uint256 shares_, address receiver, address owner_) public virtual returns (uint256 assets) {
        require((assets = previewRedeem(shares_)) != 0, "ZERO_ASSETS");
        require(shares_ > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
        require(shareHolders[owner_] >= shares_, "Insufficient balance");

        // updating allowance
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; //saves gas for limited approvals
            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares_;
            }
        }

        _burn(owner_, shares_);
        shareHolders[owner_] -= shares_;
        emit Withdraw(msg.sender, receiver, owner_, assets, shares_);
        asset.safeTransfer(receiver, assets);
    }

    // view functions
    function totalSharesOfUser(address user) public view returns (uint256) {
        return shareHolders[user];
    }

    // investing logic
    // function lendOnAave(address aaveV3, uint256 asset_amount) public onlyOwner {
    //     asset.safeApprove(aaveV3, asset_amount);
    //     IPool(aaveV3).supply(asset_(), asset_amount, address(this), 0);
    // }

    // function withdrawFromAave(address aaveV3) public onlyOwner {
    //     IPool(aaveV3).withdraw(asset_(), type(uint256).max, address(this));
    // }

    //  Accounting logic
    function asset_() public view virtual returns (address) {
        return address(asset);
    }

    function share_() public view virtual returns (address) {
        return address(this);
    }

    function totalAssets() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function previewDeposit(uint256 assets_) public view virtual returns (uint256) {
        return convertToShares(assets_);
    }

    function convertToShares(uint256 assets_) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? assets_ : assets_.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares_) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? shares_ : shares_.mulDivDown(totalAssets(), supply);
    }

    function previewMint(uint256 shares_) public view virtual returns (uint256) {
        return convertToAssets(shares_);
    }

    function previewRedeem(uint256 shares_) public view virtual returns (uint256) {
        return convertToAssets(shares_);
    }

    function previewWithdraw(uint256 assets_) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? assets_ : assets_.mulDivUp(supply, totalAssets());
    }
}
