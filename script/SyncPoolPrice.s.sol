// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {Constants} from "../utils/Constants.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";

/// @title PoolPriceSyncer
/// @notice Helper contract that calls pool.mint()/swap()/burn() directly
/// @dev Implements both MintCallback and SwapCallback
contract PoolPriceSyncer {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @notice Sync 1% pool price to match 0.3% pool
    function syncPrice(
        IUniswapV3Pool newPool,
        uint160 targetSqrtPriceX96,
        int24 tickLower,
        int24 tickUpper
    ) external onlyOwner {
        address token0 = newPool.token0();
        address token1 = newPool.token1();

        // Step 1: Mint minimal liquidity directly on pool
        uint128 liquidityAmount = 1000; // small but enough to enable swap
        newPool.mint(address(this), tickLower, tickUpper, liquidityAmount, abi.encode(token0, token1));

        console2.log("  Step 1: Minted liquidity:", liquidityAmount);

        // Step 2: Swap to target price
        (uint160 currentPrice,,,,,, ) = newPool.slot0();
        if (currentPrice != targetSqrtPriceX96) {
            bool zeroForOne = currentPrice > targetSqrtPriceX96;
            // swap with minimum amount, sqrtPriceLimitX96 will stop at target
            newPool.swap(
                address(this),
                zeroForOne,
                1e18, // large enough amountSpecified to ensure we reach target
                targetSqrtPriceX96,
                ""
            );
            console2.log("  Step 2: Swapped to target price");
        }

        // Step 3: Burn and collect
        newPool.burn(tickLower, tickUpper, liquidityAmount);
        newPool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
        console2.log("  Step 3: Burned liquidity and collected");
    }

    /// @notice StoryHunt V3 mint callback - transfer required tokens to pool
    function storyHuntV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        (address token0, address token1) = abi.decode(data, (address, address));
        if (amount0Owed > 0) IERC20(token0).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) IERC20(token1).transfer(msg.sender, amount1Owed);
    }

    /// @notice StoryHunt V3 swap callback - transfer required tokens to pool
    function storyHuntV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        if (amount0Delta > 0) {
            IERC20(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            IERC20(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    /// @notice Withdraw tokens back to owner
    function withdraw(address token) external onlyOwner {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) IERC20(token).transfer(owner, bal);
    }

    /// @notice Withdraw native token
    function withdrawNative() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal > 0) payable(owner).transfer(bal);
    }

    receive() external payable {}
}

/// @title SyncPoolPrice
/// @notice Deploys helper, syncs 1% pool price to 0.3% pool, then cleans up
contract SyncPoolPrice is Script {
    uint24 internal constant V3_FEE_HIGH = 10_000;
    uint24 internal constant V3_FEE = 3000;
    int24 internal constant TICK_SPACING_HIGH = 200;
    int24 internal constant MAX_TICK_HIGH = TickMath.MAX_TICK - (TickMath.MAX_TICK % TICK_SPACING_HIGH);

    function run() external {
        address token = vm.envAddress("TOKEN");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(deployerPrivateKey);

        IUniswapV3Factory v3Factory = IUniswapV3Factory(Constants.V3_FACTORY);
        IWETH9 weth = IWETH9(Constants.WETH);

        // =========================================================================
        // Pre-flight checks
        // =========================================================================
        require(block.chainid == 1514, "Wrong chain");

        address oldPoolAddr = v3Factory.getPool(token, Constants.WETH, V3_FEE);
        require(oldPoolAddr != address(0), "0.3% pool not found");

        address newPoolAddr = v3Factory.getPool(token, Constants.WETH, V3_FEE_HIGH);
        require(newPoolAddr != address(0), "1% pool not found");

        IUniswapV3Pool oldPool = IUniswapV3Pool(oldPoolAddr);
        IUniswapV3Pool newPool = IUniswapV3Pool(newPoolAddr);

        (uint160 sqrtPriceOld, int24 tickOld,,,,,) = oldPool.slot0();
        (uint160 sqrtPriceNew, int24 tickNew,,,,,) = newPool.slot0();
        uint128 newPoolLiquidity = newPool.liquidity();

        require(newPoolLiquidity == 0, "1% pool already has liquidity");
        require(sqrtPriceNew != sqrtPriceOld, "Prices already match");

        address token0 = newPool.token0();
        address token1 = newPool.token1();

        console2.log("=== Price Sync ===");
        console2.log("Token:", token);
        console2.log("0.3% pool tick:", tickOld);
        console2.log("1%   pool tick:", tickNew);
        console2.log("Target sqrtPriceX96:", sqrtPriceOld);
        console2.log("token0:", token0);
        console2.log("token1:", token1);

        // =========================================================================
        // Deploy helper and execute
        // =========================================================================
        vm.startBroadcast(deployerPrivateKey);

        // Deploy helper contract
        PoolPriceSyncer syncer = new PoolPriceSyncer();
        console2.log("\nDeployed PoolPriceSyncer:", address(syncer));

        // Wrap IP to WETH and send tokens to helper
        weth.deposit{value: 1 ether}();

        uint256 tokenAmount = 20000e18; // need ~18,380 LARRY for liquidity=1000 at tick 887271
        uint256 wethAmount = 1 ether;
        IERC20(token).transfer(address(syncer), tokenAmount);
        IERC20(Constants.WETH).transfer(address(syncer), wethAmount);

        console2.log("Funded helper with tokens");

        // Execute price sync
        syncer.syncPrice(newPool, sqrtPriceOld, -MAX_TICK_HIGH, MAX_TICK_HIGH);

        // Withdraw remaining tokens
        syncer.withdraw(token);
        syncer.withdraw(Constants.WETH);

        // Unwrap remaining WETH back to IP
        uint256 wethBal = IERC20(Constants.WETH).balanceOf(caller);
        if (wethBal > 0) weth.withdraw(wethBal);

        vm.stopBroadcast();

        // =========================================================================
        // Verification
        // =========================================================================
        (uint160 sqrtPriceFinal, int24 tickFinal,,,,,) = newPool.slot0();
        uint128 finalLiquidity = newPool.liquidity();

        console2.log("\n=== Verification ===");
        console2.log("1% pool tick (final):", tickFinal);
        console2.log("0.3% pool tick:      ", tickOld);
        console2.log("1% pool liquidity:   ", finalLiquidity);

        require(tickFinal == tickOld || (tickFinal >= tickOld - 200 && tickFinal <= tickOld + 200), "Price sync failed");
        require(finalLiquidity == 0, "Liquidity should be 0 after cleanup");
        console2.log("=== Price Sync Successful ===");
    }
}
