// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {LiquidityPool} from "../LiquidityPool.sol";

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        address asset,
        address share,
        address manager,
        address escrow
    ) external returns (address);
}

contract LiquidityPoolFactory {
    // todo: setup root contracts to pause, unpause etc
    // constructor() {
    //     authorizedAccounts[msg.sender] = 1;
    //     emit AddAuthorization(msg.sender);
    // }

    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        address asset,
        address share,
        address manager,
        address escrow
    ) external returns (address) {
        LiquidityPool pool = new LiquidityPool(uint64(poolId), bytes16(trancheId), asset, share, manager, escrow );

        return address(pool);
    }
}
