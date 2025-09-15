// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IP Token Interface
/// @notice Interface for IP tokens with automated bid wall mechanism
/// @dev The bid wall is a one-sided liquidity position using WETH that provides price support.
///      It automatically repositions based on current market price to maintain buy pressure
///      below market price and burns any collected tokens.
interface IIPToken {
    /// @notice Emitted when the bid wall is repositioned
    /// @param newTickLower New lower tick of the bid wall
    /// @param newTickUpper New upper tick of the bid wall
    /// @param wethCollected Amount of WETH collected from old position
    /// @param tokensCollected Amount of tokens collected from old position
    /// @param tokensBurned Amount of tokens burned
    /// @param wethForLiquidity Amount of WETH used for the new liquidity position
    /// @param newLiquidity Amount of liquidity in new position
    event BidWallRepositioned(
        int24 indexed newTickLower,
        int24 newTickUpper,
        uint256 wethCollected,
        uint256 tokensCollected,
        uint256 tokensBurned,
        uint256 wethForLiquidity,
        uint128 newLiquidity
    );
    /// @notice Address of the token creator
    /// @return Address of the creator who deployed this token

    function tokenCreator() external view returns (address);

    /// @notice Address of the liquidity pool
    /// @return Address of the Uniswap V3 pool for this token
    function liquidityPool() external view returns (address);

    /// @notice Amount of ETH used for the bid wall
    /// @return Amount of ETH allocated for bid wall operations
    function bidWallAmount() external view returns (uint256);

    /// @notice Current bid wall tick lower position
    /// @return Current lower tick position of the bid wall
    function bidWallTickLower() external view returns (int24);

    /// @notice Duration of anti-snipe period in seconds (0 = no limit)
    /// @return Duration of anti-snipe protection in seconds
    function antiSnipeDuration() external view returns (uint256);

    /// @notice Repositions the bid wall based on current market conditions
    /// @dev This function collects existing liquidity, burns tokens, and creates new liquidity at appropriate tick range
    function repositionBidWall() external;
}
