// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import {LiquidityPoolFactoryLike} from "./factories/poolFactory.sol";
import {RestrictionManagerFactoryLike} from "./factories/RestrictionManagerFactory.sol";
import {TrancheTokenFactoryLike} from "./factories/TranchTokenFactory.sol";
import {TrancheTokenLike} from "./tokens/Tranche.sol";
import {RestrictionManagerLike} from "./tokens/RestrictionManager.sol";
import {IERC20Metadata} from "./interfaces/IERC20.sol";

interface InvestmentManagerLike {
    function liquidityPools(uint64 poolId, address currency) external returns (address);
    function getTrancheToken(uint64 _poolId) external view returns (address);
    function userEscrow() external view returns (address);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

/// @dev piron pools
struct Pool {
    uint256 createdAt;
    mapping(bytes16 trancheId => Tranche) tranches;
    mapping(address currency => bool) allowedCurrencies;
}

struct Tranche {
    address token;
    // each tranche can have multiple liquidity poolseach one linking to a unique investment currency
    mapping(address currency => LiquidityPool) liquidityPools;
    /// @dev each tranche has a price per liquidity pool
    mapping(address liquidityPool => TrancheTokenPrice) prices;
}

struct TrancheTokenPrice {
    uint256 price;
    uint64 lastUpdate;
}

/// @dev Temporary storage that only exists between add
struct UndeployedTranche {}
