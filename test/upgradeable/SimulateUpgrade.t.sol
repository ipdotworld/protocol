// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IPWorld} from "../../src/IPWorld.sol";
import {IPTokenDeployer} from "../../src/IPTokenDeployer.sol";
import {IIPWorld} from "../../src/interfaces/IIPWorld.sol";
import {IIPOwnerVault} from "../../src/interfaces/IIPOwnerVault.sol";
import {Constants} from "../../utils/Constants.sol";

/// @title SimulateUpgrade
/// @notice Simulates UpgradeIPWorld on a mainnet fork with creationFee = 0
contract SimulateUpgradeTest is Test {
    address constant IPWORLD_PROXY = 0xd0EFb8Cd4c7a3Eefe823Fe963af9661D8F0CB745;
    uint256 constant NEW_CREATION_FEE = 0;

    function test_SimulateUpgrade() public {
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);

        IIPWorld ipWorld = IIPWorld(IPWORLD_PROXY);
        address currentOwner = OwnableUpgradeable(IPWORLD_PROXY).owner();

        // =========================================================================
        // Pre-upgrade state
        // =========================================================================
        console2.log("=== Pre-Upgrade State ===");
        console2.log("IPWorld proxy:", IPWORLD_PROXY);
        console2.log("Current owner:", currentOwner);
        console2.log("V3_FEE:", ipWorld.V3_FEE());
        console2.log("PRECISION:", ipWorld.PRECISION());
        console2.log("ownerVault:", ipWorld.ownerVault());
        console2.log("treasury:", ipWorld.treasury());
        console2.log("burnShare:", ipWorld.burnShare());
        console2.log("ipOwnerShare:", ipWorld.ipOwnerShare());
        console2.log("buybackShare:", ipWorld.buybackShare());
        console2.log("bidWallAmount:", ipWorld.bidWallAmount());

        // creationFee may not exist on current implementation
        uint256 preCreationFee;
        try ipWorld.creationFee() returns (uint256 fee) {
            preCreationFee = fee;
            console2.log("creationFee:", fee);
        } catch {
            console2.log("creationFee: N/A (not in current impl)");
        }

        uint256 prePrecision = ipWorld.PRECISION();
        address preOwnerVault = ipWorld.ownerVault();
        address preTreasury = ipWorld.treasury();
        uint24 preBurnShare = ipWorld.burnShare();
        uint24 preIpOwnerShare = ipWorld.ipOwnerShare();
        uint24 preBuybackShare = ipWorld.buybackShare();
        uint256 preBidWallAmount = ipWorld.bidWallAmount();

        IIPOwnerVault vault = IIPOwnerVault(Constants.IPOWNER_VAULT);
        console2.log("Vesting duration (days):", vault.vestingDuration() / 1 days);
        assertEq(vault.vestingDuration(), 180 days, "Pre: vestingDuration should be 180 days");

        // Check existing operators
        console2.log("Operator check - Constants.OWNER is operator:", ipWorld.isOperator(Constants.OWNER));

        // =========================================================================
        // Deploy and upgrade (as owner)
        // =========================================================================
        console2.log("\n=== Deploying New Implementation (creationFee = 0) ===");

        vm.startPrank(currentOwner);

        // Step 1: Deploy new IPTokenDeployer
        address newTokenDeployer = address(new IPTokenDeployer(IPWORLD_PROXY));
        console2.log("New IPTokenDeployer:", newTokenDeployer);

        // Step 2: Deploy new IPWorld implementation with creationFee = 0
        address newImpl = address(
            new IPWorld(
                Constants.WETH,
                Constants.V3_DEPLOYER,
                Constants.V3_FACTORY,
                newTokenDeployer,
                Constants.IPOWNER_VAULT,
                Constants.TREASURY,
                Constants.BURN_SHARE,
                Constants.IP_OWNER_SHARE,
                Constants.BUYBACK_SHARE,
                Constants.BID_WALL_AMOUNT,
                NEW_CREATION_FEE
            )
        );
        console2.log("New IPWorld implementation:", newImpl);

        // Step 3: Upgrade
        UUPSUpgradeable(IPWORLD_PROXY).upgradeToAndCall(newImpl, "");

        vm.stopPrank();

        // =========================================================================
        // Post-upgrade verification
        // =========================================================================
        console2.log("\n=== Post-Upgrade State ===");
        console2.log("V3_FEE:", ipWorld.V3_FEE());
        console2.log("creationFee:", ipWorld.creationFee());
        console2.log("owner:", OwnableUpgradeable(IPWORLD_PROXY).owner());

        // Assertions
        assertEq(ipWorld.V3_FEE(), 10000, "Post: V3_FEE should be 10000");
        assertEq(OwnableUpgradeable(IPWORLD_PROXY).owner(), currentOwner, "Post: owner changed");
        assertEq(ipWorld.PRECISION(), prePrecision, "Post: PRECISION changed");
        assertEq(ipWorld.ownerVault(), preOwnerVault, "Post: ownerVault changed");
        assertEq(ipWorld.treasury(), preTreasury, "Post: treasury changed");
        assertEq(ipWorld.burnShare(), preBurnShare, "Post: burnShare changed");
        assertEq(ipWorld.ipOwnerShare(), preIpOwnerShare, "Post: ipOwnerShare changed");
        assertEq(ipWorld.buybackShare(), preBuybackShare, "Post: buybackShare changed");
        assertEq(ipWorld.bidWallAmount(), preBidWallAmount, "Post: bidWallAmount changed");
        assertEq(ipWorld.creationFee(), NEW_CREATION_FEE, "Post: creationFee should be 0");

        console2.log("\n=== All Post-Upgrade Checks Passed ===");
        console2.log("creationFee changed:", preCreationFee, "->", NEW_CREATION_FEE);
        console2.log("New IPTokenDeployer:", newTokenDeployer);
        console2.log("New implementation:", newImpl);
    }
}
