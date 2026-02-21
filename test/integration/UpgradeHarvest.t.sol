// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IPWorld} from "../../src/IPWorld.sol";
import {IPTokenDeployer} from "../../src/IPTokenDeployer.sol";
import {IIPWorld} from "../../src/interfaces/IIPWorld.sol";
import {Constants} from "../../utils/Constants.sol";

/// @title UpgradeHarvestTest
/// @notice Tests that harvest works for migrated tokens after IPWorld upgrade to 1% pool
contract UpgradeHarvestTest is Test {
    address constant MIGRATED_TOKEN = 0x693c7AcF65e52C71bAFE555Bc22d69cB7f8a78a2;

    IIPWorld ipWorld;
    address owner;

    function setUp() public {
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);
        ipWorld = IIPWorld(Constants.IPWORLD);
        owner = Constants.OWNER;
    }

    /// @notice Upgrade IPWorld to new implementation and verify harvest works for migrated token
    function test_UpgradeAndHarvestMigratedToken() public {
        // Step 1: Verify token is registered
        (address ipaId, int24[] memory ticks) = ipWorld.tokenInfo(MIGRATED_TOKEN);
        console2.log("Token IPA:", ipaId);
        console2.log("Tick count:", ticks.length);
        assertTrue(ticks.length > 0, "Token should be registered in IPWorld");

        for (uint256 i = 0; i < ticks.length; i++) {
            console2.log("  tick[%d]:", i);
            console2.logInt(ticks[i]);
        }

        // Step 2: Deploy new IPWorld implementation
        address newImpl = address(
            new IPWorld(
                Constants.WETH,
                Constants.V3_DEPLOYER,
                Constants.V3_FACTORY,
                address(new IPTokenDeployer(Constants.IPWORLD)),
                Constants.IPOWNER_VAULT,
                Constants.TREASURY,
                Constants.AIRDROP_SHARE,
                Constants.IP_OWNER_SHARE,
                Constants.BUYBACK_SHARE,
                Constants.BID_WALL_AMOUNT,
                Constants.CREATION_FEE
            )
        );

        // Step 3: Upgrade proxy
        vm.prank(owner);
        UUPSUpgradeable(address(ipWorld)).upgradeToAndCall(newImpl, "");

        // Step 4: Verify V3_FEE is now 10000
        assertEq(ipWorld.V3_FEE(), 10000, "V3_FEE should be 10000 after upgrade");

        // Step 5: Try harvest - should not revert
        ipWorld.harvest(MIGRATED_TOKEN);

        console2.log("Harvest succeeded for migrated token");
    }
}
