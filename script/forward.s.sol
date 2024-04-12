// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;


import {Deployer} from "./Deployer.s.sol";

contract Forward is Deployer {
     function setUp() public {}

     function run() public {
        vm.startBroadcast();
        deploy();
           vm.stopBroadcast();
    }
}