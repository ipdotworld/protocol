// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPToken} from "../../src/IPToken.sol";
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
        ipToken = new IPToken(address(this), Constants.V3_DEPLOYER, Constants.WETH, 100 ether, "IP Token", "IPT");

        v3Factory = IUniswapV3Factory(Constants.V3_FACTORY);
        liquidityPool = v3Factory.createPool(address(ipToken), Constants.WETH, V3_FEE);
        IUniswapV3Pool(liquidityPool).initialize(TickMath.getSqrtRatioAtTick(0));
    }

    function test_IPToken_Initialized() public {
        assertEq(ipToken.name(), "IP Token");
        assertEq(ipToken.symbol(), "IPT");
        assertEq(ipToken.decimals(), 18);
        assertEq(ipToken.totalSupply(), 1e27);
    }
}
