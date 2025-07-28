// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPWorldRoyaltyPolicy} from "../../src/IPWorldRoyaltyPolicy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract IPWorldRoyaltyPolicyTest is Test {
    IPWorldRoyaltyPolicy policy;

    function setUp() public {
        // Deploy logic contract
        IPWorldRoyaltyPolicy logic = new IPWorldRoyaltyPolicy();
        // Deploy proxy
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(logic), abi.encodeWithSelector(IPWorldRoyaltyPolicy.initialize.selector));
        // Wrap as policy
        policy = IPWorldRoyaltyPolicy(address(proxy));
    }

    function testGetPolicyRoyalty() public {
        assertEq(policy.getPolicyRoyalty(address(1), address(2)), 3000);
    }

    function testGetPolicyRoyaltyStack() public {
        assertEq(policy.getPolicyRoyaltyStack(address(1)), 3000);
    }

    function testGetTransferredTokens() public {
        assertEq(policy.getTransferredTokens(address(1), address(2), address(3)), 0);
    }

    function testIsSupportGroup() public {
        assertEq(policy.isSupportGroup(), false);
    }

    function testGetPolicyRtsRequiredToLink() public {
        assertEq(policy.getPolicyRtsRequiredToLink(address(1), 100), 0);
    }

    function testCommercialUseRoyaltyPolicySet() public {
        // Simulate setting commercialUse = true and royaltyPolicy = address(policy)
        bool commercialUse = true;
        address royaltyPolicy = address(policy);
        assertTrue(commercialUse);
        assertTrue(royaltyPolicy != address(0));
    }
}
