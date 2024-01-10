// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @title  Auth
/// @notice Simple authentication pattern
/// @author Based on code from https://github.com/makerdao/dss

contract Auth {
    mapping(address => uint256) public authorizedAccounts;

    event AddAuthorization(address account);
    event RemoveAuthorization(address account);

    modifier auth() {
        require(authorizedAccounts[msg.sender] == 1, "Not authorized");
        _;
    }

    function addAuthorization(address account) external auth {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }

    function removeAuthorization(address account) external auth {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
}
