// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";

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
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(address _asset, string memory _name, string memory _symbol, uint64 poolId_)
        external
        returns (address);
}

contract InvestmentManager {
    using FixedPointMathLib for uint256;

    LiquidityPoolFactoryLike public liquidityPoolFactory;
    // uint256 public poolId;
    //  Immutables
    EscrowLike public immutable escrow;

    constructor(address escrow_, address liquidityPoolFactory_) {
        escrow = EscrowLike(escrow_);
        liquidityPoolFactory = LiquidityPoolFactoryLike(liquidityPoolFactory_);
    }

    function deployLiquidityPool() public returns (address) {
        return liquidityPoolFactory.newLiquidityPool(address(0), "bankly shares", "BKS", 1);
    }

    function deposit(address pool, uint256 amount) public {
        LiquidityPoolLike(pool).mint(msg.sender, amount);
        ERC20Like(LiquidityPoolLike(pool).asset_()).transferFrom(msg.sender, address(this), amount);
    }

    function mint(address pool, uint256 amount) public {
        LiquidityPoolLike(pool).mint(msg.sender, amount);
    }

    function withdraw(address pool, uint256 amount) public {
        LiquidityPoolLike(pool).burn(msg.sender, amount);
        ERC20Like(LiquidityPoolLike(pool).asset_()).transferFrom(address(this), msg.sender, amount);
    }

    function redeem(address pool, uint256 amount) public {
        LiquidityPoolLike(pool).burn(msg.sender, amount);
    }

    function approve(address token, address spender, uint256 value) external {
        escrow.approve(token, spender, value);
    }

    function getBalance(address pool) public view returns (uint256) {
        return LiquidityPoolLike(pool).balanceOf(msg.sender);
    }
}
