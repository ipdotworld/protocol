// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPToken} from "../../src/IPToken.sol";
import {Errors} from "../../src/lib/Errors.sol";
import {Constants} from "../../utils/Constants.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract IPTokenTest is Test {
    uint24 public constant V3_FEE = 3000; // 0.3%

    IPToken public ipToken;

    IUniswapV3Factory public v3Factory;

    address public liquidityPool;

    function setUp() public {
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);
        ipToken = new IPToken(address(this), Constants.V3_DEPLOYER, Constants.WETH, 100 ether, 0, "IP Token", "IPT");

        v3Factory = IUniswapV3Factory(Constants.V3_FACTORY);
        liquidityPool = v3Factory.createPool(address(ipToken), Constants.WETH, V3_FEE);
        IUniswapV3Pool(liquidityPool).initialize(TickMath.getSqrtRatioAtTick(0));
    }

    function test_IPToken_Initialized() public {
        assertEq(ipToken.name(), "IP Token");
        assertEq(ipToken.symbol(), "IPT");
        assertEq(ipToken.decimals(), 18);
        assertEq(ipToken.totalSupply(), 1e27);
        assertEq(ipToken.antiSnipeDuration(), 0); // No anti-snipe for this test token
    }

    function test_AntiSnipe_DisabledByDefault() public {
        // Create token with 0 anti-snipe duration (disabled)
        IPToken tokenNoSnipe = new IPToken(
            address(this),
            Constants.V3_DEPLOYER,
            Constants.WETH,
            100 ether,
            0, // No anti-snipe
            "No Snipe Token",
            "NST"
        );

        // First send tokens to liquidity pool
        address poolAddr = tokenNoSnipe.liquidityPool();
        tokenNoSnipe.transfer(poolAddr, 600_000_000 * 1e18);

        // Should be able to transfer any amount from liquidity pool (no anti-snipe)
        vm.prank(poolAddr);
        tokenNoSnipe.transfer(address(1), 500_000_000 * 1e18); // More than MAX_SNIPER_AMOUNT

        assertEq(tokenNoSnipe.balanceOf(address(1)), 500_000_000 * 1e18);
    }

    function test_AntiSnipe_EnabledBlocks() public {
        // Create token with 600 second anti-snipe duration
        IPToken tokenWithSnipe = new IPToken(
            address(this),
            Constants.V3_DEPLOYER,
            Constants.WETH,
            100 ether,
            600, // 10 minute anti-snipe
            "Snipe Protected Token",
            "SPT"
        );

        // First send tokens to liquidity pool
        address poolAddr = tokenWithSnipe.liquidityPool();
        tokenWithSnipe.transfer(poolAddr, 600_000_000 * 1e18);

        // Should revert when trying to transfer more than MAX_SNIPER_AMOUNT from liquidity pool
        vm.prank(poolAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.IPToken_ExceedsAntiSnipeLimit.selector));
        tokenWithSnipe.transfer(address(1), 500_000_000 * 1e18); // More than MAX_SNIPER_AMOUNT

        // Should allow transfers up to MAX_SNIPER_AMOUNT
        vm.prank(poolAddr);
        tokenWithSnipe.transfer(address(1), 300_000_000 * 1e18); // Exactly MAX_SNIPER_AMOUNT
        assertEq(tokenWithSnipe.balanceOf(address(1)), 300_000_000 * 1e18);
    }

    function test_AntiSnipe_ExpiresAfterDuration() public {
        // Create token with 1 second anti-snipe duration for quick testing
        IPToken tokenWithSnipe = new IPToken(
            address(this),
            Constants.V3_DEPLOYER,
            Constants.WETH,
            100 ether,
            1, // 1 second anti-snipe
            "Short Snipe Token",
            "SST"
        );

        // First send tokens to liquidity pool
        address poolAddr = tokenWithSnipe.liquidityPool();
        tokenWithSnipe.transfer(poolAddr, 600_000_000 * 1e18);

        // Should revert initially
        vm.prank(poolAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.IPToken_ExceedsAntiSnipeLimit.selector));
        tokenWithSnipe.transfer(address(1), 500_000_000 * 1e18);

        // Wait 2 seconds
        vm.warp(block.timestamp + 2);

        // Should work after expiration
        vm.prank(poolAddr);
        tokenWithSnipe.transfer(address(1), 500_000_000 * 1e18);
        assertEq(tokenWithSnipe.balanceOf(address(1)), 500_000_000 * 1e18);
    }

    function test_AntiSnipe_OnlyAppliesToLiquidityPool() public {
        // Create token with anti-snipe enabled
        IPToken tokenWithSnipe = new IPToken(
            address(this),
            Constants.V3_DEPLOYER,
            Constants.WETH,
            100 ether,
            600, // 10 minute anti-snipe
            "Snipe Protected Token",
            "SPT"
        );

        // Regular transfers should not be affected
        tokenWithSnipe.transfer(address(1), 500_000_000 * 1e18); // More than MAX_SNIPER_AMOUNT
        assertEq(tokenWithSnipe.balanceOf(address(1)), 500_000_000 * 1e18);

        // TransferFrom should also work normally for non-pool addresses
        tokenWithSnipe.approve(address(2), 100_000_000 * 1e18);
        vm.prank(address(2));
        tokenWithSnipe.transferFrom(address(this), address(3), 100_000_000 * 1e18);
        assertEq(tokenWithSnipe.balanceOf(address(3)), 100_000_000 * 1e18);
    }

    function test_AntiSnipe_TransferFromBlocked() public {
        // Create token with anti-snipe enabled
        IPToken tokenWithSnipe = new IPToken(
            address(this),
            Constants.V3_DEPLOYER,
            Constants.WETH,
            100 ether,
            600, // 10 minute anti-snipe
            "Snipe Protected Token",
            "SPT"
        );

        address poolAddr = tokenWithSnipe.liquidityPool();

        // First send tokens to liquidity pool
        tokenWithSnipe.transfer(poolAddr, 600_000_000 * 1e18);

        // Approve this contract to spend pool's tokens
        vm.prank(poolAddr);
        tokenWithSnipe.approve(address(this), 600_000_000 * 1e18);

        // transferFrom from liquidity pool should also be blocked
        vm.expectRevert(abi.encodeWithSelector(Errors.IPToken_ExceedsAntiSnipeLimit.selector));
        tokenWithSnipe.transferFrom(poolAddr, address(1), 500_000_000 * 1e18);

        // But smaller amounts should work
        tokenWithSnipe.transferFrom(poolAddr, address(1), 300_000_000 * 1e18);
        assertEq(tokenWithSnipe.balanceOf(address(1)), 300_000_000 * 1e18);
    }

    function test_AntiSnipe_TokenCreatorExemption() public {
        // Create token with anti-snipe enabled, this contract is the creator
        IPToken tokenWithSnipe = new IPToken(
            address(this), // This contract is the creator
            Constants.V3_DEPLOYER,
            Constants.WETH,
            100 ether,
            600, // 10 minute anti-snipe
            "Creator Exempt Token",
            "CET"
        );

        address poolAddr = tokenWithSnipe.liquidityPool();

        // First send tokens to liquidity pool
        tokenWithSnipe.transfer(poolAddr, 900_000_000 * 1e18);

        // Token creator should be able to buy any amount during anti-snipe period
        vm.prank(poolAddr);
        tokenWithSnipe.transfer(address(this), 800_000_000 * 1e18); // Way more than MAX_SNIPER_AMOUNT
        assertEq(tokenWithSnipe.balanceOf(address(this)), 900_000_000 * 1e18); // 100M original + 800M bought

        // But other addresses should still be blocked
        vm.prank(poolAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.IPToken_ExceedsAntiSnipeLimit.selector));
        tokenWithSnipe.transfer(address(1), 500_000_000 * 1e18);
    }

    function test_AntiSnipe_CreatorExemptionTransferFrom() public {
        // Create token with different creator address
        address creator = makeAddr("creator");
        IPToken tokenWithSnipe = new IPToken(
            creator, // Different creator
            Constants.V3_DEPLOYER,
            Constants.WETH,
            100 ether,
            600, // 10 minute anti-snipe
            "Creator Different Token",
            "CDT"
        );

        address poolAddr = tokenWithSnipe.liquidityPool();

        // First send tokens to liquidity pool
        tokenWithSnipe.transfer(poolAddr, 900_000_000 * 1e18);

        // Approve this contract to spend pool's tokens
        vm.prank(poolAddr);
        tokenWithSnipe.approve(address(this), 900_000_000 * 1e18);

        // Creator should be able to buy any amount via transferFrom
        tokenWithSnipe.transferFrom(poolAddr, creator, 800_000_000 * 1e18);
        assertEq(tokenWithSnipe.balanceOf(creator), 800_000_000 * 1e18);

        // But other addresses should still be blocked (need to approve more first)
        vm.prank(poolAddr);
        tokenWithSnipe.approve(address(this), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Errors.IPToken_ExceedsAntiSnipeLimit.selector));
        tokenWithSnipe.transferFrom(poolAddr, address(1), 500_000_000 * 1e18);
    }
}
