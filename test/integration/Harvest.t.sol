// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IIPWorld} from "../../src/interfaces/IIPWorld.sol";
import {Errors} from "../../src/lib/Errors.sol";

import {BaseTest} from "../BaseTest.sol";
import {MockERC721} from "../mocks/MockERC721.sol";

contract HarvestTest is BaseTest {
    MockERC721 internal mockNft;

    function setUp() public override {
        super.setUp();
        mockNft = new MockERC721();
    }

    function test_Harvest_Unverified() public {
        vm.prank(address(operator));
        (address pool, address tokenAddr) =
            ipWorld.createIpToken(alice, "chill", "CHILL", address(0), startTickList, allocationList);
        swap(IUniswapV3Pool(pool), 1 ether);

        IERC20 token = IERC20(tokenAddr);

        bool isToken0 = tokenAddr < address(weth);
        int24 lTick = isToken0 ? -MAX_TICK : MAX_TICK;
        int24 uTick = isToken0 ? MAX_TICK : -MAX_TICK;
        uint160 lowerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lTick);
        uint160 upperSqrtPriceX96 = TickMath.getSqrtRatioAtTick(uTick);

        // Swaps
        vm.startPrank(alice);
        token.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);

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

        // TODO: received fee calculation automatic after arbitrary amount of swaps
        ipWorld.harvest(tokenAddr);
    }

    function test_Harvest_Verified() public {
        uint256 mintTokenId = 1;
        mockNft.mint(alice, mintTokenId);
        address ipaId = ipAssetRegistry.register(block.chainid, address(mockNft), mintTokenId);

        vm.prank(address(operator));
        ipWorld.claimIp(ipaId, alice);
        vm.prank(address(operator));
        (address pool, address tokenAddr) =
            ipWorld.createIpToken(alice, "chill", "CHILL", ipaId, startTickList, allocationList);
        swap(IUniswapV3Pool(pool), 1 ether);

        IERC20 token = IERC20(tokenAddr);

        bool isToken0 = tokenAddr < address(weth);
        int24 lTick = isToken0 ? -MAX_TICK : MAX_TICK;
        int24 uTick = isToken0 ? MAX_TICK : -MAX_TICK;
        uint160 lowerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(lTick);
        uint160 upperSqrtPriceX96 = TickMath.getSqrtRatioAtTick(uTick);

        // Swaps
        vm.startPrank(alice);
        token.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);

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

        // TODO: received fee calculation automatic after arbitrary amount of swaps
        //        vm.expectEmit(address(ipWorld));
        //        emit IIPWorld.HarvestBaseProtocolFee(alice, 4000000000000001);
        //        vm.expectEmit(address(ipWorld));
        //        emit IIPWorld.HarvestBaseStakersFee(alice, 31999999999999999);
        ipWorld.harvest(tokenAddr);
    }
}
