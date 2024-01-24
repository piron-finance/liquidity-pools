// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Auth} from "../Auth.sol";
import {ERC20} from "../tokens/ERC20.sol";
import {LiquidityPool} from "../LiquidityPool.sol";

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(
        address asset,
        address share,
        address manager,
        address escrow,
        uint64 poolId,
        bytes16 trancheId
    ) external returns (address);
}

contract LiquidityPoolFactory {
    // todo: setup root contracts to pause, unpause etc
    // constructor() {
    //     authorizedAccounts[msg.sender] = 1;
    //     emit AddAuthorization(msg.sender);
    // }

    function newLiquidityPool(
        address asset,
        address share,
        address manager,
        address escrow,
        uint64 poolId,
        bytes16 trancheId
    ) external returns (address) {
        LiquidityPool pool = new LiquidityPool(asset, share, manager, escrow, poolId, trancheId);

        return address(pool);
    }
}
