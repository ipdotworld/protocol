// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IPWorld} from "../src/IPWorld.sol";
import {IPOwnerVault} from "../src/IPOwnerVault.sol";
import {IPTokenDeployer} from "../src/IPTokenDeployer.sol";
import {IPWorldRoyaltyPolicy} from "../src/IPWorldRoyaltyPolicy.sol";
import {IIPOwnerVault} from "../src/interfaces/IIPOwnerVault.sol";
import {IIPWorld} from "../src/interfaces/IIPWorld.sol";
import {IIPTokenDeployer} from "../src/interfaces/IIPTokenDeployer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../utils/Constants.sol";

contract IPWorldDeploy is Script {
    function run()
        external
        returns (address ipWorld, address ownerVault, address tokenDeployer, address royaltyPolicy)
    {
        // Get RPC URL from environment
        string memory rpcUrl = vm.envString("RPC_URL");
        vm.createSelectFork(rpcUrl);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deploying from:", deployer);
        console2.log("Using RPC URL:", rpcUrl);
        console2.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy IPTokenDeployer with expected IPWorld address
        // Calculate future IPWorld proxy address
        // Deployment order: IPTokenDeployer, IPOwnerVault impl, IPOwnerVault proxy, IPWorld impl, IPWorld proxy
        uint256 currentNonce = vm.getNonce(deployer);
        address expectedIpWorldAddress = vm.computeCreateAddress(deployer, currentNonce + 4);

        tokenDeployer = address(new IPTokenDeployer(expectedIpWorldAddress));
        console2.log("IPTokenDeployer deployed:", tokenDeployer);

        // Step 2: Deploy IPOwnerVault proxy
        address ownerVaultImpl = address(new IPOwnerVault(expectedIpWorldAddress, Constants.VESTING_DURATION));
        ownerVault = address(
            new ERC1967Proxy(ownerVaultImpl, abi.encodeWithSelector(IPOwnerVault.initialize.selector, deployer))
        );
        console2.log("IPOwnerVault proxy deployed:", ownerVault);

        // Step 3: Deploy IPWorld proxy
        address ipWorldImpl = address(
            new IPWorld(
                Constants.WETH,
                getV3Deployer(),
                getV3Factory(),
                tokenDeployer,
                ownerVault,
                Constants.TREASURY,
                Constants.BURN_SHARE,
                Constants.IP_OWNER_SHARE,
                Constants.BUYBACK_SHARE,
                Constants.BID_WALL_AMOUNT
            )
        );
        ipWorld = address(new ERC1967Proxy(ipWorldImpl, abi.encodeWithSelector(IPWorld.initialize.selector, deployer)));
        console2.log("IPWorld proxy deployed:", ipWorld);

        require(ipWorld == expectedIpWorldAddress, "IPWorld address mismatch");

        // Step 4: Deploy IPWorldRoyaltyPolicy proxy
        address royaltyPolicyImpl = address(new IPWorldRoyaltyPolicy());
        royaltyPolicy = address(
            new ERC1967Proxy(royaltyPolicyImpl, abi.encodeWithSelector(IPWorldRoyaltyPolicy.initialize.selector))
        );
        console2.log("IPWorldRoyaltyPolicy proxy deployed:", royaltyPolicy);

        vm.stopBroadcast();

        console2.log("\nDeployment Summary:");
        console2.log("===================");
        console2.log("IPWorld:", ipWorld);
        console2.log("IPOwnerVault:", ownerVault);
        console2.log("IPTokenDeployer:", tokenDeployer);
        console2.log("IPWorldRoyaltyPolicy:", royaltyPolicy);

        return (ipWorld, ownerVault, tokenDeployer, royaltyPolicy);
    }

    function getV3Factory() private view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1514) {
            // Story mainnet
            return Constants.V3_FACTORY;
        } else if (chainId == 1315) {
            // Story Aeneid testnet
            return Constants.V3_FACTORY_AENEID;
        } else {
            revert("Unsupported chain ID. Only Story mainnet (1514) and Aeneid testnet (1315) are supported.");
        }
    }

    function getSwapRouter() private view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1514) {
            // Story mainnet
            return Constants.SWAP_ROUTER;
        } else if (chainId == 1315) {
            // Story Aeneid testnet
            return Constants.SWAP_ROUTER_AENEID;
        } else {
            revert("Unsupported chain ID. Only Story mainnet (1514) and Aeneid testnet (1315) are supported.");
        }
    }

    function getNFTPositionManager() private view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1514) {
            // Story mainnet
            return Constants.NFT_POSITION_MANAGER;
        } else if (chainId == 1315) {
            // Story Aeneid testnet
            return Constants.NFT_POSITION_MANAGER_AENEID;
        } else {
            revert("Unsupported chain ID. Only Story mainnet (1514) and Aeneid testnet (1315) are supported.");
        }
    }

    function getV3Deployer() private view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1514) {
            // Story mainnet
            return Constants.V3_DEPLOYER;
        } else if (chainId == 1315) {
            // Story Aeneid testnet
            return Constants.V3_DEPLOYER_AENEID;
        } else {
            revert("Unsupported chain ID. Only Story mainnet (1514) and Aeneid testnet (1315) are supported.");
        }
    }
}
