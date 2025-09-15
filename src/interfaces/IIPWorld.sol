// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IIPWorld {
    /// @notice Emitted when operator status is changed for an address
    /// @param operator Address whose operator status changed
    /// @param status True if operator status granted, false if revoked
    event SetOperator(address indexed operator, bool status);

    /// @notice Emitted when a new IP token is deployed
    /// @param tokenCreator Address of the token creator
    /// @param token Address of the newly deployed token
    /// @param pool Address of the created Uniswap V3 pool
    /// @param startTickList Array of tick positions for liquidity deployment
    /// @param allocationList Array of allocation percentages for each position
    event TokenDeployed(
        address indexed tokenCreator,
        address indexed token,
        address indexed pool,
        int24[] startTickList,
        uint256[] allocationList
    );

    /// @notice Emitted when a pool is initialized with initial price
    /// @param pool Address of the initialized pool
    /// @param token Address of the IP token
    /// @param initialTick Initial tick position
    /// @param sqrtPriceX96 Initial sqrt price
    event PoolInitialized(address indexed pool, address indexed token, int24 initialTick, uint160 sqrtPriceX96);

    /// @notice Emitted when liquidity is added to a position
    /// @param token Address of the IP token
    /// @param pool Address of the pool
    /// @param tickLower Lower tick of the position
    /// @param tickUpper Upper tick of the position
    /// @param liquidity Amount of liquidity added
    /// @param tokenAmount Amount of tokens used
    event LiquidityDeployed(
        address indexed token,
        address indexed pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 tokenAmount
    );

    /// @notice Emitted when liquidity is collected from a position
    /// @param pool Address of the pool
    /// @param tickLower Lower tick of the position
    /// @param tickUpper Upper tick of the position
    /// @param wethAmount Amount of WETH collected
    /// @param tokenAmount Amount of tokens collected
    event LiquidityCollected(
        address indexed pool, int24 tickLower, int24 tickUpper, uint256 wethAmount, uint256 tokenAmount
    );

    /// @notice Emitted when a token is linked to an IP asset
    /// @param ipaId IP asset identifier
    /// @param token Address of the linked token
    event Linked(address indexed ipaId, address indexed token);

    /// @notice Emitted when an IP asset is claimed by a recipient
    /// @param ipaId IP asset identifier
    /// @param recipient Address of the IP asset recipient
    event Claimed(address indexed ipaId, address indexed recipient);

    /// @notice Emitted when a new recipient is pending for an IP asset
    /// @param ipaId IP asset identifier
    /// @param currentRecipient Current recipient of the IP asset
    /// @param pendingRecipient Address of the pending recipient
    event RecipientPending(address indexed ipaId, address indexed currentRecipient, address indexed pendingRecipient);

    /// @notice Emitted when fees are harvested with detailed distribution
    /// @param token Address of the harvested token
    /// @param wethCollected Total WETH collected from fees
    /// @param tokensCollected Total tokens collected from fees
    /// @param tokensBurned Amount of tokens burned
    /// @param wethToBuyback WETH sent to bid wall
    /// @param wethToIpOwner WETH sent to IP owner vault
    event Harvest(
        address indexed token,
        uint256 wethCollected,
        uint256 tokensCollected,
        uint256 tokensBurned,
        uint256 wethToBuyback,
        uint256 wethToIpOwner
    );

    /// @notice Precision used for v3 calculations
    /// @return Precision constant used for percentage calculations
    function PRECISION() external view returns (uint256);

    /// @notice Fee value for LP pools (equivalent to a 0.3% fee)
    /// @return Uniswap V3 fee tier for all IP token pools
    function V3_FEE() external view returns (uint24);

    /// @notice IP world owner vault (for vesting IP owner shares)
    /// @return Address of the vault contract managing IP owner token vesting
    function ownerVault() external view returns (address);

    /// @notice Address of IP world treasury
    /// @return Address of the treasury receiving protocol fees
    function treasury() external view returns (address);

    /// @notice Share of LP fees designated as an $IP fee for the IP asset owner
    /// @return Percentage share of fees allocated to IP owners
    function ipOwnerShare() external view returns (uint24);

    /// @notice Share of LP fees designated as an $IP fee for the bid wall
    /// @return Percentage share of fees used for bid wall repositioning
    function buybackShare() external view returns (uint24);

    /// @notice Share of LP fees designated as an $Token fee for the burn
    /// @return Percentage share of fees used for token burning
    function burnShare() external view returns (uint24);

    /// @notice Amount of ETH allocated for bid wall operations
    /// @return Fixed amount of ETH used for each token's bid wall
    function bidWallAmount() external view returns (uint256);

    /// @notice Duration of anti-snipe protection in seconds
    /// @return Duration of anti-snipe period for newly created tokens
    function ANTI_SNIPE_DURATION() external view returns (uint256);

    /// @notice Checks if an address is an operator
    /// @param operator Address to check
    /// @return True if the address is an operator, false otherwise
    function isOperator(address operator) external view returns (bool);

    /// @notice Gets token information for a deployed IP world token
    /// @param token Address of the token
    /// @return ipaId Address of the IP asset associated with the token
    /// @return startTicks Array of start ticks for the token
    function tokenInfo(address token) external view returns (address ipaId, int24[] memory startTicks);

    /// @notice Fetches IPA recipient
    /// @param ipaId IP asset identifier
    /// @return Address of the recipient for the IP asset
    function ipaRecipient(address ipaId) external view returns (address);

    /// @notice Gets the designated claimer (IP owner) for a token
    /// @param token Address of the token
    /// @return Address of the claimer or zero if none exists
    function getTokenIpRecipient(address token) external view returns (address);

    /// @notice Gets the pending recipient for an IP asset
    /// @param ipaId IP asset identifier
    /// @return Address of the pending recipient or zero if none exists
    function ipaPendingRecipient(address ipaId) external view returns (address);

    /// @notice Sets or removes operator status for an address
    /// @dev Only the contract owner can call this function
    /// @param operator Address to set operator status for
    /// @param status True to grant operator permissions, false to revoke
    function setOperator(address operator, bool status) external;

    /// @notice Claims an IP asset for a recipient, initiating a two-step process if already claimed
    /// @dev Only operators can call this function. If the IP asset has no recipient, sets directly.
    ///      If already has a recipient, sets as pending and requires acceptance via acceptRecipient.
    /// @param ipaId Story Protocol IP asset identifier
    /// @param recipient Address that will receive the IP asset rewards
    function claimIp(address ipaId, address recipient) external;

    /// @notice Accepts the recipient role transfer for an IP asset
    /// @dev Can only be called by the current recipient. Completes the two-step transfer process by approving the pending recipient.
    /// @param ipaId Story Protocol IP asset identifier to accept recipient transfer for
    function acceptRecipient(address ipaId) external;

    /// @notice Links existing tokens to an IP asset
    /// @dev Only operators can call this function. Updates the token info for each token
    /// @param ipaId Story Protocol IP asset identifier to link tokens to
    /// @param tokenList Array of token addresses to be linked to the IP asset
    function linkTokensToIp(address ipaId, address[] calldata tokenList) external;

    /// @notice Creates a new IP token with liquidity positions and optional IP asset linking
    /// @dev Only operators can call this function. Deploys token, creates pool, adds liquidity, and sets up vesting.
    ///      Remaining tokens after liquidity allocation are sent to IPOwnerVault for vesting.
    /// @param tokenCreator Address of the token creator who will own initial allocation rights
    /// @param name ERC20 token name
    /// @param symbol ERC20 token symbol
    /// @param ipaId Story Protocol IP asset identifier to link (zero address if none)
    /// @param startTickList Array of tick values defining liquidity position boundaries (each must be multiple of TICK_SPACING = 60)
    /// @param allocationList Array of allocation percentages for each liquidity position (sum must be <= PRECISION = 1,000,000)
    /// @return pool Address of the created Uniswap V3 pool
    /// @return token Address of the deployed IP token contract
    function createIpToken(
        address tokenCreator,
        string calldata name,
        string calldata symbol,
        address ipaId,
        int24[] calldata startTickList,
        uint256[] calldata allocationList
    ) external returns (address pool, address token);

    /// @notice Harvests fees from active liquidity positions and distributes to stakeholders
    /// @dev Collects fees, repositions or burns tokens, distributes WETH to IP owner/treasury/bid wall
    /// @param token Address of the IP token to harvest fees for
    function harvest(address token) external;

    /// @notice Distributes tokens to specified recipients
    /// @dev Only operators can call this function. Used for token distribution events
    /// @param token Address of the token to distribute
    /// @param addressList Array of recipient addresses
    /// @param amountList Array of amounts to send to each recipient (must match addressList length)
    function claimToken(address token, address[] calldata addressList, uint256[] calldata amountList) external;
}
