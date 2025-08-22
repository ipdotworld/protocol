// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {Errors} from "../../src/lib/Errors.sol";
import {BaseTest} from "../BaseTest.sol";
import {Operator} from "../../src/Operator.sol";

contract OldIPAssetTest is BaseTest {
    uint256 internal signerPk = 0xa11ce;
    address internal signer = vm.addr(signerPk);

    // Old IP Asset from Story mainnet
    address internal constant OLD_IPA = 0xB1D831271A68Db5c18c8F0B69327446f7C8D0A42;

    function setUp() public override {
        super.setUp();

        // Set expected signer for operator
        operator.setExpectedSigner(signer);
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
                        "CREATE(address creator,int24[] startTick,uint256[] allocationList,uint256 nonce,uint256 deadline)"
                    ),
                    alice,
                    keccak256(abi.encodePacked(startTickList)),
                    keccak256(abi.encodePacked(allocationList)),
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        vm.prank(alice);
        (address pool, address token) = operator.createIpTokenWithSig{value: 1 ether}(
            "OldIP Token", "OLDIP", OLD_IPA, startTickList, allocationList, block.timestamp + 1000, sig
        );

        // Verify token was created
        assert(token != address(0));
        assert(pool != address(0));

        // Check if token is linked to the old IPA
        (address linkedIpaId,) = ipWorld.tokenInfo(token);
        assertEq(linkedIpaId, OLD_IPA, "Token should be linked to old IPA");

        console.log("Created token:", token);
        console.log("Created pool:", pool);
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

        console.log("Link token test completed successfully - token linked to IPA");
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

        console.log("Direct claim test completed successfully - IP claimed by:", recipient);
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
                        "CREATE(address creator,int24[] startTick,uint256[] allocationList,uint256 nonce,uint256 deadline)"
                    ),
                    alice,
                    keccak256(abi.encodePacked(startTickList)),
                    keccak256(abi.encodePacked(allocationList)),
                    operator.nonces(alice),
                    block.timestamp + 1000
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        Operator.Signature memory sig = Operator.Signature(v, r, s);

        vm.prank(alice);
        (address pool, address tokenAddr) = operator.createIpTokenWithSig{value: 1 ether}(
            "OldIP Token", "OLDIP", OLD_IPA, startTickList, allocationList, block.timestamp + 1000, sig
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

        console.log("Harvest success:", successes[0]);
        console.log("Harvest result:", results[0]);
        console.log("Token address:", tokenAddr);
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
            ipWorld.createIpToken(alice, "Direct Harvest Test", "DHT", OLD_IPA, startTickList, allocationList);

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

        console.log("Direct harvest completed successfully for token:", tokenAddr);
    }
}
