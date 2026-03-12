// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPWorld} from "../../src/IPWorld.sol";
import {IPTokenDeployer} from "../../src/IPTokenDeployer.sol";
import {IPOwnerVault} from "../../src/IPOwnerVault.sol";
import {IPWorldRoyaltyPolicy} from "../../src/IPWorldRoyaltyPolicy.sol";
import {IIPWorld} from "../../src/interfaces/IIPWorld.sol";
import {IIPOwnerVault} from "../../src/interfaces/IIPOwnerVault.sol";
import {IGraphAwareRoyaltyPolicy} from "../../src/interfaces/storyprotocol/IGraphAwareRoyaltyPolicy.sol";
import {Constants} from "../../utils/Constants.sol";

/// @title UpgradeAllTest
/// @notice Fork-based tests for deploying new RoyaltyPolicy and upgrading IPOwnerVault + IPWorld
contract UpgradeAllTest is Test {
    address constant VAULT_PROXY = 0x81336266Ba5F26B8AFf7d2b2A2305F52A39292b2;
    address constant IPWORLD_PROXY = 0xd0EFb8Cd4c7a3Eefe823Fe963af9661D8F0CB745;
    address constant OWNER = 0xA4fBE288bAbd27dc792e811C826E855989273090;

    function setUp() public {
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);
    }

    /// @notice Tests deploying new RoyaltyPolicy + upgrading IPOwnerVault and IPWorld
    function test_UpgradeAll() public {
        IIPWorld ipWorld = IIPWorld(IPWORLD_PROXY);
        IIPOwnerVault vault = IIPOwnerVault(VAULT_PROXY);

        // Capture pre-upgrade state
        address preIpWorldOwner = OwnableUpgradeable(IPWORLD_PROXY).owner();
        address preVaultOwner = OwnableUpgradeable(VAULT_PROXY).owner();
        uint256 prePrecision = ipWorld.PRECISION();
        address preOwnerVault = ipWorld.ownerVault();
        address preTreasury = ipWorld.treasury();
        uint64 preVestingDuration = vault.vestingDuration();

        vm.startPrank(OWNER);

        // 1. Deploy new RoyaltyPolicy proxy (fresh deploy, not upgrade)
        address newRoyaltyPolicyImpl = address(new IPWorldRoyaltyPolicy());
        address newRoyaltyPolicyProxy = address(
            new ERC1967Proxy(newRoyaltyPolicyImpl, abi.encodeCall(IPWorldRoyaltyPolicy.initialize, (OWNER)))
        );

        // 2. Upgrade IPOwnerVault
        address newVaultImpl = address(new IPOwnerVault(IPWORLD_PROXY, Constants.VESTING_DURATION));
        UUPSUpgradeable(VAULT_PROXY).upgradeToAndCall(newVaultImpl, "");

        // 3. Upgrade IPWorld
        address newTokenDeployer = address(new IPTokenDeployer(IPWORLD_PROXY));
        address newWorldImpl = address(
            new IPWorld(
                Constants.WETH,
                Constants.V3_DEPLOYER,
                Constants.V3_FACTORY,
                newTokenDeployer,
                VAULT_PROXY,
                Constants.TREASURY,
                Constants.AIRDROP_SHARE,
                Constants.IP_OWNER_SHARE,
                Constants.BUYBACK_SHARE,
                Constants.BID_WALL_AMOUNT,
                Constants.CREATION_FEE,
                Constants.REFERRAL_SHARE
            )
        );
        UUPSUpgradeable(IPWORLD_PROXY).upgradeToAndCall(newWorldImpl, "");

        vm.stopPrank();

        // Verify owners preserved / set correctly
        assertEq(OwnableUpgradeable(IPWORLD_PROXY).owner(), preIpWorldOwner, "IPWorld owner changed");
        assertEq(OwnableUpgradeable(VAULT_PROXY).owner(), preVaultOwner, "Vault owner changed");
        assertEq(OwnableUpgradeable(newRoyaltyPolicyProxy).owner(), OWNER, "RoyaltyPolicy owner not set");

        // Verify IPWorld state preserved
        assertEq(ipWorld.PRECISION(), prePrecision, "PRECISION changed");
        assertEq(ipWorld.ownerVault(), preOwnerVault, "ownerVault changed");
        assertEq(ipWorld.treasury(), preTreasury, "treasury changed");
        assertEq(ipWorld.V3_FEE(), 10000, "V3_FEE should be 10000");
        assertEq(ipWorld.ANTI_SNIPE_DURATION(), 120, "ANTI_SNIPE_DURATION should be 120");
        assertEq(ipWorld.creationFee(), Constants.CREATION_FEE, "creationFee mismatch");

        // Verify post-upgrade IPWorld immutable params
        assertEq(ipWorld.airdropShare(), Constants.AIRDROP_SHARE, "airdropShare mismatch");
        assertEq(ipWorld.ipOwnerShare(), Constants.IP_OWNER_SHARE, "ipOwnerShare mismatch");
        assertEq(ipWorld.buybackShare(), Constants.BUYBACK_SHARE, "buybackShare mismatch");
        assertEq(ipWorld.bidWallAmount(), Constants.BID_WALL_AMOUNT, "bidWallAmount mismatch");

        // Verify vault state preserved
        assertEq(vault.vestingDuration(), preVestingDuration, "vestingDuration changed");

        // Verify new royalty policy functions correctly
        IGraphAwareRoyaltyPolicy royaltyPolicy = IGraphAwareRoyaltyPolicy(newRoyaltyPolicyProxy);
        assertEq(royaltyPolicy.getPolicyRoyaltyStack(address(0)), 3000, "RoyaltyPolicy royalty stack wrong");
        assertEq(royaltyPolicy.getPolicyRoyalty(address(1), address(2)), 3000, "RoyaltyPolicy royalty wrong");
    }

    /// @notice Verifies that a non-owner cannot upgrade the new RoyaltyPolicy
    function test_NonOwnerCannotUpgradeRoyaltyPolicy() public {
        // Deploy new RoyaltyPolicy proxy as owner
        vm.startPrank(OWNER);
        address newImpl = address(new IPWorldRoyaltyPolicy());
        address newProxy = address(
            new ERC1967Proxy(newImpl, abi.encodeCall(IPWorldRoyaltyPolicy.initialize, (OWNER)))
        );
        vm.stopPrank();

        // Verify owner is set
        assertEq(OwnableUpgradeable(newProxy).owner(), OWNER);

        // Attempt upgrade as non-owner should revert
        address attacker = makeAddr("attacker");
        address maliciousImpl = address(new IPWorldRoyaltyPolicy());

        vm.prank(attacker);
        vm.expectRevert();
        UUPSUpgradeable(newProxy).upgradeToAndCall(maliciousImpl, "");
    }

    /// @notice Verifies that RoyaltyPolicy functionality works correctly on fresh deploy
    function test_RoyaltyPolicyFunctionalityPreserved() public {
        // Deploy new RoyaltyPolicy proxy
        vm.startPrank(OWNER);
        address newImpl = address(new IPWorldRoyaltyPolicy());
        address newProxy = address(
            new ERC1967Proxy(newImpl, abi.encodeCall(IPWorldRoyaltyPolicy.initialize, (OWNER)))
        );
        vm.stopPrank();

        IGraphAwareRoyaltyPolicy royaltyPolicy = IGraphAwareRoyaltyPolicy(newProxy);

        // Verify all public functions return correct values
        assertEq(royaltyPolicy.getPolicyRoyaltyStack(address(0)), 3000, "getPolicyRoyaltyStack not 3000");
        assertEq(royaltyPolicy.getPolicyRoyalty(address(1), address(2)), 3000, "getPolicyRoyalty not 3000");
        assertEq(royaltyPolicy.getTransferredTokens(address(1), address(2), address(3)), 0, "getTransferredTokens not 0");
        assertEq(royaltyPolicy.transferToVault(address(1), address(2), address(3)), 0, "transferToVault not 0");
        assertEq(royaltyPolicy.isSupportGroup(), false, "isSupportGroup not false");
        assertEq(royaltyPolicy.getPolicyRtsRequiredToLink(address(1), 100), 0, "getPolicyRtsRequiredToLink not 0");

        // Verify ERC165 supportsInterface
        IERC165 erc165 = IERC165(newProxy);
        assertTrue(erc165.supportsInterface(type(IGraphAwareRoyaltyPolicy).interfaceId), "ERC165 IGraphAwareRoyaltyPolicy");
        assertTrue(erc165.supportsInterface(bytes4(0x01ffc9a7)), "ERC165 IERC165");

        // Verify owner can upgrade
        vm.startPrank(OWNER);
        address newImpl2 = address(new IPWorldRoyaltyPolicy());
        UUPSUpgradeable(newProxy).upgradeToAndCall(newImpl2, "");
        vm.stopPrank();

        // Still works after upgrade
        assertEq(royaltyPolicy.getPolicyRoyaltyStack(address(0)), 3000, "Post-upgrade royaltyStack wrong");
    }
}
