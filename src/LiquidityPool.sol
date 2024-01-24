// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "./token/ERC20.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/interfaces/IERC7575.sol";

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

contract LiquidityPool is IERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    mapping(address => uint256) public shareHolders;

    //   Immutables
    address public immutable asset;
    address public immutable owner;
    uint64 public immutable poolId;
    address public immutable share;

    /// @notice Liquidity Pool implementation contract
    ManagerLike public manager;

    /// @notice Escrow contract for tokens
    address public immutable escrow;

    constructor(address _asset, address _share, uint64 _poolId, address _manager, address _escrow) {
        asset = _asset;
        share = _share;
        escrow = _escrow;
        manager = ManagerLike(_manager);
        owner = msg.sender;
        poolId = _poolId;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    // add request deposit with eip2612. add logic for share

    // Deposit and Withdrawal Logic
    function deposit(uint256 assets_, address receiver) external override returns (uint256 shares) {
        require((shares = previewDeposit(assets_)) != 0, "ZERO_SHARES"); //since we round down in previewDeposit, this is a safe check
        require(assets_ > 0, "Deposit less than Zero");
        require(ERC20(asset).balanceOf(msg.sender) >= assets_, "Insufficient balance");

        SafeTransferLib.safeTransferFrom(msg.sender, address(this), assets_);

        _mint(receiver, shares);
        shareHolders[msg.sender] += shares;
    }

    function mint(uint256 shares_, address receiver) public virtual returns (uint256 assets) {
        require(shares_ > 0, "Mint less than Zero");

        assets = previewMint(shares_); // no need to check for rounding error since we round up

        // we need to transfer assets before minting
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
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
        ERC20(asset).safeTransfer(receiver, assets_);
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
        ERC20(asset).safeTransfer(receiver, assets);
    }

    // View functions

    // --- ERC-4626 methods ----
    /// @inheritdoc IERC7575Minimal
    function totalAssets() external view returns (uint256) {
        return convertToAssets(IERC20Metadata(share).totalSupply());
    }

    function convertToShares(uint256 assets_) external view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? assets_ : assets_.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares_) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? shares_ : shares_.mulDivDown(totalAssets(), supply);
    }

    function maxDeposit(address receiver) external pure override returns (uint256) {
        return type(uint256).max; // Update with your logic if needed
    }

    // fmr func

    // Implement other IERC7575 methods: mint, withdraw, and redeem

    function totalSharesOfUser(address user) public view returns (uint256) {
        return shareHolders[user];
    }

    // ... (Additional methods and logic)

    function previewDeposit(uint256 assets_) public view virtual returns (uint256) {
        return convertToShares(assets_);
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

    function maxMint(address receiver) public view virtual returns (uint256) {}
    function maxRedeem(address _owner) public view virtual returns (uint256) {}
    function maxWithdraw(address _owner) public view virtual returns (uint256) {}

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {}
}
