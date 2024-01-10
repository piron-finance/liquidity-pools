// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Auth} from "../Auth.sol";
import {ERC20} from "../tokens/ERC20.sol";
import {LiquidityPool} from "../LiquidityPool.sol";

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(address _asset, string memory _name, string memory _symbol, uint64 poolId_)
        external
        returns (address);
}

contract LiquidityPoolFactory {
    // todo: setup root contracts to pause, unpause etc
    // constructor() {
    //     authorizedAccounts[msg.sender] = 1;
    //     emit AddAuthorization(msg.sender);
    // }

    function newLiquidityPool(ERC20 _asset, string memory _name, string memory _symbol, uint64 poolId_)
        external
        returns (address)
    {
        LiquidityPool pool = new LiquidityPool(_asset, _name, _symbol, poolId_);

        return address(pool);
    }
}
