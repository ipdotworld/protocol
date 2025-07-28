// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPWorldRoyaltyPolicy} from "../../src/IPWorldRoyaltyPolicy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RoyaltyModule} from "@storyprotocol/core/modules/royalty/RoyaltyModule.sol";
import {ILicensingModule} from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";
import {IPILicenseTemplate, PILTerms} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {IIPAssetRegistry} from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {Constants} from "../../utils/Constants.sol";

contract IPWorldRoyaltyPolicyTest is Test {
    function testRoyaltyPolicyAeneidFlow() public {
        // Fork Aeneid testnet
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);

        // Mock the custom precompile's getParentIpsCount function to return 0
        vm.mockCall(
            0x0000000000000000000000000000000000000101,
            abi.encodeWithSignature("getParentIpsCount(address)"),
            abi.encode(0)
        );

        vm.mockCall(
            0x0000000000000000000000000000000000000101,
            abi.encodeWithSignature("getParentIpsCountExt(address)"),
            abi.encode(0)
        );

        // Mock the custom precompile's getParentIps function to return an empty array
        vm.mockCall(
            0x0000000000000000000000000000000000000101,
            abi.encodeWithSignature("getParentIps(address,uint256,uint256)"),
            abi.encode(new address[](0))
        );

        // Mock the custom precompile's getAncestorIpsCount function to return 0
        vm.mockCall(
            0x0000000000000000000000000000000000000101,
            abi.encodeWithSignature("getAncestorIpsCount(address)"),
            abi.encode(0)
        );

        vm.mockCall(
            0x0000000000000000000000000000000000000101,
            abi.encodeWithSignature("getAncestorIpsCountExt(address)"),
            abi.encode(0)
        );

        // Mock the custom precompile's getAncestorIps function to return an empty array
        vm.mockCall(
            0x0000000000000000000000000000000000000101,
            abi.encodeWithSignature("getAncestorIps(address,uint256,uint256)"),
            abi.encode(new address[](0))
        );

        address testUser = address(0x1234);
        vm.startPrank(testUser);
        vm.deal(testUser, 100 ether);

        // Deploy a dummy mock NFT
        MockERC721 mockNFT = new MockERC721();
        // Mint tokenId 1 for parent IP, tokenId 2 for derivative IP
        mockNFT.mint(testUser, 1);
        mockNFT.mint(testUser, 2);

        // 1. Deploy upgradeable IPWorldRoyaltyPolicy
        IPWorldRoyaltyPolicy logic = new IPWorldRoyaltyPolicy();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(logic), abi.encodeWithSelector(IPWorldRoyaltyPolicy.initialize.selector));
        vm.makePersistent(address(proxy));
        IPWorldRoyaltyPolicy policy = IPWorldRoyaltyPolicy(address(proxy));

        // 2. Register as external royalty policy on RoyaltyModule
        RoyaltyModule(Constants.ROYALTY_MODULE).registerExternalRoyaltyPolicy(address(policy));

        // 3. Register PIL terms with commercialUse=true and royaltyPolicy=policy
        PILTerms memory pilTerms = PILTerms({
            transferable: true,
            royaltyPolicy: address(policy),
            defaultMintingFee: 0,
            expiration: 0,
            commercialUse: true,
            commercialAttribution: true,
            commercializerChecker: address(0),
            commercializerCheckerData: "",
            commercialRevShare: 0,
            commercialRevCeiling: 0,
            derivativesAllowed: true,
            derivativesAttribution: true,
            derivativesApproval: false,
            derivativesReciprocal: true,
            derivativeRevCeiling: 0,
            currency: Constants.WETH,
            uri: ""
        });

        uint256 pilTermsId = IPILicenseTemplate(Constants.PILICENSE_TEMPLATE).registerLicenseTerms(pilTerms);

        // 4. Register parent IP using mockNFT
        address parentIpId = IIPAssetRegistry(Constants.IP_ASSET_REGISTRY).register(block.chainid, address(mockNFT), 1);

        // 5. Attach PIL terms to parent IP
        ILicensingModule(Constants.LICENSING_MODULE).attachLicenseTerms(
            parentIpId, Constants.PILICENSE_TEMPLATE, pilTermsId
        );

        // 6. Mint license token for parent IP
        uint256 licenseTokenId = ILicensingModule(Constants.LICENSING_MODULE).mintLicenseTokens(
            parentIpId,
            Constants.PILICENSE_TEMPLATE,
            pilTermsId,
            1, // amount
            testUser, // receiver
            "", // royaltyContext
            0, // maxMintingFee
            0 // maxRevenueShare
        );

        // 7. Register derivative IP using mockNFT
        address derivativeIpId =
            IIPAssetRegistry(Constants.IP_ASSET_REGISTRY).register(block.chainid, address(mockNFT), 2);

        // 8. Register derivative using license token
        uint256[] memory licenseTokenIds = new uint256[](1);
        licenseTokenIds[0] = licenseTokenId;

        ILicensingModule(Constants.LICENSING_MODULE).registerDerivativeWithLicenseTokens(
            derivativeIpId,
            licenseTokenIds,
            "", // royaltyContext
            0 // maxRts
        );

        // Assert that the policy address is nonzero and registered
        assertTrue(address(policy) != address(0));
        assertTrue(RoyaltyModule(Constants.ROYALTY_MODULE).isRegisteredExternalRoyaltyPolicy(address(policy)));

        // Assert that PIL terms were registered successfully
        assertTrue(pilTermsId > 0);

        // Assert that IPs were registered successfully
        assertTrue(IIPAssetRegistry(Constants.IP_ASSET_REGISTRY).isRegistered(parentIpId));
        assertTrue(IIPAssetRegistry(Constants.IP_ASSET_REGISTRY).isRegistered(derivativeIpId));

        // Assert that license token was minted successfully
        assertTrue(licenseTokenId > 0);

        vm.stopPrank();
    }
}
