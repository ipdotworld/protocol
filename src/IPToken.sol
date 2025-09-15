// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {PoolAddress} from "./lib/storyhunt/PoolAddress.sol";
import {IStoryHuntV3MintCallback} from "./interfaces/storyhunt/IStoryHuntV3MintCallback.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {PositionKey} from "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import {IIPToken} from "./interfaces/IIPToken.sol";
import {IIPWorld} from "./interfaces/IIPWorld.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {Errors} from "./lib/Errors.sol";

/// @title IPToken
/// @notice ERC20 token with automated bid wall for price support and permit functionality
/// @dev Deployed by IPWorld, features burnable tokens and bid wall mechanism using fixed WETH amount
contract IPToken is IIPToken, ERC20, ERC20Burnable, ERC20Permit, IStoryHuntV3MintCallback {
    using TickMath for int24;

    /// @notice Total supply allocation for new token deploys (1 billion tokens)
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice Fee tier for Uniswap V3 pool (0.3% fee)
    uint24 internal constant V3_FEE = 3000;

    /// @notice Tick spacing for bid wall positions (60 for 0.3% fee tier)
    int24 internal constant TICK_SPACING = 60;

    /// @notice Maximum valid tick for bid wall positioning (adjusted for tick spacing)
    int24 internal constant MAX_TICK = TickMath.MAX_TICK - (TickMath.MAX_TICK % TICK_SPACING);

    /// @notice Maximum sniper amount during anti-snipe period
    uint256 internal constant MAX_SNIPER_AMOUNT = 300_000_000 * 1e18;

    /// @notice Address of the IP World contract that deployed this token
    address internal immutable _ipWorld;

    /// @notice Address of Wrapped Ether for the trading pair
    address internal immutable _weth;

    /// @notice Address of the token creator
    address public immutable tokenCreator;

    /// @notice Address of the liquidity pool
    address public immutable liquidityPool;

    /// @notice Amount of bid wall
    uint256 public immutable bidWallAmount;

    /// @notice Duration of anti-snipe period in seconds (0 = no limit)
    uint256 public immutable antiSnipeDuration;

    /// @notice Token creation timestamp
    uint256 private immutable _creationTimestamp;

    /// @notice Tick range for the bid wall
    int24 public bidWallTickLower;

    /// @notice Initializes the IP token contract with fixed supply and bid wall configuration
    /// @dev Mints total supply to msg.sender (IPWorld), computes pool address deterministically
    /// @param tokenCreator_ Address of the original token creator/developer
    /// @param v3Deployer_ Address of the Uniswap V3 deployer for pool address computation
    /// @param weth_ Address of the Wrapped Ether contract for the trading pair
    /// @param bidWallAmount_ Fixed amount of ETH reserved for bid wall operations
    /// @param antiSnipeDuration_ Duration of anti-snipe period in seconds (0 = no limit)
    /// @param name_ ERC20 token name
    /// @param symbol_ ERC20 token symbol
    constructor(
        address tokenCreator_,
        address v3Deployer_,
        address weth_,
        uint256 bidWallAmount_,
        uint256 antiSnipeDuration_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        tokenCreator = tokenCreator_;
        _mint(msg.sender, TOTAL_SUPPLY);
        _ipWorld = msg.sender;
        _weth = weth_;
        liquidityPool = PoolAddress.computeAddress(v3Deployer_, PoolAddress.getPoolKey(address(this), weth_, V3_FEE));
        bidWallTickLower = MAX_TICK;
        bidWallAmount = bidWallAmount_;
        antiSnipeDuration = antiSnipeDuration_;
        _creationTimestamp = block.timestamp;
    }

    function repositionBidWall() external {
        (, int24 currentTick,,,,,) = IUniswapV3Pool(liquidityPool).slot0();
        bool nativeIsZero = _weth < address(this);

        int24 newTickLower;
        int24 newTickUpper;

        (uint256 wethCollected, uint256 tokensCollected) =
            _collectLiquidity(IUniswapV3Pool(liquidityPool), bidWallTickLower, nativeIsZero);
        uint256 burnAmount = balanceOf(address(this));
        if (burnAmount > 0) {
            _burn(address(this), burnAmount);
        }

        if (nativeIsZero) {
            int24 baseTick = currentTick + 1;
            newTickLower = _validTick(baseTick, false);
            newTickUpper = newTickLower + TICK_SPACING;
            if (newTickUpper > MAX_TICK) {
                return;
            }
        } else {
            int24 baseTick = currentTick - 1;
            newTickUpper = _validTick(baseTick, true);
            newTickLower = newTickUpper - TICK_SPACING;
            if (newTickLower < -MAX_TICK) {
                return;
            }
        }
        uint256 wethForLiquidity = IERC20(_weth).balanceOf(address(this));
        if (wethForLiquidity > bidWallAmount) {
            wethForLiquidity = bidWallAmount;
        }
        uint128 newLiquidity =
            _addLiquidity(IUniswapV3Pool(liquidityPool), wethForLiquidity, newTickLower, nativeIsZero);

        bidWallTickLower = newTickLower;

        // Emit bid wall repositioned event
        emit BidWallRepositioned(
            newTickLower, newTickUpper, wethCollected, tokensCollected, burnAmount, wethForLiquidity, newLiquidity
        );
    }

    /// @notice Adds WETH liquidity to create a one-sided bid wall at specified tick range
    /// @param pool Uniswap V3 pool to add liquidity to
    /// @param wethForLiquidity Amount of WETH to use for liquidity provision
    /// @param tickLower Lower tick boundary for the bid wall position
    /// @param nativeIsZero Whether WETH is token0 in the pool
    function _addLiquidity(IUniswapV3Pool pool, uint256 wethForLiquidity, int24 tickLower, bool nativeIsZero)
        internal
        returns (uint128 liquidity)
    {
        if (wethForLiquidity == 0) return 0;
        int24 tickUpper = tickLower + TICK_SPACING;
        uint160 lowerSqrtPriceX96 = tickLower.getSqrtRatioAtTick();
        uint160 upperSqrtPriceX96 = tickUpper.getSqrtRatioAtTick();

        if (nativeIsZero) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(lowerSqrtPriceX96, upperSqrtPriceX96, wethForLiquidity);
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(lowerSqrtPriceX96, upperSqrtPriceX96, wethForLiquidity);
        }
        if (liquidity == 0) return 0;

        pool.mint(address(this), tickLower, tickUpper, liquidity, "");
        return liquidity;
    }

    /// @notice Collects all liquidity and fees from the bid wall position
    /// @param pool Uniswap V3 pool to collect from
    /// @param tickLower Lower tick boundary of the bid wall position
    /// @param nativeIsZero Whether WETH is token0 in the pool
    /// @return wethAmount Amount of WETH collected from the position
    /// @return tokenAmount Amount of IP tokens collected from the position
    function _collectLiquidity(IUniswapV3Pool pool, int24 tickLower, bool nativeIsZero)
        internal
        returns (uint256 wethAmount, uint256 tokenAmount)
    {
        int24 tickUpper;
        if (nativeIsZero) {
            tickUpper = tickLower + TICK_SPACING;
        } else {
            tickUpper = -tickLower;
            tickLower = -tickLower - TICK_SPACING;
        }

        bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);
        (uint128 burnAmount,,,,) = pool.positions(positionKey);
        if (burnAmount == 0) return (0, 0);
        pool.burn(tickLower, tickUpper, burnAmount);
        (wethAmount, tokenAmount) =
            pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    /// @notice Normalizes a tick value to conform to Uniswap V3 tick spacing requirements
    /// @dev This function handles several critical cases:
    ///      1. Clamps ticks to valid range [-MAX_TICK, MAX_TICK]
    ///      2. Rounds ticks to nearest valid tick (divisible by TICK_SPACING)
    ///      3. For negative ticks, adjusts rounding behavior due to integer division truncation
    ///      4. Ensures final result doesn't exceed boundaries when rounding up
    /// @param tick Raw tick value that may not conform to tick spacing
    /// @param _roundDown True to round down to nearest valid tick, false to round up
    /// @return tick_ Valid tick that conforms to TICK_SPACING and is within valid range
    function _validTick(int24 tick, bool _roundDown) internal pure returns (int24 tick_) {
        // If we have a malformed tick, then we need to bring it back within range
        if (tick < -MAX_TICK) tick = -MAX_TICK;
        else if (tick > MAX_TICK) tick = MAX_TICK;

        // If the tick is already valid, exit early
        if (tick % TICK_SPACING == 0) {
            return tick;
        }

        tick = tick / TICK_SPACING * TICK_SPACING;
        if (tick < 0) {
            tick -= TICK_SPACING;
        }

        // If we are rounding up, then we can just add a `TICK_SPACING` to the lower tick
        if (!_roundDown) {
            int24 result = tick + TICK_SPACING;
            // Ensure the result doesn't exceed MAX_TICK
            if (result > MAX_TICK) {
                result = MAX_TICK;
            }
            return result;
        }
        return tick;
    }

    /// @notice Override transfer to implement anti-snipe protection
    /// @dev Restricts transfers from liquidity pool during anti-snipe period
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();

        // Check anti-snipe protection if enabled and transfer is from liquidity pool
        if (antiSnipeDuration > 0 && owner == liquidityPool && block.timestamp < _creationTimestamp + antiSnipeDuration)
        {
            // During anti-snipe period, limit transfers from liquidity pool
            // But allow token creator to buy without limit
            if (to != tokenCreator && amount > MAX_SNIPER_AMOUNT) {
                revert Errors.IPToken_ExceedsAntiSnipeLimit();
            }
        }

        _transfer(owner, to, amount);
        return true;
    }

    /// @notice Override transferFrom to implement anti-snipe protection
    /// @dev Restricts transfers from liquidity pool during anti-snipe period
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);

        // Check anti-snipe protection if enabled and transfer is from liquidity pool
        if (antiSnipeDuration > 0 && from == liquidityPool && block.timestamp < _creationTimestamp + antiSnipeDuration)
        {
            // During anti-snipe period, limit transfers from liquidity pool
            // But allow token creator to buy without limit
            if (to != tokenCreator && amount > MAX_SNIPER_AMOUNT) {
                revert Errors.IPToken_ExceedsAntiSnipeLimit();
            }
        }

        _transfer(from, to, amount);
        return true;
    }

    /// @notice Transfers tokens to LP pool post-deployment via v3 mint callback
    /// @param amount0Owed Amount of token0 required for liquidity transfer
    /// @param amount1Owed Amount of token1 required for liquidity transfer
    function storyHuntV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        if (msg.sender != liquidityPool) {
            revert Errors.IPToken_OnlyLiquidityPool();
        }

        if (amount1Owed > 0) {
            IERC20(_weth).transfer(msg.sender, amount1Owed);
        } else if (amount0Owed > 0) {
            IERC20(_weth).transfer(msg.sender, amount0Owed);
        }
    }
}
