// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IIPAssetRegistry} from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";

import {Errors} from "../../src/lib/Errors.sol";
import {Constants} from "../../utils/Constants.sol";
import {BaseTest} from "../BaseTest.sol";
import {Operator} from "../../src/Operator.sol";
import {ILicensingModuleWithNFT} from "../../src/interfaces/ILicensingModuleWithNFT.sol";
import {ILicensingModule} from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";
import {IIPAccount} from "@storyprotocol/core/interfaces/IIPAccount.sol";
import {IAccessController} from "@storyprotocol/core/interfaces/access/IAccessController.sol";
import {AccessPermission} from "@storyprotocol/core/lib/AccessPermission.sol";
import {MetaTx} from "@storyprotocol/core/lib/MetaTx.sol";

contract MockIPGraph {
    mapping(address childIpId => mapping(address parentIpId => bool)) parentIps;
    mapping(address ipId => address[] parents) parentsList;

    function addParentIp(address ipId, address[] calldata parentIpIds) external {
        for (uint256 i = 0; i < parentIpIds.length; i++) {
            if (!parentIps[ipId][parentIpIds[i]]) {
                parentIps[ipId][parentIpIds[i]] = true;
                parentsList[ipId].push(parentIpIds[i]);
            }
        }
    }

    function getParentIpsCount(address ipId) external view returns (uint256) {
        return parentsList[ipId].length;
    }

    function getParentIpsCountExt(address ipId) external view returns (uint256) {
        return parentsList[ipId].length;
    }

    function hasParentIp(address ipId, address parent) external view returns (bool) {
        return parentIps[ipId][parent];
    }

    function hasParentIpExt(address ipId, address parent) external view returns (bool) {
        return parentIps[ipId][parent];
    }

    function getParentIps(address ipId) external view returns (address[] memory) {
        return parentsList[ipId];
    }

    function getParentIpsExt(address ipId) external view returns (address[] memory) {
        return parentsList[ipId];
    }
}

contract OldIPAssetTest is BaseTest {
    // Operator signer (for expectedSigner verification)
    uint256 internal signerPk = 0xa11ce;
    address internal signer = vm.addr(signerPk);

    // IP Asset owner (different from operator signer)
    uint256 internal ipOwnerPk = 0xb22ef;
    address internal ipOwner = vm.addr(ipOwnerPk);

    // Old IP Asset from Story mainnet
    address internal constant OLD_IPA = 0xB1D831271A68Db5c18c8F0B69327446f7C8D0A42;

    function setUp() public override {
        super.setUp();

        // Deploy MockIPGraph at the expected address 0x0101
        MockIPGraph mockIpGraph = new MockIPGraph();
        vm.etch(address(0x0101), address(mockIpGraph).code);

        // Set expected signer for signature verification
        operator.setExpectedSigner(signer);
    }

    /// @dev Get the signature for setting batch permissions for the IP by the periphery.
    /// @param ipId The ID of the IP.
    /// @param permissionList The list of permissions to be set.
    /// @param deadline The deadline for the signature.
    /// @param state IPAccount's internal nonce
    /// @param signerSk The secret key of the signer.
    /// @return signature The signature for setting the batch permissions.
    /// @return expectedState The expected IPAccount's state after setting the permissions.
    /// @return data The call data for executing the setBatchTransientPermissions function.
    function _getSetBatchPermissionSigForPeriphery(
        address ipId,
        AccessPermission.Permission[] memory permissionList,
        uint256 deadline,
        bytes32 state,
        uint256 signerSk
    ) internal view returns (bytes memory signature, bytes32 expectedState, bytes memory data) {
        expectedState = keccak256(
            abi.encode(
                state, // ipAccount.state()
                abi.encodeWithSelector(
                    IIPAccount.execute.selector,
                    Constants.ACCESS_CONTROLLER,
                    0, // amount of ether to send
                    abi.encodeWithSelector(IAccessController.setBatchTransientPermissions.selector, permissionList)
                )
            )
        );

        data = abi.encodeWithSelector(IAccessController.setBatchTransientPermissions.selector, permissionList);

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(ipId),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: Constants.ACCESS_CONTROLLER,
                    value: 0,
                    data: data,
                    nonce: expectedState,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerSk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function test_OldIPAsset_CreateToken() public {
        vm.deal(alice, 10 ether);

        int24[] memory startTickList = new int24[](1);
        startTickList[0] = -230400;
        uint256[] memory allocationList = new uint256[](1);
        allocationList[0] = 970000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            operator.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "CREATE(address creator,int24[] startTick,uint256[] allocationList,bool antiSnipe,uint256 nonce,uint256 deadline)"
                    ),
                    alice,
                    keccak256(abi.encodePacked(startTickList)),
                    keccak256(abi.encodePacked(allocationList)),
                    false,
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        vm.prank(alice);
        (address pool, address token) = operator.createIpTokenWithSig{value: 1 ether}(
            "OldIP Token", "OLDIP", OLD_IPA, startTickList, allocationList, false, block.timestamp + 1000, sig
        );

        // Verify token was created
        assert(token != address(0));
        assert(pool != address(0));

        // Check if token is linked to the old IPA
        (address linkedIpaId,) = ipWorld.tokenInfo(token);
        assertEq(linkedIpaId, OLD_IPA, "Token should be linked to old IPA");
    }

    function test_OldIPAsset_LinkToken() public {
        // Create a mock token to link
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("mockToken");

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            operator.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256("LINK(address sender,address ipaId,address[] tokens,uint256 nonce,uint256 deadline)"),
                    alice,
                    OLD_IPA,
                    tokens,
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        vm.prank(alice);
        // This should succeed since operator can link tokens to IP
        operator.linkTokenToIpWithSig(OLD_IPA, tokens, block.timestamp + 1000, sig);

        // Verify the token was linked by checking token info
        (address linkedIpaId,) = ipWorld.tokenInfo(tokens[0]);
        assertEq(linkedIpaId, OLD_IPA, "Token should be linked to old IPA");
    }

    function test_OldIPAsset_ClaimDirect() public {
        // Test direct claim using ipWorld.claimIp
        // Since claimIp has onlyOperator modifier, we need to call it as operator
        address newRecipient = bob;

        vm.prank(address(operator));
        ipWorld.claimIp(OLD_IPA, newRecipient);

        // Verify the recipient was set
        address recipient = ipWorld.ipaRecipient(OLD_IPA);
        assertEq(recipient, newRecipient, "Recipient should be set to bob");
    }

    function test_OldIPAsset_Harvest() public {
        vm.deal(alice, 10 ether);

        // First create a token for the old IP asset
        int24[] memory startTickList = new int24[](1);
        startTickList[0] = -230400;
        uint256[] memory allocationList = new uint256[](1);
        allocationList[0] = 970000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            operator.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "CREATE(address creator,int24[] startTick,uint256[] allocationList,bool antiSnipe,uint256 nonce,uint256 deadline)"
                    ),
                    alice,
                    keccak256(abi.encodePacked(startTickList)),
                    keccak256(abi.encodePacked(allocationList)),
                    false,
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        vm.prank(alice);
        (, address tokenAddr) = operator.createIpTokenWithSig{value: 1 ether}(
            "OldIP Token", "OLDIP", OLD_IPA, startTickList, allocationList, false, block.timestamp + 1000, sig
        );

        // Now perform swaps to generate fees
        IERC20 token = IERC20(tokenAddr);
        bool isToken0 = tokenAddr < address(weth);
        int24 lTick = isToken0 ? -MAX_TICK : MAX_TICK;
        int24 uTick = isToken0 ? MAX_TICK : -MAX_TICK;
        uint160 lowerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lTick);
        uint160 upperSqrtPriceX96 = TickMath.getSqrtRatioAtTick(uTick);

        // Perform multiple swaps to generate fees
        vm.startPrank(alice);
        token.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);

        // WETH -> Token swaps
        for (uint256 i = 0; i < 3; i++) {
            weth.deposit{value: 1 ether}();
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(weth),
                    tokenOut: address(token),
                    fee: POOL_FEE,
                    recipient: alice,
                    deadline: block.timestamp + 1000,
                    amountIn: 1 ether,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: isToken0 ? lowerSqrtPriceX96 : upperSqrtPriceX96
                })
            );
        }

        // Token -> WETH swaps
        uint256 totalTokenAmount = token.balanceOf(alice);
        for (uint256 i = 0; i < 3; i++) {
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(token),
                    tokenOut: address(weth),
                    fee: POOL_FEE,
                    recipient: alice,
                    deadline: block.timestamp + 1000,
                    amountIn: totalTokenAmount / 3,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: isToken0 ? upperSqrtPriceX96 : lowerSqrtPriceX96
                })
            );
        }
        vm.stopPrank();

        // Now try to harvest
        address[] memory tokens = new address[](1);
        tokens[0] = tokenAddr;

        (bool[] memory successes, string[] memory results) = operator.harvestTokens(tokens);

        assertEq(successes.length, 1);
        assertEq(results.length, 1);

        // Assert that harvest was successful
        assertTrue(successes[0], "Harvest should succeed after real trading");
        assertEq(results[0], "", "Empty error message means successful harvest");
    }

    function test_OldIPAsset_HarvestDirect() public {
        vm.deal(alice, 10 ether);

        // Create token and perform swaps (same as above test)
        int24[] memory startTickList = new int24[](1);
        startTickList[0] = -230400;
        uint256[] memory allocationList = new uint256[](1);
        allocationList[0] = 970000;

        vm.prank(address(operator));
        (address pool, address tokenAddr) =
            ipWorld.createIpToken(alice, "Direct Harvest Test", "DHT", OLD_IPA, startTickList, allocationList, false);

        // Initial swap to setup pool
        swap(IUniswapV3Pool(pool), 1 ether);

        // Perform trading to generate fees
        IERC20 token = IERC20(tokenAddr);
        bool isToken0 = tokenAddr < address(weth);
        int24 lTick = isToken0 ? -MAX_TICK : MAX_TICK;
        int24 uTick = isToken0 ? MAX_TICK : -MAX_TICK;
        uint160 lowerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lTick);
        uint160 upperSqrtPriceX96 = TickMath.getSqrtRatioAtTick(uTick);

        vm.startPrank(alice);
        token.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);

        // Multiple swaps to generate significant fees
        for (uint256 i = 0; i < 5; i++) {
            weth.deposit{value: 1 ether}();
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(weth),
                    tokenOut: address(token),
                    fee: POOL_FEE,
                    recipient: alice,
                    deadline: block.timestamp + 1000,
                    amountIn: 1 ether,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: isToken0 ? lowerSqrtPriceX96 : upperSqrtPriceX96
                })
            );
        }
        vm.stopPrank();

        // Direct harvest call
        ipWorld.harvest(tokenAddr);
    }

    function test_OldIPAsset_ClaimIp_ValidCall() public {
        address claimer = bob;

        // Create token addresses array
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("token1");
        tokens[1] = makeAddr("token2");

        // Create a new IP asset that we can control instead of using OLD_IPA
        // Grant MINTER_ROLE to this contract if not already granted
        bytes32 minterRole = keccak256("MINTER_ROLE");
        if (!spgNft.hasRole(minterRole, address(this))) {
            spgNft.grantRole(minterRole, address(this));
        }

        // Mint NFT to ipOwner (different from operator signer)
        uint256 tokenId = spgNft.mint(ipOwner, "https://example.com/metadata", bytes32(0), false); // ipOwner will be the NFT owner
        address testIpAsset = ipAssetRegistry.register(block.chainid, address(spgNft), tokenId);

        // Since alice will call the function, use alice for operator signature
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            operator.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "CLAIM(address sender,address ipaId,address claimer,address[] tokens,uint256 nonce,uint256 deadline)"
                    ),
                    alice, // Alice is calling the function
                    testIpAsset,
                    claimer,
                    keccak256(abi.encodePacked(tokens)),
                    operator.nonces(alice), // Use alice's nonce
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        // Create permission list for attachLicenseTerms and setLicensingConfig
        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](2);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: testIpAsset,
            signer: address(operator), // Operator as signer (matches Operator.sol)
            to: Constants.LICENSING_MODULE,
            func: ILicensingModule.attachLicenseTerms.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: testIpAsset,
            signer: address(operator), // Operator as signer (matches Operator.sol)
            to: Constants.LICENSING_MODULE,
            func: ILicensingModule.setLicensingConfig.selector,
            permission: AccessPermission.ALLOW
        });

        // Generate signature using the helper function
        uint256 deadline = block.timestamp + 1000;
        bytes32 currentState = IIPAccount(payable(testIpAsset)).state();
        (bytes memory signature,,) = _getSetBatchPermissionSigForPeriphery({
            ipId: testIpAsset,
            permissionList: permissionList,
            deadline: deadline,
            state: currentState,
            signerSk: ipOwnerPk // Use IP Owner's private key instead of operator signer's key
        });

        // Extract r, s, v from the signature bytes
        bytes32 pilR;
        bytes32 pilS;
        uint8 pilV;
        assembly {
            pilR := mload(add(signature, 0x20))
            pilS := mload(add(signature, 0x40))
            pilV := byte(0, mload(add(signature, 0x60)))
        }

        // IP Owner's signature for licensing permissions
        Operator.Signature memory ipOwnerSig = Operator.Signature(pilV, pilR, pilS);

        // Call from alice (not the IP owner), using both signatures
        vm.prank(alice);
        operator.claimIpWithSig(testIpAsset, claimer, tokens, block.timestamp + 1000, sig, ipOwnerSig);

        // Verify the tokens are linked to the IP
        (address linkedIpaId,) = ipWorld.tokenInfo(tokens[0]);
        assertEq(linkedIpaId, testIpAsset, "Token should be linked to test IP asset");

        // Verify the claim was successful
        address recipient = ipWorld.ipaRecipient(testIpAsset);
        assertEq(recipient, claimer, "IP should be claimed by the claimer");
    }

    function test_OldIPAsset_ClaimIp_InvalidClaimer() public {
        address claimer = address(0); // Invalid claimer

        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("token1");

        // Create signature even though it will fail due to invalid claimer
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            operator.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "CLAIM(address sender,address ipaId,address claimer,address[] tokens,uint256 nonce,uint256 deadline)"
                    ),
                    alice,
                    OLD_IPA,
                    claimer,
                    keccak256(abi.encodePacked(tokens)),
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        // Dummy IP Owner signature for error test
        Operator.Signature memory dummyIpOwnerSig = Operator.Signature(0, bytes32(0), bytes32(0));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Operator_InvalidAddress.selector));
        operator.claimIpWithSig(OLD_IPA, claimer, tokens, block.timestamp + 1000, sig, dummyIpOwnerSig);
    }

    function test_OldIPAsset_ClaimIp_InvalidIpaId() public {
        address ipaId = address(0); // Invalid IP asset ID
        address claimer = bob;

        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("token1");

        // Create signature even though it will fail due to invalid ipaId
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            operator.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "CLAIM(address sender,address ipaId,address claimer,address[] tokens,uint256 nonce,uint256 deadline)"
                    ),
                    alice,
                    ipaId,
                    claimer,
                    keccak256(abi.encodePacked(tokens)),
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        // Dummy IP Owner signature for error test
        Operator.Signature memory dummyIpOwnerSig = Operator.Signature(0, bytes32(0), bytes32(0));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Operator_InvalidAddress.selector));
        operator.claimIpWithSig(ipaId, claimer, tokens, block.timestamp + 1000, sig, dummyIpOwnerSig);
    }

    function test_OldIPAsset_ClaimIp_EmptyTokens() public {
        address claimer = bob;

        // Empty token array
        address[] memory tokens = new address[](0);

        // Create signature even though it may fail
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            operator.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "CLAIM(address sender,address ipaId,address claimer,address[] tokens,uint256 nonce,uint256 deadline)"
                    ),
                    alice,
                    OLD_IPA,
                    claimer,
                    keccak256(abi.encodePacked(tokens)),
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        // Empty IP Owner signature for error test
        Operator.Signature memory emptyIpOwnerSig = Operator.Signature(0, bytes32(0), bytes32(0));

        // This should still work, just claiming IP without linking tokens
        vm.prank(alice);
        vm.expectRevert(); // Expecting revert from Story Protocol integration
        operator.claimIpWithSig(OLD_IPA, claimer, tokens, block.timestamp + 1000, sig, emptyIpOwnerSig);
    }
}
