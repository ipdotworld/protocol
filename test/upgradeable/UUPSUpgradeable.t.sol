// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import {IPWorld} from "../../src/IPWorld.sol";
import {IIPWorld} from "../../src/interfaces/IIPWorld.sol";
import {Constants} from "../../utils/Constants.sol";

contract UUPSUpgradeableTest is Test {
    IIPWorld public ipWorld;

    function setUp() public {
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);
        address template = address(
            new IPWorld(
                address(0x01),
                address(0x02),
                address(0x03),
                address(0x06),
                address(0x04),
                address(0x05),
                500_000,
                300_000,
                500_000,
                500 ether
            )
        );
        address owner = address(0x08);
        ipWorld =
            IIPWorld(address(new ERC1967Proxy(template, abi.encodeWithSelector(IPWorld.initialize.selector, owner))));
    }

    function test_UUPSUpgradeable() public {
        assertEq(Ownable(address(ipWorld)).owner(), address(0x08));
        assertEq(ipWorld.PRECISION(), 1000000);
        assertEq(address(ipWorld.ownerVault()), address(0x04));

        address template = address(new XXXX());

        uint64 version = 3;
        vm.prank(address(0x08));
        UUPSUpgradeable(address(ipWorld)).upgradeToAndCall(
            template, abi.encodeWithSelector(XXXX.initialize.selector, address(this), version)
        );

        assertEq(Ownable(address(ipWorld)).owner(), address(this));
    }
}

contract XXXX is Ownable2StepUpgradeable, UUPSUpgradeable {
    function initialize(address owner, uint64 version) public reinitializer(version) {
        __Ownable_init(owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
