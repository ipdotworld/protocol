// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IPWorld} from "../src/IPWorld.sol";
import {Constants} from "../utils/Constants.sol";

contract DeployIPWorldImpl is Script {
    function run() external {
        bool isTestnet = block.chainid == 1315;
        require(block.chainid == 1514 || isTestnet, "Wrong chain");

        address v3Deployer = isTestnet ? Constants.V3_DEPLOYER_AENEID : Constants.V3_DEPLOYER;
        address v3Factory = isTestnet ? Constants.V3_FACTORY_AENEID : Constants.V3_FACTORY;
        address tokenDeployer = address(0x44b982452b5e4eEc6B3cB0B1c847Ae4a495a14ED);
        address vaultProxy = isTestnet ? Constants.IPOWNER_VAULT_AENEID : Constants.IPOWNER_VAULT;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Deploying IPWorld Impl ===");
        console2.log("WETH:", Constants.WETH);
        console2.log("v3Deployer:", v3Deployer);
        console2.log("v3Factory:", v3Factory);
        console2.log("tokenDeployer:", tokenDeployer);
        console2.log("vaultProxy:", vaultProxy);
        console2.log("treasury:", Constants.TREASURY);

        vm.startBroadcast(deployerPrivateKey);

        address newWorldImpl = address(
            new IPWorld(
                Constants.WETH,
                v3Deployer,
                v3Factory,
                tokenDeployer,
                vaultProxy,
                Constants.TREASURY,
                Constants.AIRDROP_SHARE,
                Constants.IP_OWNER_SHARE,
                Constants.BUYBACK_SHARE,
                Constants.BID_WALL_AMOUNT,
                Constants.CREATION_FEE,
                Constants.REFERRAL_SHARE
            )
        );

        vm.stopBroadcast();

        console2.log("New IPWorld impl:", newWorldImpl);
    }
}
