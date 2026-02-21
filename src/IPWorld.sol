// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IERC721Receiver
} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {
    LiquidityAmounts
} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import {
    IStoryHuntV3MintCallback
} from "./interfaces/storyhunt/IStoryHuntV3MintCallback.sol";

import {TokenInfoLibrary, TokenInfo} from "./lib/TokenInfo.sol";
import {IIPWorld} from "./interfaces/IIPWorld.sol";
import {IIPOwnerVault} from "./interfaces/IIPOwnerVault.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {IIPToken} from "./interfaces/IIPToken.sol";
import {IIPTokenDeployer} from "./interfaces/IIPTokenDeployer.sol";
import {Errors} from "./lib/Errors.sol";

/// @title IPWorld
/// @notice Main platform contract for launching IP-backed memecoins with one-sided Uniswap V3 liquidity
/// @dev Manages token deployment, IP linking, LP management, and fee distribution. Upgradeable via UUPS.
contract IPWorld is
    IIPWorld,
    IStoryHuntV3MintCallback,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    IERC721Receiver
{
    using TickMath for int24;
    using TokenInfoLibrary for TokenInfo;
    using TokenInfoLibrary for mapping(address token => TokenInfo);

    uint256 public constant PRECISION = 1000000;

    /// @notice Fee tier for 1% pools
    uint24 public constant V3_FEE = 10000;

    /// @notice Anti-snipe duration in seconds (2 minutes)
    uint256 public constant ANTI_SNIPE_DURATION = 120;

    /// @notice Tick spacing for 1% fee tier pools
    int24 private constant TICK_SPACING = 200;

    /// @notice Maximum valid tick for LP positions (adjusted for tick spacing)
    int24 private constant MAX_TICK =
        TickMath.MAX_TICK - (TickMath.MAX_TICK % TICK_SPACING);

    /// @notice Address of Wrapped Ether contract for trading pairs
    address private immutable _weth;

    /// @notice Address of Uniswap v3 pool deployer contract for pool creation
    address private immutable _v3Deployer;

    /// @notice Uniswap v3 factory contract interface for pool management
    IUniswapV3Factory private immutable _v3Factory;

    /// @notice Address of the IP token deployer contract
    IIPTokenDeployer private immutable _tokenDeployer;

    address public immutable ownerVault;

    address public immutable treasury;

    uint24 public immutable airdropShare;

    uint24 public immutable ipOwnerShare;

    uint24 public immutable buybackShare;

    uint256 public immutable bidWallAmount;

    /// @notice Fee required to create an IP token, transferred to treasury
    uint256 public immutable creationFee;

    mapping(address operator => bool) public isOperator;

    /// @notice Stores token information including IP asset linkage and tick configurations
    mapping(address token => TokenInfo) private _tokenInfo;

    /// @notice Maps IP asset identifiers to their designated reward recipients
    mapping(address ipaId => address recipient) private _ipaRecipient;

    /// @notice Maps IP asset identifiers to their pending reward recipients
    mapping(address ipaId => address pendingRecipient)
        private _ipaPendingRecipient;

    /// @notice Per-IPA treasury address (immutable once set)
    mapping(address ipaId => address) public ipTreasury;

    /// @notice Per-IPA referral address
    mapping(address ipaId => address) public referral;

    /// @notice Pending referral for two-step referral change
    mapping(address ipaId => address) private _pendingReferral;

    /// @notice Accumulated token treasury amount before ipTreasury is set
    mapping(address token => uint256) public pendingTreasury;

    /// @notice WETH airdrop pool accumulated from harvest (stored as WETH token)
    mapping(address token => uint256) public wethAirdropPool;

    /// @notice Initializes the IP World contract with immutable configuration
    /// @dev Validates addresses are non-zero and ipOwnerShare + buybackShare <= PRECISION.
    ///      The sum can be less than PRECISION. Remaining share goes to treasury.
    /// @param weth_ Address of the Wrapped Ether contract
    /// @param v3Deployer_ Address of the Uniswap V3 pool deployer contract
    /// @param v3Factory_ Address of the Uniswap V3 factory contract
    /// @param ownerVault_ Address of the IP owner vault for token vesting
    /// @param treasury_ Address of the protocol treasury
    /// @param airdropShare_ Percentage of fees allocated to airdrop pool (out of 1,000,000)
    /// @param ipOwnerShare_ Percentage of fees allocated to IP owners (out of 1,000,000)
    /// @param buybackShare_ Percentage of fees used for bid wall operations (out of 1,000,000)
    /// @param bidWallAmount_ Fixed amount of ETH allocated for each token's bid wall
    /// @param tokenDeployer_ Address of the IP token deployer contract
    /// @param creationFee_ Fee required to create an IP token
    constructor(
        address weth_,
        address v3Deployer_,
        address v3Factory_,
        address tokenDeployer_,
        address ownerVault_,
        address treasury_,
        uint24 airdropShare_,
        uint24 ipOwnerShare_,
        uint24 buybackShare_,
        uint256 bidWallAmount_,
        uint256 creationFee_
    ) {
        if (
            weth_ == address(0) ||
            v3Deployer_ == address(0) ||
            v3Factory_ == address(0) ||
            ownerVault_ == address(0) ||
            treasury_ == address(0) ||
            tokenDeployer_ == address(0)
        ) {
            revert Errors.IPWorld_InvalidAddress();
        }
        if (ipOwnerShare_ + buybackShare_ + airdropShare_ > PRECISION) {
            revert Errors.IPWorld_InvalidShare();
        }
        _weth = weth_;
        _v3Deployer = v3Deployer_;
        _v3Factory = IUniswapV3Factory(v3Factory_);
        _tokenDeployer = IIPTokenDeployer(tokenDeployer_);
        ownerVault = ownerVault_;
        treasury = treasury_;
        airdropShare = airdropShare_;
        ipOwnerShare = ipOwnerShare_;
        buybackShare = buybackShare_;
        bidWallAmount = bidWallAmount_;
        creationFee = creationFee_;
        _disableInitializers();
    }

    /// @notice Initializes the IP world contract
    /// @param initialOwner Initial contract owner
    function initialize(address initialOwner) public initializer {
        _transferOwnership(initialOwner);
    }

    /// @notice Restricts calls to only be made through enrolled operators
    modifier onlyOperator() {
        if (!isOperator[msg.sender]) {
            revert Errors.IPWorld_OperatorOnly();
        }
        _;
    }

    ///
    /// Getters and Setters
    ///

    function tokenInfo(
        address token
    )
        external
        view
        override
        returns (address ipaId, int24[] memory startTicks)
    {
        return _tokenInfo[token].decode();
    }

    function ipaRecipient(
        address ipaId
    ) external view override returns (address) {
        return _ipaRecipient[ipaId];
    }

    function ipaPendingRecipient(
        address ipaId
    ) external view override returns (address) {
        return _ipaPendingRecipient[ipaId];
    }

    function getTokenIpRecipient(
        address token
    ) external view returns (address) {
        (address ipaId, ) = _tokenInfo[token].decode();
        return _ipaRecipient[ipaId];
    }

    /// @notice Gets the token airdrop pool balance (calculated as balance - pendingTreasury)
    function tokenAirdropPool(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this)) - pendingTreasury[token];
    }

    function setOperator(address operator, bool status) external onlyOwner {
        if (operator == treasury) {
            revert Errors.IPWorld_InvalidAddress();
        }
        isOperator[operator] = status;
        emit SetOperator(operator, status);
    }

    ///
    /// IP Asset Management
    ///

    function claimIp(
        address ipaId,
        address recipient,
        address referral_
    ) external onlyOperator {
        if (ipaId == address(0) || recipient == address(0)) {
            revert Errors.IPWorld_InvalidAddress();
        }

        address currentRecipient = _ipaRecipient[ipaId];
        if (currentRecipient == address(0)) {
            // First time claiming - set recipient and referral
            _ipaRecipient[ipaId] = recipient;
            emit Claimed(ipaId, recipient);

            // Set referral (address(0) = no referral, allowed)
            referral[ipaId] = referral_;
            if (referral_ != address(0)) {
                emit ReferralSet(ipaId, referral_);
            }
        } else {
            // Already has a recipient - initiate two-step transfer
            _ipaPendingRecipient[ipaId] = recipient;
            emit RecipientPending(ipaId, currentRecipient, recipient);
        }
    }

    function acceptRecipient(address ipaId) external {
        address pendingRecipient = _ipaPendingRecipient[ipaId];
        if (pendingRecipient == address(0)) {
            revert Errors.IPWorld_NoPendingRecipient();
        }
        address currentRecipient = _ipaRecipient[ipaId];
        if (msg.sender != currentRecipient) {
            revert Errors.IPWorld_NotCurrentRecipient();
        }

        _ipaRecipient[ipaId] = pendingRecipient;
        delete _ipaPendingRecipient[ipaId];
        emit Claimed(ipaId, pendingRecipient);
    }

    function setIpTreasury(
        address ipaId,
        address treasury_
    ) external onlyOperator {
        if (treasury_ == address(0)) {
            revert Errors.IPWorld_InvalidIpTreasury();
        }
        if (ipTreasury[ipaId] != address(0)) {
            revert Errors.IPWorld_IpTreasuryAlreadySet();
        }
        ipTreasury[ipaId] = treasury_;
        emit IpTreasurySet(ipaId, treasury_);
    }

    function setReferral(
        address ipaId,
        address newReferral
    ) external onlyOperator {
        if (newReferral == address(0)) {
            revert Errors.IPWorld_InvalidReferral();
        }
        address currentReferral = referral[ipaId];
        _pendingReferral[ipaId] = newReferral;
        emit ReferralPending(ipaId, currentReferral, newReferral);
    }

    function acceptReferral(address ipaId) external {
        address currentRecipient = _ipaRecipient[ipaId];
        if (currentRecipient != msg.sender) {
            revert Errors.IPWorld_NotCurrentRecipient();
        }
        address pendingRef = _pendingReferral[ipaId];
        if (pendingRef == address(0)) {
            revert Errors.IPWorld_NoPendingReferral();
        }
        referral[ipaId] = pendingRef;
        delete _pendingReferral[ipaId];
        emit ReferralSet(ipaId, pendingRef);
    }

    function linkTokensToIp(
        address ipaId,
        address[] calldata tokenList
    ) external onlyOperator {
        if (ipaId == address(0)) {
            revert Errors.IPWorld_InvalidAddress();
        }
        for (uint256 i = 0; i < tokenList.length; ++i) {
            address token = tokenList[i];
            if (token == address(0)) {
                revert Errors.IPWorld_InvalidAddress();
            }
            _tokenInfo.updateTokenInfo(token, ipaId);
            emit Linked(ipaId, token);
        }
    }

    ///
    /// Token Deployment
    ///

    function createIpToken(
        address tokenCreator,
        string calldata name,
        string calldata symbol,
        address ipaId,
        int24[] calldata startTickList,
        uint256[] calldata allocationList,
        bool antiSnipe
    ) external payable onlyOperator returns (address pool, address token) {
        // CEI: Checks - Validate fee
        if (msg.value != creationFee) {
            revert Errors.IPWorld_InvalidFee();
        }

        // CEI: Interactions - Transfer fee to treasury before state changes
        if (creationFee > 0) {
            (bool success, ) = treasury.call{value: msg.value}("");
            if (!success) revert Errors.IPWorld_FeeTransferFailed();
        }

        if (tokenCreator == address(0)) {
            revert Errors.IPWorld_InvalidAddress();
        }
        uint256 length = startTickList.length;
        if (
            length != allocationList.length ||
            length > TokenInfoLibrary.MAX_LP ||
            length == 0
        ) {
            revert Errors.IPWorld_InvalidTick();
        }

        uint256 antiSnipeDuration = antiSnipe ? ANTI_SNIPE_DURATION : 0;
        token = _tokenDeployer.deployToken(
            tokenCreator,
            _v3Deployer,
            _weth,
            bidWallAmount,
            antiSnipeDuration,
            name,
            symbol
        );
        pool = _v3Factory.getPool(token, _weth, V3_FEE);
        if (pool == address(0)) {
            pool = _v3Factory.createPool(token, _weth, V3_FEE);
        }
        emit TokenDeployed(
            tokenCreator,
            token,
            pool,
            startTickList,
            allocationList
        );

        (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        if (sqrtRatioX96 == 0) {
            int24 initialTick = _weth < token ? MAX_TICK : -MAX_TICK;
            uint160 initialSqrtPrice = initialTick.getSqrtRatioAtTick();
            IUniswapV3Pool(pool).initialize(initialSqrtPrice);
            emit PoolInitialized(pool, token, initialTick, initialSqrtPrice);
        }

        int24 startTick = startTickList[0];
        if (startTick % TICK_SPACING != 0) {
            revert Errors.IPWorld_InvalidTick();
        }
        uint256 totalSupply = IERC20(token).totalSupply();
        for (uint256 i = 1; i <= length; ++i) {
            int24 nextTick = (i == length) ? MAX_TICK : startTickList[i];
            if (
                startTick < TickMath.MIN_TICK ||
                startTick >= nextTick ||
                nextTick % TICK_SPACING != 0
            ) {
                revert Errors.IPWorld_InvalidTick();
            }
            uint256 liquidity = (totalSupply * allocationList[i - 1]) /
                PRECISION;
            _addLiquidity(
                token,
                IUniswapV3Pool(pool),
                liquidity,
                startTick,
                nextTick
            );
            startTick = nextTick;
        }

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(token).transfer(ownerVault, tokenBalance);
        }

        _tokenInfo[token] = TokenInfoLibrary.encode(ipaId, startTickList);

        if (ipaId != address(0)) {
            emit Linked(ipaId, token);
        }
    }

    ///
    /// LP Management
    ///

    function harvest(address token) external {
        if (token == address(0)) {
            revert Errors.IPWorld_InvalidAddress();
        }
        (address ipaId, int24[] memory startTickList) = _tokenInfo[token]
            .decode();
        uint256 length = startTickList.length;
        if (length == 0) {
            revert Errors.IPWorld_WrongToken();
        }

        // Look up the 1% pool from factory (all tokens use 1% pool after migration)
        IUniswapV3Pool pool = IUniswapV3Pool(
            _v3Factory.getPool(_weth, token, V3_FEE)
        );
        if (address(pool) == address(0)) {
            revert Errors.IPWorld_WrongToken();
        }

        // Determine if token supports bid wall (new IPToken has repositionBidWall)
        bool isNewToken;
        try IIPToken(token).liquidityPool() {
            isNewToken = true;
        } catch {
            isNewToken = false;
        }
        bool isNativeZero = _weth < token;

        (, int24 currentTick, , , , , ) = pool.slot0();
        if (isNativeZero) currentTick = -currentTick;

        int24 startTick;
        int24 nextTick;
        uint256 i;
        for (i = 0; i < length; ++i) {
            startTick = startTickList[i];
            nextTick = (i == length - 1) ? MAX_TICK : startTickList[i + 1];
            if (startTick <= currentTick && currentTick < nextTick) {
                break;
            }
        }

        /// @dev Collect fees from the current active liquidity position
        (uint256 wethAmount, uint256 tokenAmount) = _collectLiquidity(
            pool,
            startTick,
            nextTick,
            isNativeZero
        );

        /// @dev Distribute token fees: airdrop pool + ipTreasury (or pendingTreasury)
        uint256 tokenTreasuryAmount;
        uint256 tokenAirdropAmount;
        if (tokenAmount > 0) {
            tokenAirdropAmount = (tokenAmount * airdropShare) / PRECISION;
            tokenTreasuryAmount = tokenAmount - tokenAirdropAmount;

            // Handle treasury distribution based on ipTreasury (per-IPA)
            address ipTreasury_ = ipTreasury[ipaId];
            if (ipTreasury_ != address(0)) {
                uint256 pending = pendingTreasury[token];
                uint256 totalTreasuryAmount = tokenTreasuryAmount + pending;
                if (pending > 0) pendingTreasury[token] = 0;
                IERC20(token).transfer(ipTreasury_, totalTreasuryAmount);
                if (pending > 0)
                    emit TreasuryFlushed(token, ipTreasury_, pending);
            } else {
                pendingTreasury[token] += tokenTreasuryAmount;
            }
            // tokenAirdropAmount stays in contract (no tracking needed)
        }

        address recipient = _ipaRecipient[ipaId];

        // Create vesting schedule if recipient exists and vesting not yet set
        if (
            recipient != address(0) &&
            !IIPOwnerVault(ownerVault).vesting(token).isSet
        ) {
            IIPOwnerVault(ownerVault).createVestingOnTokenDeploy(token);
        }

        uint256 buybackAmount;
        uint256 ipOwnerAmount;
        uint256 wethAirdropAmount;

        if (wethAmount != 0) {
            if (i == 0) {
                // 1st LP: 100% to protocol treasury
                IWETH9(_weth).withdraw(wethAmount);
                (bool success, ) = treasury.call{value: wethAmount}("");
                if (!success) revert();
            } else {
                // 2nd+ LP: all shares on full wethAmount
                buybackAmount = (wethAmount * buybackShare) / PRECISION;
                ipOwnerAmount = (wethAmount * ipOwnerShare) / PRECISION;
                wethAirdropAmount = (wethAmount * airdropShare) / PRECISION;
                uint256 treasuryAmount = wethAmount -
                    buybackAmount -
                    ipOwnerAmount -
                    wethAirdropAmount;

                // Accumulate WETH airdrop (keep as WETH)
                wethAirdropPool[token] += wethAirdropAmount;

                if (isNewToken) {
                    // New token: send buyback amount to token and call repositionBidWall
                    IERC20(_weth).transfer(address(token), buybackAmount);
                    IIPToken(token).repositionBidWall();
                } else {
                    // Old token: skip buyback (add buyback to treasury since no bid wall)
                    treasuryAmount += buybackAmount;
                    buybackAmount = 0;
                }

                uint256 wethToWithdraw = ipOwnerAmount + treasuryAmount;
                IWETH9(_weth).withdraw(wethToWithdraw);

                (bool success, ) = treasury.call{value: treasuryAmount}("");
                if (!success) revert();

                IIPOwnerVault(ownerVault).distributeOwdAmount{
                    value: ipOwnerAmount
                }(token);
            }
        }

        // Emit legacy event (Goldsky compatibility) - tokensBurned always 0
        emit Harvest(
            token,
            wethAmount,
            tokenAmount,
            0,
            buybackAmount,
            ipOwnerAmount
        );

        // Emit new detailed event
        emit HarvestDistributed(
            token,
            tokenAmount,
            tokenTreasuryAmount,
            tokenAirdropAmount,
            wethAmount,
            ipOwnerAmount,
            buybackAmount,
            wethAirdropAmount
        );
    }

    ///
    /// Token Management
    ///

    function claimAirdrop(
        address token,
        address[] calldata recipients,
        uint256[] calldata tokenAmounts,
        uint256[] calldata wethAmounts
    ) external onlyOperator {
        if (token == address(0)) {
            revert Errors.IPWorld_InvalidAddress();
        }

        uint256 length = recipients.length;
        if (length != tokenAmounts.length || length != wethAmounts.length) {
            revert Errors.IPWorld_InvalidArgument();
        }

        uint256 totalTokenAmount;
        uint256 totalWethAmount;
        for (uint256 i = 0; i < length; ++i) {
            totalTokenAmount += tokenAmounts[i];
            totalWethAmount += wethAmounts[i];
        }

        // tokenAirdropPool = balance - pendingTreasury (no storage)
        uint256 availableTokenPool = IERC20(token).balanceOf(address(this)) -
            pendingTreasury[token];
        if (totalTokenAmount > availableTokenPool) {
            revert Errors.IPWorld_InsufficientAirdropPool();
        }
        if (totalWethAmount > wethAirdropPool[token]) {
            revert Errors.IPWorld_InsufficientAirdropPool();
        }

        // Only deduct wethAirdropPool (token pool is balance-based, auto-deducted by transfer)
        wethAirdropPool[token] -= totalWethAmount;

        for (uint256 i = 0; i < length; ++i) {
            address recipient = recipients[i];
            if (recipient == address(0)) {
                revert Errors.IPWorld_InvalidAddress();
            }
            if (tokenAmounts[i] > 0)
                IERC20(token).transfer(recipient, tokenAmounts[i]);
            if (wethAmounts[i] > 0)
                IERC20(_weth).transfer(recipient, wethAmounts[i]);
            emit AirdropClaimed(
                token,
                recipient,
                tokenAmounts[i],
                wethAmounts[i]
            );
        }
    }

    ///
    /// Internal
    ///

    /// @notice Adds liquidity to a Uniswap V3 position within specified tick range as one-sided range
    /// @param token Address of the IP token to add as liquidity
    /// @param pool Uniswap V3 pool to add liquidity to
    /// @param tokenForLiquidity Amount of tokens to use for liquidity provision
    /// @param tickLower Lower tick boundary for the liquidity position
    /// @param tickUpper Upper tick boundary for the liquidity position
    function _addLiquidity(
        address token,
        IUniswapV3Pool pool,
        uint256 tokenForLiquidity,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        if (tokenForLiquidity == 0) return;
        bool nativeIsZero = _weth < token;
        // Store original ticks for event
        int24 originalTickLower = tickLower;
        int24 originalTickUpper = tickUpper;

        if (nativeIsZero) {
            (tickLower, tickUpper) = (-tickUpper, -tickLower);
        }
        uint160 lowerSqrtPriceX96 = tickLower.getSqrtRatioAtTick();
        uint160 upperSqrtPriceX96 = tickUpper.getSqrtRatioAtTick();
        uint128 liquidity;

        if (nativeIsZero) {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(
                lowerSqrtPriceX96,
                upperSqrtPriceX96,
                tokenForLiquidity
            );
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(
                lowerSqrtPriceX96,
                upperSqrtPriceX96,
                tokenForLiquidity
            );
        }
        if (liquidity == 0) return;

        bytes memory data = abi.encode(token);
        pool.mint(address(this), tickLower, tickUpper, liquidity, data);

        // Emit event with original tick values (before potential swap)
        emit LiquidityDeployed(
            token,
            address(pool),
            originalTickLower,
            originalTickUpper,
            liquidity,
            tokenForLiquidity
        );
    }

    /// @notice Collects all liquidity and fees from a specific tick range position
    /// @param pool Uniswap V3 pool to collect from
    /// @param tickLower Lower tick boundary of the position
    /// @param tickUpper Upper tick boundary of the position
    /// @param nativeIsZero Whether WETH is token0 in the pool
    /// @return wethAmount Amount of WETH collected
    /// @return tokenAmount Amount of IP tokens collected
    function _collectLiquidity(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        bool nativeIsZero
    ) internal returns (uint256 wethAmount, uint256 tokenAmount) {
        // Store original ticks for event
        int24 originalTickLower = tickLower;
        int24 originalTickUpper = tickUpper;

        if (nativeIsZero) {
            (tickLower, tickUpper) = (-tickUpper, -tickLower);
            pool.burn(tickLower, tickUpper, 0);
            (wethAmount, tokenAmount) = pool.collect(
                address(this),
                tickLower,
                tickUpper,
                type(uint128).max,
                type(uint128).max
            );
        } else {
            pool.burn(tickLower, tickUpper, 0);
            (tokenAmount, wethAmount) = pool.collect(
                address(this),
                tickLower,
                tickUpper,
                type(uint128).max,
                type(uint128).max
            );
        }

        emit LiquidityCollected(
            address(pool),
            originalTickLower,
            originalTickUpper,
            wethAmount,
            tokenAmount
        );
    }

    ///
    /// Uniswap v3 Callbacks
    ///

    /// @notice Transfers tokens to LP pool post-deployment via v3 mint callback
    /// @dev Accepts callbacks only from the 1% pool looked up via factory.
    /// @param amount0Owed Amount of token0 required for liquidity transfer
    /// @param amount1Owed Amount of token1 required for liquidity transfer
    /// @param data Additional data passed by the caller
    function storyHuntV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        address token = abi.decode(data, (address));

        // Accept callback only from the 1% pool
        address pool = _v3Factory.getPool(token, _weth, V3_FEE);
        if (msg.sender != pool || pool == address(0)) {
            revert Errors.IPWorld_OnlyLiquidityPool();
        }

        bool nativeIsZero = _weth < token;
        if (amount0Owed > 0) {
            IERC20(nativeIsZero ? _weth : token).transfer(
                msg.sender,
                amount0Owed
            );
        }
        if (amount1Owed > 0) {
            IERC20(nativeIsZero ? token : _weth).transfer(
                msg.sender,
                amount1Owed
            );
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @notice Ensures Story IPA NFTs can be received on registration
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
