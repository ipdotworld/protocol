// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPToken} from "./IPToken.sol";
import {IAntiSnipeToken} from "./interfaces/IAntiSnipeToken.sol";
import {Errors} from "./lib/Errors.sol";

/// @title IPAntiSnipeToken
/// @notice ERC20 token with automated bid wall for price support, permit functionality, and anti-snipe protection
/// @dev Extends IPToken with transfer limits during anti-snipe period
contract IPAntiSnipeToken is IPToken, IAntiSnipeToken {
    /// @notice Maximum sniper amount during anti-snipe period
    uint256 public constant MAX_SNIPER_AMOUNT = 200_000_000 * 1e18;

    /// @notice Duration of anti-snipe period in seconds (0 = no limit)
    uint256 public immutable antiSnipeDuration;

    /// @notice Token creation timestamp
    uint256 private immutable _creationTimestamp;

    /// @notice Initializes the IP anti-snipe token contract with transfer limits
    /// @dev Extends IPToken constructor with anti-snipe duration
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
    ) IPToken(tokenCreator_, v3Deployer_, weth_, bidWallAmount_, name_, symbol_) {
        antiSnipeDuration = antiSnipeDuration_;
        _creationTimestamp = block.timestamp;
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
}
