// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IPWorld} from "../src/IPWorld.sol";
import {IPTokenDeployer} from "../src/IPTokenDeployer.sol";
import {IIPWorld} from "../src/interfaces/IIPWorld.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Constants} from "../utils/Constants.sol";

/// @title UpgradeIPWorld
/// @notice Upgrades IPWorld proxy using the existing IPOwnerVault
/// @dev Requires PRIVATE_KEY env var. Caller must be the owner of IPWorld.
///      Supports Story mainnet (1514) and Aeneid testnet (1315).
contract UpgradeIPWorld is Script {
    function run() external {
        bool isTestnet = block.chainid == 1315;
        require(block.chainid == 1514 || isTestnet, "Wrong chain");

        address ipWorldProxy = isTestnet
            ? Constants.IPWORLD_AENEID
            : Constants.IPWORLD;
        address vaultProxy = isTestnet
            ? Constants.IPOWNER_VAULT_AENEID
            : Constants.IPOWNER_VAULT;

        require(ipWorldProxy.code.length > 0, "IPWorld proxy not found");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(deployerPrivateKey);

        address ipWorldOwner = OwnableUpgradeable(ipWorldProxy).owner();
        require(caller == ipWorldOwner, "Caller is not owner of IPWorld");

        _logPreState(ipWorldProxy, vaultProxy, caller, isTestnet);

        vm.startBroadcast(deployerPrivateKey);

        (address newTokenDeployer, address newWorldImpl) = _upgradeIPWorld(
            ipWorldProxy,
            vaultProxy,
            isTestnet,
            Constants.CREATION_FEE
        );

        vm.stopBroadcast();

        _verifyPostUpgrade(
            ipWorldProxy,
            vaultProxy,
            ipWorldOwner,
            Constants.CREATION_FEE
        );

        console2.log("\n=== Post-Upgrade Verification Passed ===");
        console2.log("IPOwnerVault proxy:", vaultProxy);
        console2.log("New IPTokenDeployer:", newTokenDeployer);
        console2.log("New IPWorld impl:", newWorldImpl);
        console2.log("=== Upgrade Complete ===");
    }

    function _logPreState(
        address ipWorldProxy,
        address vaultProxy,
        address caller,
        bool isTestnet
    ) internal view {
        IIPWorld ipWorld = IIPWorld(ipWorldProxy);

        console2.log("=== Pre-Upgrade State ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Caller:", caller);
        console2.log("IPWorld proxy:", ipWorldProxy);
        console2.log("IPOwnerVault proxy:", vaultProxy);
        console2.log("Current V3_FEE:", ipWorld.V3_FEE());
        console2.log(
            "V3 Deployer:",
            isTestnet ? Constants.V3_DEPLOYER_AENEID : Constants.V3_DEPLOYER
        );
        console2.log(
            "V3 Factory:",
            isTestnet ? Constants.V3_FACTORY_AENEID : Constants.V3_FACTORY
        );
    }

    function _upgradeIPWorld(
        address ipWorldProxy,
        address vaultProxy,
        bool isTestnet,
        uint256 newCreationFee
    ) internal returns (address newTokenDeployer, address newWorldImpl) {
        address v3Deployer = isTestnet
            ? Constants.V3_DEPLOYER_AENEID
            : Constants.V3_DEPLOYER;
        address v3Factory = isTestnet
            ? Constants.V3_FACTORY_AENEID
            : Constants.V3_FACTORY;

        newTokenDeployer = address(new IPTokenDeployer(ipWorldProxy));
        console2.log("\nNew IPTokenDeployer:", newTokenDeployer);

        newWorldImpl = address(
            new IPWorld(
                Constants.WETH,
                v3Deployer,
                v3Factory,
                newTokenDeployer,
                vaultProxy,
                Constants.TREASURY,
                Constants.AIRDROP_SHARE,
                Constants.IP_OWNER_SHARE,
                Constants.BUYBACK_SHARE,
                Constants.BID_WALL_AMOUNT,
                newCreationFee,
                Constants.REFERRAL_SHARE
            )
        );
        console2.log("New IPWorld impl:", newWorldImpl);

        UUPSUpgradeable(ipWorldProxy).upgradeToAndCall(newWorldImpl, "");
        console2.log("IPWorld proxy upgraded");
    }

    function _verifyPostUpgrade(
        address ipWorldProxy,
        address vaultProxy,
        address expectedOwner,
        uint256 expectedCreationFee
    ) internal view {
        IIPWorld ipWorld = IIPWorld(ipWorldProxy);

        require(ipWorld.V3_FEE() == 10000, "Post: V3_FEE should be 10000");
        require(
            ipWorld.ANTI_SNIPE_DURATION() == 120,
            "Post: ANTI_SNIPE_DURATION should be 120"
        );
        require(
            OwnableUpgradeable(ipWorldProxy).owner() == expectedOwner,
            "Post: IPWorld owner changed"
        );
        require(
            ipWorld.ownerVault() == vaultProxy,
            "Post: ownerVault mismatch"
        );
        require(
            ipWorld.creationFee() == expectedCreationFee,
            "Post: creationFee mismatch"
        );

        console2.log("\nV3_FEE:", ipWorld.V3_FEE());
        console2.log("ANTI_SNIPE_DURATION:", ipWorld.ANTI_SNIPE_DURATION());
        console2.log("creationFee:", ipWorld.creationFee());
        console2.log("ownerVault:", ipWorld.ownerVault());
    }
}
