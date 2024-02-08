// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
// import "hardhat/console.sol";
import {ERC20} from "./tokens/ERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract Escrow {
    ERC20 public asset;

    function approve(ERC20 token, address spender, uint256 value) external {
        asset = token;

        asset.approve(spender, 0);
        asset.approve(spender, value);
    }

    function transferOut(address receiver, uint256 value) external {
        require(value > 0, "Value must be greater than 0");

        uint256 balanceBefore = IERC20(address(asset)).balanceOf(address(this));

        require(balanceBefore >= value, "Insufficient balance in Escrow");

        IERC20(address(asset)).transfer(receiver, value);

        uint256 balanceAfter = IERC20(address(asset)).balanceOf(address(this));

        require(balanceBefore - value == balanceAfter, "Transfer failed: Incorrect balance");
    }
}
