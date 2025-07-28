// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IIPOwnerVault {
    /// @notice Contains vesting schedule information for IP token owners
    /// @param isSet Whether a vesting schedule has been created for this token
    /// @param start Unix timestamp when vesting schedule begins
    /// @param end Unix timestamp when vesting schedule completes
    /// @param remaining Amount of tokens still locked in vesting
    /// @param released Amount of tokens already released from vesting
    struct VestingData {
        bool isSet;
        uint64 start;
        uint64 end;
        uint256 remaining;
        uint256 released;
    }

    /// @notice Emitted when vested tokens are released to an IP owner
    /// @param token Address of the token being released
    /// @param amount Amount of tokens released from vesting
    event ReleasedVested(address indexed token, uint256 amount);

    /// @notice Emitted when a vesting schedule is created for a token
    /// @param token Address of the token with new vesting schedule
    /// @param totalAmount Total amount of tokens to be vested
    /// @param startTime Unix timestamp when vesting begins
    /// @param endTime Unix timestamp when vesting completes
    event VestingScheduleCreated(address indexed token, uint256 totalAmount, uint64 startTime, uint64 endTime);

    /// @notice Emitted when ETH is deposited for later claiming by IP owner
    /// @param token Address of the token receiving ETH deposit
    /// @param amount Amount of ETH deposited
    event EthDeposited(address indexed token, uint256 amount);

    /// @notice Emitted when vested tokens and ETH are claimed together
    /// @param token Address of the token being claimed
    /// @param recipient Address receiving the tokens and ETH
    /// @param tokenAmount Amount of vested tokens claimed
    /// @param ethAmount Amount of ETH claimed
    event VestedTokensAndEthClaimed(
        address indexed token, address indexed recipient, uint256 tokenAmount, uint256 ethAmount
    );

    /// @notice Gets the vesting duration for all IP tokens
    /// @return Duration in seconds that tokens vest over
    function vestingDuration() external view returns (uint64);

    /// @notice Gets the amount of ETH waiting for distribution to an IP owner
    /// @dev ETH accumulates here from harvest operations until claimed
    /// @param token Address of the IP token
    /// @return Amount of ETH pending distribution to the token's IP owner
    function owdAmount(address token) external view returns (uint256);

    /// @notice Gets the total amount of tokens already released from vesting
    /// @param token Address of the IP token
    /// @return Amount of tokens that have been released to the IP owner
    function released(address token) external view returns (uint256);

    /// @notice Gets the amount of tokens still remaining to be vested
    /// @param token Address of the IP token
    /// @return Amount of tokens still locked in vesting schedule
    function remaining(address token) external view returns (uint256);

    /// @notice Calculates how many tokens can be released immediately
    /// @param token Address of the IP token
    /// @return Amount of tokens available for immediate release
    function releasable(address token) external view returns (uint256);

    /// @notice Calculates the amount of tokens vested at a specific timestamp
    /// @dev Uses linear vesting schedule from start to end time
    /// @param token Address of the IP token
    /// @param timestamp Unix timestamp to check vesting amount at
    /// @return Amount of tokens that should be vested at the given timestamp
    function vestedAmount(address token, uint64 timestamp) external view returns (uint256);

    /// @notice Claims all available vested tokens and ETH for an IP owner
    /// @dev Can only be called after IP asset has been claimed. Transfers both tokens and ETH
    /// @param token Address of the IP token to claim vested amounts for
    function claim(address token) external;

    /// @notice Gets the complete vesting information for a token
    /// @param token Address of the IP token
    /// @return VestingData struct containing all vesting parameters and state
    function vesting(address token) external view returns (VestingData memory);

    /// @notice Creates a vesting schedule when a token is deployed
    /// @dev Only callable by the IPWorld contract. Uses current token balance as vesting amount
    /// @param token Address of the newly deployed IP token
    function createVestingOnTokenDeploy(address token) external;

    /// @notice Adds ETH to the pending distribution amount for an IP token
    /// @dev Called by IPWorld during harvest operations to accumulate ETH rewards
    /// @param token Address of the IP token to credit ETH rewards to
    function distributeOwdAmount(address token) external payable;
}
