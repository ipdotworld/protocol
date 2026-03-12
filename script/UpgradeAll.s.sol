// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPWorld} from "../src/IPWorld.sol";
import {IPTokenDeployer} from "../src/IPTokenDeployer.sol";
import {IPOwnerVault} from "../src/IPOwnerVault.sol";
import {IPWorldRoyaltyPolicy} from "../src/IPWorldRoyaltyPolicy.sol";
import {IIPWorld} from "../src/interfaces/IIPWorld.sol";
import {IGraphAwareRoyaltyPolicy} from "../src/interfaces/storyprotocol/IGraphAwareRoyaltyPolicy.sol";
import {Constants} from "../utils/Constants.sol";

/// @title UpgradeAll
/// @notice Deploys new IPWorldRoyaltyPolicy proxy and upgrades IPOwnerVault + IPWorld
/// @dev Requires PRIVATE_KEY env var. Caller must be the owner of IPWorld and IPOwnerVault.
///      Supports Story mainnet (1514) and Aeneid testnet (1315).
///      IPWorldRoyaltyPolicy is deployed fresh (not upgraded) due to missing access control on old proxy.
contract UpgradeAll is Script {
    function run() external returns (address newRoyaltyPolicyProxy) {
        bool isTestnet = block.chainid == 1315;
        require(block.chainid == 1514 || isTestnet, "Wrong chain");

        // Resolve proxy addresses per chain
        address vaultProxy = isTestnet ? Constants.IPOWNER_VAULT_AENEID : Constants.IPOWNER_VAULT;
        address ipWorldProxy = isTestnet ? Constants.IPWORLD_AENEID : Constants.IPWORLD;
        address owner = Constants.OWNER;

        // Pre-upgrade: verify proxy existence
        require(vaultProxy.code.length > 0, "IPOwnerVault proxy not found");
        require(ipWorldProxy.code.length > 0, "IPWorld proxy not found");

        // Pre-upgrade: verify caller is the owner
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(deployerPrivateKey);

        address ipWorldOwner = OwnableUpgradeable(ipWorldProxy).owner();
        require(caller == ipWorldOwner, "Caller is not owner of IPWorld");

        address vaultOwner = OwnableUpgradeable(vaultProxy).owner();
        require(caller == vaultOwner, "Caller is not owner of IPOwnerVault");

        _logPreState(vaultProxy, ipWorldProxy, caller, isTestnet);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new IPWorldRoyaltyPolicy (fresh proxy, not upgrade)
        newRoyaltyPolicyProxy = _deployRoyaltyPolicy(owner);

        // 2. Upgrade IPOwnerVault
        address newVaultImpl = _upgradeIPOwnerVault(vaultProxy, ipWorldProxy);

        // 3. Upgrade IPWorld (deploy new IPTokenDeployer first)
        (address newTokenDeployer, address newWorldImpl) =
            _upgradeIPWorld(ipWorldProxy, vaultProxy, isTestnet, Constants.CREATION_FEE);

        vm.stopBroadcast();

        // Post-upgrade verification
        _verifyPostUpgrade(newRoyaltyPolicyProxy, vaultProxy, ipWorldProxy, owner);

        console2.log("\n=== Upgrade Complete ===");
        console2.log("New RoyaltyPolicy proxy:", newRoyaltyPolicyProxy);
        console2.log("New IPOwnerVault impl:", newVaultImpl);
        console2.log("New IPTokenDeployer:", newTokenDeployer);
        console2.log("New IPWorld impl:", newWorldImpl);
        console2.log("\nIMPORTANT: Update Constants.ROYALTY_POLICY with new proxy address above");
    }

    function _logPreState(
        address vaultProxy,
        address ipWorldProxy,
        address caller,
        bool isTestnet
    ) internal view {
        IIPWorld ipWorld = IIPWorld(ipWorldProxy);

        console2.log("=== Pre-Upgrade State ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Network:", isTestnet ? "Aeneid Testnet" : "Story Mainnet");
        console2.log("Caller:", caller);
        console2.log("IPOwnerVault proxy:", vaultProxy);
        console2.log("IPWorld proxy:", ipWorldProxy);
        console2.log("IPWorld V3_FEE:", ipWorld.V3_FEE());
    }

    /// @notice Deploys a fresh IPWorldRoyaltyPolicy proxy with proper access control
    /// @dev Old proxy has no access control on _authorizeUpgrade, so we deploy a new one
    function _deployRoyaltyPolicy(address owner) internal returns (address newProxy) {
        address newImpl = address(new IPWorldRoyaltyPolicy());
        console2.log("\nNew RoyaltyPolicy impl:", newImpl);

        newProxy = address(
            new ERC1967Proxy(newImpl, abi.encodeCall(IPWorldRoyaltyPolicy.initialize, (owner)))
        );
        console2.log("New RoyaltyPolicy proxy deployed:", newProxy);
    }

    /// @notice Upgrades IPOwnerVault (no reinitialization needed)
    function _upgradeIPOwnerVault(address proxy, address ipWorldProxy) internal returns (address newImpl) {
        newImpl = address(new IPOwnerVault(ipWorldProxy, Constants.VESTING_DURATION));
        console2.log("\nNew IPOwnerVault impl:", newImpl);

        UUPSUpgradeable(proxy).upgradeToAndCall(newImpl, "");
        console2.log("IPOwnerVault proxy upgraded");
    }

    /// @notice Upgrades IPWorld with new IPTokenDeployer
    function _upgradeIPWorld(address ipWorldProxy, address vaultProxy, bool isTestnet, uint256 newCreationFee)
        internal
        returns (address newTokenDeployer, address newWorldImpl)
    {
        address v3Deployer = isTestnet ? Constants.V3_DEPLOYER_AENEID : Constants.V3_DEPLOYER;
        address v3Factory = isTestnet ? Constants.V3_FACTORY_AENEID : Constants.V3_FACTORY;

        // Step 1: Deploy new IPTokenDeployer
        newTokenDeployer = address(new IPTokenDeployer(ipWorldProxy));
        console2.log("\nNew IPTokenDeployer:", newTokenDeployer);

        // Step 2: Deploy new IPWorld implementation
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

        // Step 3: Upgrade
        UUPSUpgradeable(ipWorldProxy).upgradeToAndCall(newWorldImpl, "");
        console2.log("IPWorld proxy upgraded");
    }

    function _verifyPostUpgrade(address royaltyPolicyProxy, address vaultProxy, address ipWorldProxy, address owner)
        internal
        view
    {
        // Verify RoyaltyPolicy
        IGraphAwareRoyaltyPolicy royaltyPolicy = IGraphAwareRoyaltyPolicy(royaltyPolicyProxy);
        require(
            OwnableUpgradeable(royaltyPolicyProxy).owner() == owner, "Post: RoyaltyPolicy owner not set correctly"
        );
        require(royaltyPolicy.getPolicyRoyaltyStack(address(0)) == 3000, "Post: RoyaltyPolicy royalty changed");
        console2.log("\nRoyaltyPolicy owner:", OwnableUpgradeable(royaltyPolicyProxy).owner());
        console2.log("RoyaltyPolicy royaltyStack:", royaltyPolicy.getPolicyRoyaltyStack(address(0)));

        // Verify IPOwnerVault
        require(OwnableUpgradeable(vaultProxy).owner() == owner, "Post: IPOwnerVault owner changed");
        console2.log("IPOwnerVault owner:", OwnableUpgradeable(vaultProxy).owner());

        // Verify IPWorld
        IIPWorld ipWorld = IIPWorld(ipWorldProxy);
        require(ipWorld.V3_FEE() == 10000, "Post: V3_FEE should be 10000");
        require(ipWorld.ANTI_SNIPE_DURATION() == 120, "Post: ANTI_SNIPE_DURATION should be 120");
        require(OwnableUpgradeable(ipWorldProxy).owner() == owner, "Post: IPWorld owner changed");
        require(ipWorld.ownerVault() == vaultProxy, "Post: ownerVault mismatch");
        require(ipWorld.creationFee() == Constants.CREATION_FEE, "Post: creationFee mismatch");
        console2.log("IPWorld owner:", OwnableUpgradeable(ipWorldProxy).owner());
        console2.log("IPWorld V3_FEE:", ipWorld.V3_FEE());
        console2.log("IPWorld creationFee:", ipWorld.creationFee());
        console2.log("IPWorld ownerVault:", ipWorld.ownerVault());
    }
}
