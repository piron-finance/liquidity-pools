// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {ERC20} from "./tokens/ERC20.sol";

contract Escrow {
    using SafeTransferLib for ERC20;

    ERC20 public asset;

    function approve(ERC20 token, address spender, uint256 value) external {
        asset = token;

        asset.safeApprove(spender, 0);
        asset.safeApprove(spender, value);
    }
}
