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

/// @dev Temporary storage that only exists between addTranche and deployTranche
struct UndeployedTranche {
    /// @dev The decimals of the pool currecncy must match that of the tranche token
    uint8 decimals;
    /// @dev metadata
    string tokenName;
    string tokenSymbol;
    uint8 restrictionSet;
}

/// @title Pool Manager
/// @notice Manages the creation and deployment of pools and tranches
contract PoolManager {
    using FixedPointMathLib for uint256;

    // Decimals
    uint8 internal constant MAX_DECIMALS = 18;
    uint8 internal constant MIN_DECIMALS = 1;

    //  Immutables
    EscrowLike public immutable escrow;

    InvestmentManagerLike public investmentManager;

    //  Factories
    LiquidityPoolFactoryLike public liquidityPoolFactory;
    RestrictionManagerFactoryLike public restrictionManagerFactory;
    TrancheTokenFactoryLike public trancheTokenFactory;

    mapping(uint64 poolId => Pool) public pools;
    mapping(uint64 poolId => mapping(bytes16 trancheId => UndeployedTranche)) public undeployedTranches;

    /// @dev Chain agnostic currency id -> evm currency address and reverse mapping
    mapping(uint128 currencyId => address) public currencyIdToAddress;
    mapping(address => uint128 currencyId) public currencyAddressToId;

    //  Events
    event File(bytes32 indexed what, address data);
    event AddCurrency(uint128 indexed currencyId, address indexed currency);
    event AddPool(uint64 indexed poolId);
    event AllowInvestmentCurrency(uint64 indexed poolId, address indexed currency);
    event DisallowInvestmentCurrency(uint64 indexed poolId, address indexed currency);
    event AddTranche(uint64 indexed poolId, bytes16 indexed trancheId);
    event DeployTranche(uint64 indexed poolId, bytes16 indexed trancheId, address indexed trancheToken);
    event DeployLiquidityPool(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed currency, address liquidityPool
    );
    event RemoveLiquidityPool(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed currency, address liquidityPool
    );
    event PriceUpdate(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed currency, uint256 price, uint64 computedAt
    );
    event TransferCurrency(address indexed currency, bytes32 indexed recipient, uint128 amount);
    event TransferTrancheTokensToCentrifuge(
        uint64 indexed poolId, bytes16 indexed trancheId, bytes32 destinationAddress, uint128 amount
    );
    event TransferTrancheTokensToEVM(
        uint64 indexed poolId,
        bytes16 indexed trancheId,
        uint64 indexed destinationChainId,
        address destinationAddress,
        uint128 amount
    );

    constructor(
        address escrow_,
        address liquidityPoolFactory_,
        address restrictionManagerFactory_,
        address trancheTokenFactory_
    ) {
        escrow = EscrowLike(escrow_);
        liquidityPoolFactory = LiquidityPoolFactoryLike(liquidityPoolFactory_);
        restrictionManagerFactory = RestrictionManagerFactoryLike(restrictionManagerFactory_);
        trancheTokenFactory = TrancheTokenFactoryLike(trancheTokenFactory_);
    }

    /// @notice piron pools support multiple currencies for investment. the function adds a new currency to the pool details
    /// @dev this function can only be called by the investment manager

    function allowInvestmentCurrency(uint64 poolId, uint128 currencyId) public {
        Pool storage pool = pools[poolId];
        // require(msg.sender == address(investmentManager), "PoolManager/only-investment-manager");
        require(pool.createdAt != 0, "PoolManager/pool-not-found");

        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/invalid-currency");

        require(!pools[poolId].allowedCurrencies[currency], "PoolManager/currency-already-added");

        pools[poolId].allowedCurrencies[currency] = true;
        emit AllowInvestmentCurrency(poolId, currency);
    }

    function diaallowInvestmentCurrency(uint64 poolId, uint128 currencyId) public {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/pool-not-found");

        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/invalid-currency");

        pools[poolId].allowedCurrencies[currency] = false;
        emit DisallowInvestmentCurrency(poolId, currency);
    }

    function addCurrency(uint128 currencyId, address currency) public {
        // Currency index  should start at 1
        require(currencyId != 0, "PoolManager/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currencyId] == address(0), "PoolManager/currency-id-in-use");
        require(currencyAddressToId[currency] == 0, "PoolManager/currency-address-in-use");

        uint8 currencyDecimals = IERC20Metadata(currency).decimals();
        require(currencyDecimals >= MIN_DECIMALS, "PoolManager/too-few-currency-decimals");
        require(currencyDecimals <= MAX_DECIMALS, "PoolManager/too-many-currency-decimals");

        currencyIdToAddress[currencyId] = currency;
        currencyAddressToId[currency] = currencyId;

        // Give investment manager infinite approval for currency in the escrow
        // to transfer to the user escrow on redeem, withdraw or transfer
        escrow.approve(currency, investmentManager.userEscrow(), type(uint256).max);

        emit AddCurrency(currencyId, currency);
    }

    // --- Public functions ---
    // slither-disable-start reentrancy-eth
    function deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        UndeployedTranche storage undeployedTranche = undeployedTranches[poolId][trancheId];
        require(undeployedTranche.decimals != 0, "PoolManager/tranche-not-added");

        address token = trancheTokenFactory.newTrancheToken(
            poolId, trancheId, undeployedTranche.tokenName, undeployedTranche.tokenSymbol, undeployedTranche.decimals
        );

        pools[poolId].tranches[trancheId].token = token;

        delete undeployedTranches[poolId][trancheId];

        // Give investment manager infinite approval for tranche tokens
        // in the escrow to transfer to the user on deposit or mint
        escrow.approve(token, address(investmentManager), type(uint256).max);

        emit DeployTranche(poolId, trancheId, token);
        return token;
    }
    // slither-disable-end reentrancy-eth

    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");
        require(isAllowedAsInvestmentCurrency(poolId, currency), "PoolManager/currency-not-supported");

        address liquidityPool = tranche.liquidityPools[currency];
        require(liquidityPool == address(0), "PoolManager/liquidity-pool-already-deployed");

        // Deploy liquidity pool
        liquidityPool = liquidityPoolFactory.newLiquidityPool(
            poolId, trancheId, currency, tranche.token, address(escrow), address(investmentManager)
        );
        tranche.liquidityPools[currency] = liquidityPool;

        // Link liquidity pool to tranche token
        TrancheTokenLike(tranche.token).addTrustedForwarder(liquidityPool);

        // Give liquidity pool infinite approval for tranche tokens
        // in the escrow to burn on executed redemptions
        escrow.approve(tranche.token, liquidityPool, type(uint256).max);

        emit DeployLiquidityPool(poolId, trancheId, currency, liquidityPool);
        return liquidityPool;
    }

    function removeLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public auth {
        require(pools[poolId].createdAt != 0, "PoolManager/pool-does-not-exist");
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address liquidityPool = tranche.liquidityPools[currency];
        require(liquidityPool != address(0), "PoolManager/liquidity-pool-not-deployed");

        delete tranche.liquidityPools[currency];

        AuthLike(address(investmentManager)).deny(liquidityPool);

        AuthLike(tranche.token).deny(liquidityPool);
        TrancheTokenLike(tranche.token).removeTrustedForwarder(liquidityPool);

        escrow.approve(address(tranche.token), liquidityPool, 0);

        emit RemoveLiquidityPool(poolId, trancheId, currency, liquidityPool);
    }
}
