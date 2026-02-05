// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IPWorld} from "../src/IPWorld.sol";
import {IPTokenDeployer} from "../src/IPTokenDeployer.sol";
import {IIPWorld} from "../src/interfaces/IIPWorld.sol";
import {IIPOwnerVault} from "../src/interfaces/IIPOwnerVault.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Constants} from "../utils/Constants.sol";

/// @title UpgradeIPWorld
/// @notice Upgrades IPWorld proxy to new implementation with 1% pool support
/// @dev Requires PRIVATE_KEY env var. Caller must be the IPWorld owner.
contract UpgradeIPWorld is Script {
    function run() external {
        address ipWorldProxy = Constants.IPWORLD;

        // =========================================================================
        // Pre-flight checks
        // =========================================================================

        require(block.chainid == 1514, "Wrong chain: must be Story mainnet (1514)");
        require(ipWorldProxy.code.length > 0, "IPWorld proxy not found");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(deployerPrivateKey);

        address currentOwner = OwnableUpgradeable(ipWorldProxy).owner();
        require(caller == currentOwner, "Caller is not owner of IPWorld");

        // Capture pre-upgrade state
        IIPWorld ipWorld = IIPWorld(ipWorldProxy);
        uint256 prePrecision = ipWorld.PRECISION();
        address preOwnerVault = ipWorld.ownerVault();
        address preTreasury = ipWorld.treasury();
        uint24 preBurnShare = ipWorld.burnShare();
        uint24 preIpOwnerShare = ipWorld.ipOwnerShare();
        uint24 preBuybackShare = ipWorld.buybackShare();
        uint256 preBidWallAmount = ipWorld.bidWallAmount();

        // Check: IPOwnerVault vesting duration is 180 days
        IIPOwnerVault vault = IIPOwnerVault(Constants.IPOWNER_VAULT);
        require(vault.vestingDuration() == 180 days, "Pre: vestingDuration should be 180 days");

        console2.log("=== Pre-Upgrade State ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Caller:", caller);
        console2.log("IPWorld proxy:", ipWorldProxy);
        console2.log("Current owner:", currentOwner);
        console2.log("Current V3_FEE:", ipWorld.V3_FEE());
        console2.log("Vesting duration (days):", vault.vestingDuration() / 1 days);

        // =========================================================================
        // Deploy and upgrade
        // =========================================================================

        uint256 newCreationFee = vm.envOr("CREATION_FEE", Constants.CREATION_FEE);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new IPTokenDeployer (IPToken now uses V3_FEE=10000)
        address newTokenDeployer = address(new IPTokenDeployer(ipWorldProxy));
        console2.log("New IPTokenDeployer deployed:", newTokenDeployer);

        // Step 2: Deploy new IPWorld implementation
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
                newCreationFee
            )
        );
        console2.log("New IPWorld implementation deployed:", newImpl);

        // Step 3: Upgrade proxy (no reinitializer needed, no storage changes)
        UUPSUpgradeable(ipWorldProxy).upgradeToAndCall(newImpl, "");

        vm.stopBroadcast();

        // =========================================================================
        // Post-upgrade verification
        // =========================================================================

        // Check 1: V3_FEE is now 10000
        assertEq(ipWorld.V3_FEE(), 10000, "Post: V3_FEE should be 10000");

        // Check 2: Owner unchanged
        assertEq(OwnableUpgradeable(ipWorldProxy).owner(), currentOwner, "Post: owner changed");

        // Check 3: Immutables preserved
        assertEq(ipWorld.PRECISION(), prePrecision, "Post: PRECISION changed");
        assertEq(ipWorld.ownerVault(), preOwnerVault, "Post: ownerVault changed");
        assertEq(ipWorld.treasury(), preTreasury, "Post: treasury changed");
        assertEq(ipWorld.burnShare(), preBurnShare, "Post: burnShare changed");
        assertEq(ipWorld.ipOwnerShare(), preIpOwnerShare, "Post: ipOwnerShare changed");
        assertEq(ipWorld.buybackShare(), preBuybackShare, "Post: buybackShare changed");
        assertEq(ipWorld.bidWallAmount(), preBidWallAmount, "Post: bidWallAmount changed");
        assertEq(ipWorld.creationFee(), newCreationFee, "Post: creationFee mismatch");

        console2.log("\n=== Post-Upgrade Verification Passed ===");
        console2.log("V3_FEE:", ipWorld.V3_FEE());
        console2.log("creationFee:", ipWorld.creationFee());
        console2.log("New IPTokenDeployer:", newTokenDeployer);
        console2.log("New implementation:", newImpl);
        console2.log("\n=== Upgrade Complete ===");
    }

    function assertEq(uint256 a, uint256 b, string memory msg) internal pure {
        require(a == b, msg);
    }

    function assertEq(address a, address b, string memory msg) internal pure {
        require(a == b, msg);
    }
}
