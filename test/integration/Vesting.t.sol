// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Errors} from "../../src/lib/Errors.sol";
import {IPToken} from "../../src/IPToken.sol";
import {IIPOwnerVault, IPOwnerVault} from "../../src/IPOwnerVault.sol";

import {BaseTest} from "../BaseTest.sol";
import {MockERC721} from "../mocks/MockERC721.sol";

contract VestingTest is BaseTest {
    MockERC721 internal mockNft;

    function setUp() public override {
        super.setUp();
        mockNft = new MockERC721();
    }

    function test_Vesting_CreatedUnverified() public {
        vm.prank(address(operator));
        (address pool, address tokenAddr) =
            ipWorld.createIpToken(address(this), "chill", "CHILL", address(0), startTickList, allocationList, false);
        swap(IUniswapV3Pool(pool), 1 ether);

        assertApproxEqAbs(
            IERC20(tokenAddr).balanceOf(address(ownerVault)),
            IERC20(tokenAddr).totalSupply() * (ipWorld.PRECISION() - allocationList[0] - allocationList[1])
                / ipWorld.PRECISION(),
            1 gwei
        );
    }

    function test_Vesting_CreatedVerified() public {
        uint256 mintTokenId = 1;
        mockNft.mint(alice, mintTokenId);
        address ipaId = ipAssetRegistry.register(block.chainid, address(mockNft), mintTokenId);

        vm.startPrank(address(operator));
        ipWorld.claimIp(ipaId, alice);
        assertEq(ipWorld.ipaRecipient(ipaId), address(alice));
        (address pool, address tokenAddr) =
            ipWorld.createIpToken(address(this), "chill", "CHILL", ipaId, startTickList, allocationList, false);
        vm.stopPrank();

        swap(IUniswapV3Pool(pool), 1 ether);

        // Check balances before harvest to verify harvest actually works
        uint256 treasuryBefore = address(treasury).balance;

        ipWorld.harvest(tokenAddr);

        // Verify harvest collected fees
        assertTrue(address(treasury).balance > treasuryBefore, "No ETH was sent to treasury");

        IIPOwnerVault.VestingData memory vestingData = ownerVault.vesting(tokenAddr);
        assertTrue(vestingData.isSet);

        uint256 duration = ownerVault.vestingDuration();
        assertEq(vestingData.start, block.timestamp);
        assertEq(vestingData.end, block.timestamp + duration);
        assertEq(ownerVault.released(tokenAddr), 0);

        uint256 remaining = ownerVault.remaining(tokenAddr);
        uint256 released = 0;

        uint64 warpTime = 1000;
        vm.warp(block.timestamp + warpTime);

        uint256 expectedVestedAmount = (ownerVault.remaining(tokenAddr) * warpTime) / duration;
        assertEq(ownerVault.vestedAmount(tokenAddr, uint64(block.timestamp)), expectedVestedAmount);
        assertEq(ownerVault.remaining(tokenAddr), remaining);
        assertEq(ownerVault.releasable(tokenAddr), expectedVestedAmount);

        vm.expectEmit(address(ownerVault));
        emit IIPOwnerVault.ReleasedVested(tokenAddr, expectedVestedAmount);
        ownerVault.claim(tokenAddr);

        remaining -= expectedVestedAmount;
        released += expectedVestedAmount;
        assertEq(IERC20(tokenAddr).balanceOf(alice), released, "1");

        assertEq(ownerVault.vestedAmount(tokenAddr, uint64(block.timestamp)), expectedVestedAmount);
        assertEq(ownerVault.remaining(tokenAddr), remaining);
        assertEq(ownerVault.releasable(tokenAddr), 0);
    }

    function test_Vesting_CreateUnverifiedThenVerify() public {}

    function test_Vesting_CreatedWithZeroWETH() public {
        uint256 mintTokenId = 1;
        mockNft.mint(alice, mintTokenId);
        address ipaId = ipAssetRegistry.register(block.chainid, address(mockNft), mintTokenId);

        vm.startPrank(address(operator));
        ipWorld.claimIp(ipaId, alice);
        assertEq(ipWorld.ipaRecipient(ipaId), address(alice));
        (, address tokenAddr) =
            ipWorld.createIpToken(address(this), "chill", "CHILL", ipaId, startTickList, allocationList, false);
        vm.stopPrank();

        // Harvest immediately without any swaps - no fees should have accrued
        ipWorld.harvest(tokenAddr);

        // Vesting should still be created even with zero fees
        IIPOwnerVault.VestingData memory vestingData = ownerVault.vesting(tokenAddr);
        assertTrue(vestingData.isSet, "Vesting should be created even with zero WETH");
        assertEq(vestingData.start, block.timestamp);
        assertEq(vestingData.end, block.timestamp + ownerVault.vestingDuration());
    }
}
