// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";

import {BaseTest} from "../BaseTest.sol";

contract RegistrationTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_MintAndRegister() public {
        vm.prank(address(operator));
        registrationWorkflows.mintAndRegisterIp(address(spgNft), address(ipWorld), ipMetadataEmpty, false);
    }
}
