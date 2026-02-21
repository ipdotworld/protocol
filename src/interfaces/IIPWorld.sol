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

    /// @notice Emitted when fees are harvested (legacy format for Goldsky compatibility)
    event Harvest(
        address indexed token,
        uint256 wethCollected,
        uint256 tokensCollected,
        uint256 tokensBurned,
        uint256 wethToBuyback,
        uint256 wethToIpOwner
    );

    /// @notice Emitted when fees are harvested with detailed distribution
    event HarvestDistributed(
        address indexed token,
        uint256 tokenCollected,
        uint256 tokenToIpTreasury,
        uint256 tokenToUgc,
        uint256 wethCollected,
        uint256 wethToIpOwner,
        uint256 wethToBuyback,
        uint256 wethToUgc
    );

    /// @notice Emitted when ipTreasury is set for an IP asset
    event IpTreasurySet(address indexed ipaId, address indexed treasury);

    /// @notice Emitted when a referral is set for an IP asset
    event ReferralSet(address indexed ipaId, address indexed referral);

    /// @notice Emitted when a new referral is pending for an IP asset
    event ReferralPending(address indexed ipaId, address indexed currentReferral, address indexed pendingReferral);

    /// @notice Emitted when pending treasury is flushed to ipTreasury
    event TreasuryFlushed(address indexed token, address indexed treasury, uint256 amount);

    /// @notice Emitted when airdrop is claimed by a recipient
    event AirdropClaimed(address indexed token, address indexed recipient, uint256 tokenAmount, uint256 wethAmount);

    /// @notice Precision used for v3 calculations
    /// @return Precision constant used for percentage calculations
    function PRECISION() external view returns (uint256);

    /// @notice Fee value for LP pools (1% fee tier)
    /// @return Uniswap V3 fee tier for all IP token pools
    function V3_FEE() external view returns (uint24);

    /// @notice Anti-snipe duration in seconds
    /// @return Duration of anti-snipe period for new tokens
    function ANTI_SNIPE_DURATION() external view returns (uint256);

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

    /// @notice Share of fees allocated to airdrop pool
    /// @return Percentage share of fees for airdrop (out of PRECISION)
    function airdropShare() external view returns (uint24);

    /// @notice Gets the treasury address for an IP asset
    function ipTreasury(address ipaId) external view returns (address);

    /// @notice Gets the pending treasury amount for a token (before ipTreasury is set)
    function pendingTreasury(address token) external view returns (uint256);

    /// @notice Gets the token airdrop pool balance (balance - pendingTreasury)
    function tokenAirdropPool(address token) external view returns (uint256);

    /// @notice Gets the WETH airdrop pool balance
    function wethAirdropPool(address token) external view returns (uint256);

    /// @notice Amount of ETH allocated for bid wall operations
    /// @return Fixed amount of ETH used for each token's bid wall
    function bidWallAmount() external view returns (uint256);

    /// @notice Fee required to create an IP token
    /// @return Amount of ETH required as creation fee
    function creationFee() external view returns (uint256);

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
    ///      Referral is set on first claim (address(0) means no referral).
    /// @param ipaId Story Protocol IP asset identifier
    /// @param recipient Address that will receive the IP asset rewards
    /// @param referral Address of the referral for this IP asset (only used on first claim)
    function claimIp(address ipaId, address recipient, address referral) external;

    /// @notice Accepts the recipient role transfer for an IP asset
    /// @dev Can only be called by the current recipient. Completes the two-step transfer process by approving the pending recipient.
    /// @param ipaId Story Protocol IP asset identifier to accept recipient transfer for
    function acceptRecipient(address ipaId) external;

    /// @notice Sets the treasury address for an IP asset (one-time, immutable)
    /// @dev Only operators can call this function. Reverts if treasury is already set.
    /// @param ipaId Story Protocol IP asset identifier
    /// @param treasury Address of the treasury for this IP asset
    function setIpTreasury(address ipaId, address treasury) external;

    /// @notice Proposes a new referral for an IP asset (step 1 of two-step process)
    /// @dev Only operators can call this function. Requires acceptance via acceptReferral.
    /// @param ipaId Story Protocol IP asset identifier
    /// @param newReferral Address of the proposed new referral
    function setReferral(address ipaId, address newReferral) external;

    /// @notice Accepts the referral change for an IP asset (step 2 of two-step process)
    /// @dev Can only be called by the current recipient.
    /// @param ipaId Story Protocol IP asset identifier
    function acceptReferral(address ipaId) external;

    /// @notice Gets the referral address for an IP asset
    /// @param ipaId IP asset identifier
    /// @return Address of the referral or zero if none exists
    function referral(address ipaId) external view returns (address);

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
    /// @param startTickList Array of tick values defining liquidity position boundaries (each must be multiple of TICK_SPACING = 200)
    /// @param allocationList Array of allocation percentages for each liquidity position (sum must be <= PRECISION = 1,000,000)
    /// @param antiSnipe If true, enables anti-snipe protection for ANTI_SNIPE_DURATION seconds
    /// @return pool Address of the created Uniswap V3 pool
    /// @return token Address of the deployed IP token contract
    function createIpToken(
        address tokenCreator,
        string calldata name,
        string calldata symbol,
        address ipaId,
        int24[] calldata startTickList,
        uint256[] calldata allocationList,
        bool antiSnipe
    ) external payable returns (address pool, address token);

    /// @notice Harvests fees from active liquidity positions and distributes to stakeholders
    /// @dev Collects fees, repositions or burns tokens, distributes WETH to IP owner/treasury/bid wall
    /// @param token Address of the IP token to harvest fees for
    function harvest(address token) external;

    /// @notice Distributes token and WETH airdrop to specified recipients
    /// @dev Only operators can call this function. Replaces claimToken.
    /// @param token Address of the token to distribute
    /// @param recipients Array of recipient addresses
    /// @param tokenAmounts Array of token amounts for each recipient
    /// @param wethAmounts Array of WETH amounts for each recipient
    function claimAirdrop(
        address token,
        address[] calldata recipients,
        uint256[] calldata tokenAmounts,
        uint256[] calldata wethAmounts
    ) external;
}
