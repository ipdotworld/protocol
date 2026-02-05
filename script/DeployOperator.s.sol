// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Operator} from "../src/Operator.sol";
import {Constants} from "../utils/Constants.sol";

/// @title DeployOperator
/// @notice Deploys a new Operator contract and registers it on IPWorld
/// @dev Requires PRIVATE_KEY env var. Caller must be the IPWorld owner.
contract DeployOperator is Script {
    address constant OLD_OPERATOR = 0x3A923bF60869D30b2ae12107EFF846790466492D;

    function run() external {
        require(block.chainid == 1514, "Wrong chain: must be Story mainnet (1514)");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(deployerPrivateKey);

        // Read old operator state
        Operator oldOp = Operator(OLD_OPERATOR);
        address oldIpWorld = address(oldOp.ipWorld());
        address oldSpgNft = oldOp.spgNft();
        address oldRoyaltyPolicy = oldOp.royaltyPolicy();
        string memory oldLicensingUrl = oldOp.licensingUrl();
        address oldExpectedSigner = oldOp.expectedSigner();
        address oldOwner = oldOp.owner();

        console2.log("=== Old Operator State ===");
        console2.log("Old Operator:", OLD_OPERATOR);
        console2.log("ipWorld:", oldIpWorld);
        console2.log("spgNft:", oldSpgNft);
        console2.log("royaltyPolicy:", oldRoyaltyPolicy);
        console2.log("licensingUrl:", oldLicensingUrl);
        console2.log("expectedSigner:", oldExpectedSigner);
        console2.log("owner:", oldOwner);

        require(caller == oldOwner, "Caller is not the owner");

        // =========================================================================
        // Deploy new Operator with same params but updated V3 deployer
        // =========================================================================

        vm.startBroadcast(deployerPrivateKey);

        Operator newOperator = new Operator(
            Constants.WETH,
            oldIpWorld,
            Constants.V3_DEPLOYER,
            oldSpgNft,
            oldRoyaltyPolicy,
            oldLicensingUrl
        );

        // Set the same expected signer
        newOperator.setExpectedSigner(oldExpectedSigner);

        vm.stopBroadcast();

        // =========================================================================
        // Post-deploy verification
        // =========================================================================

        console2.log("\n=== New Operator Deployed ===");
        console2.log("Address:", address(newOperator));
        console2.log("ipWorld:", address(newOperator.ipWorld()));
        console2.log("spgNft:", newOperator.spgNft());
        console2.log("royaltyPolicy:", newOperator.royaltyPolicy());
        console2.log("licensingUrl:", newOperator.licensingUrl());
        console2.log("expectedSigner:", newOperator.expectedSigner());
        console2.log("owner:", newOperator.owner());
        console2.log("V3_FEE:", newOperator.V3_FEE());

        // Verify all values match
        require(address(newOperator.ipWorld()) == oldIpWorld, "ipWorld mismatch");
        require(newOperator.spgNft() == oldSpgNft, "spgNft mismatch");
        require(newOperator.royaltyPolicy() == oldRoyaltyPolicy, "royaltyPolicy mismatch");
        require(newOperator.expectedSigner() == oldExpectedSigner, "expectedSigner mismatch");
        require(newOperator.owner() == caller, "owner mismatch");

        console2.log("\n=== All Checks Passed ===");
        console2.log("\nNext steps:");
        console2.log("1. Register new operator:  ipWorld.setOperator(newOperator, true)");
        console2.log("2. Grant SPG NFT minter role to new operator");
        console2.log("3. Revoke old operator:    ipWorld.setOperator(oldOperator, false)");
    }
}
