// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, Vm, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
/// @notice Aeneid QuoterV2 uses non-struct parameters and returns only amountIn
interface IAeneidQuoterV2 {
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amount,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);
}
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {SPGNFTLib} from "@storyprotocol/periphery/lib/SPGNFTLib.sol";
import {IIPWorld} from "../../src/interfaces/IIPWorld.sol";
import {IIPToken} from "../../src/interfaces/IIPToken.sol";
import {Operator} from "../../src/Operator.sol";
import {IWETH9} from "../../src/interfaces/IWETH9.sol";
import {Constants} from "../../utils/Constants.sol";

/// @title Fork Simulation Test
/// @notice Simulates daily trading to measure economic metrics at FDV milestones
contract ForkSimulationTest is Test {
    uint24 internal constant POOL_FEE = 10000;
    int24 internal constant TICK_SPACING = 200;
    int24 internal constant MAX_TICK = TickMath.MAX_TICK - (TickMath.MAX_TICK % TICK_SPACING);

    // 1 IP = $1.5 USD (in 1e18 precision)
    uint256 internal constant IP_PRICE_USD = 15e17;

    IWETH9 internal weth = IWETH9(Constants.WETH);
    IAeneidQuoterV2 internal quoterV2 = IAeneidQuoterV2(Constants.QUOTER_V2_AENEID);
    IUniswapV3Factory internal v3Factory = IUniswapV3Factory(Constants.V3_FACTORY_AENEID);
    address internal v3Deployer = Constants.V3_DEPLOYER_AENEID;
    ISwapRouter internal swapRouter = ISwapRouter(Constants.SWAP_ROUTER_AENEID);

    IIPWorld internal ipWorld;
    Operator internal operator;
    ISPGNFT internal spgNft;

    address internal alice = makeAddr("alice");
    address internal trader = makeAddr("trader");

    int24[] internal startTickList = [-136_000, -112_000, -56_000];
    uint256[] internal allocationList = [760_000, 200_000, 10_000];

    struct MilestoneData {
        uint256 targetUsd;
        uint256 day;
        uint256 wethInPool;
        bool reached;
        HarvestStats harvestSnapshot;
        uint256 cumBuyVolume;
        uint256 cumSellVolume;
    }

    struct HarvestStats {
        uint256 totalWethCollected;
        uint256 totalTokensCollected;
        uint256 totalWethToBuyback;
        uint256 totalWethToIpOwner;
        uint256 totalTokenToIpTreasury;
        uint256 totalTokenToUgc;
        uint256 totalWethToUgc;
        uint256 harvestCount;
    }

    HarvestStats internal harvestStats;

    function setUp() public {
        vm.createSelectFork(Constants.STORY_TESTNET_RPC);

        ipWorld = IIPWorld(Constants.IPWORLD_AENEID);

        bytes32 ownableStorageSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        address ipWorldOwner = address(uint160(uint256(vm.load(address(ipWorld), ownableStorageSlot))));

        spgNft = ISPGNFT(Constants.SPG_NFT_AENEID);

        operator = new Operator(
            address(weth),
            address(ipWorld),
            Constants.V3_DEPLOYER_AENEID,
            Constants.SPG_NFT_AENEID,
            Constants.ROYALTY_POLICY_AENEID,
            Constants.LICENSING_URL
        );

        vm.startPrank(ipWorldOwner);
        spgNft.grantRole(SPGNFTLib.MINTER_ROLE, address(operator));
        spgNft.grantRole(SPGNFTLib.ADMIN_ROLE, address(ipWorld));
        ipWorld.setOperator(address(operator), true);
        vm.stopPrank();
    }

    function storyHuntV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        uint256 transferAmount = uint256(amount0Delta > 0 ? amount0Delta : amount1Delta);
        vm.deal(address(this), transferAmount);
        weth.deposit{value: transferAmount}();
        weth.transfer(msg.sender, transferAmount);
    }

    // ──────────────────────────────────────────────
    //  Math: max(5 * fdv_m^0.4, 1)
    // ──────────────────────────────────────────────

    /// @notice Returns max(5 * x^0.4, 0.1) in 1e18 precision
    /// @param x_1e18  fdv_m in 1e18 (e.g., 10e18 means fdv_m = 10)
    /// @return result in 1e18 (e.g., 12.56e18 means multiplier = 12.56)
    function volumeMultiplier(uint256 x_1e18) internal pure returns (uint256) {
        // Precomputed anchors for f(x) = 5 * x^0.4:
        //   x=0.0003 -> 0.100   x=0.001 -> 0.316   x=0.003 -> 0.467
        //   x=0.01   -> 0.793   x=0.03  -> 1.173   x=0.1   -> 1.990
        //   x=0.3    -> 2.944   x=1     -> 5.000   x=3     -> 7.397
        //   x=10     -> 12.560  x=30    -> 18.58    x=100   -> 31.55

        if (x_1e18 <= 3e14) return 1e17; // clamp to 0.1

        if (x_1e18 <= 1e15) {
            // [0.0003, 0.001]
            return 1e17 + ((x_1e18 - 3e14) * (316e15 - 1e17)) / (1e15 - 3e14);
        }
        if (x_1e18 <= 3e15) {
            // [0.001, 0.003]
            return 316e15 + ((x_1e18 - 1e15) * (467e15 - 316e15)) / (3e15 - 1e15);
        }
        if (x_1e18 <= 1e16) {
            // [0.003, 0.01]
            return 467e15 + ((x_1e18 - 3e15) * (793e15 - 467e15)) / (1e16 - 3e15);
        }
        if (x_1e18 <= 3e16) {
            // [0.01, 0.03]
            return 793e15 + ((x_1e18 - 1e16) * (1173e15 - 793e15)) / (3e16 - 1e16);
        }
        if (x_1e18 <= 1e17) {
            // [0.03, 0.1]
            return 1173e15 + ((x_1e18 - 3e16) * (199e16 - 1173e15)) / (1e17 - 3e16);
        }
        if (x_1e18 <= 3e17) {
            // [0.1, 0.3]
            return 199e16 + ((x_1e18 - 1e17) * (2944e15 - 199e16)) / (3e17 - 1e17);
        }
        if (x_1e18 <= 1e18) {
            // [0.3, 1]
            return 2944e15 + ((x_1e18 - 3e17) * (5e18 - 2944e15)) / (1e18 - 3e17);
        }
        if (x_1e18 <= 3e18) {
            // [1, 3]
            return 5e18 + ((x_1e18 - 1e18) * (7397e15 - 5e18)) / (3e18 - 1e18);
        }
        if (x_1e18 <= 10e18) {
            // [3, 10]
            return 7397e15 + ((x_1e18 - 3e18) * (1256e16 - 7397e15)) / (10e18 - 3e18);
        }
        if (x_1e18 <= 30e18) {
            // [10, 30]
            return 1256e16 + ((x_1e18 - 10e18) * (1858e16 - 1256e16)) / (30e18 - 10e18);
        }
        if (x_1e18 <= 100e18) {
            // [30, 100]
            return 1858e16 + ((x_1e18 - 30e18) * (3155e16 - 1858e16)) / (100e18 - 30e18);
        }
        // [100, 1000]
        return 3155e16 + ((x_1e18 - 100e18) * (7925e16 - 3155e16)) / (900e18);
    }

    // ──────────────────────────────────────────────
    //  Market Cap & Liquidity helpers
    // ──────────────────────────────────────────────

    function getMarketCapWeth(IERC20Metadata token) internal returns (uint256) {
        uint256 totalSupply = token.totalSupply();
        uint256 decimals = token.decimals();
        try quoterV2.quoteExactOutputSingle(
            address(weth), address(token), POOL_FEE, 10 ** decimals, 0
        ) returns (uint256 amountIn) {
            return FullMath.mulDiv(amountIn, totalSupply, 10 ** decimals);
        } catch {
            return 0;
        }
    }

    /// @return FDV in USD as whole dollars (no decimals)
    function getMarketCapUsd(IERC20Metadata token) internal returns (uint256) {
        uint256 mcWeth = getMarketCapWeth(token);
        // mcWeth is in wei (1e18). USD = mcWeth * 1.5 / 1e18
        return FullMath.mulDiv(mcWeth, IP_PRICE_USD, 1e18);
    }

    // ──────────────────────────────────────────────
    //  Swap helpers with retry (binary-search fallback)
    // ──────────────────────────────────────────────

    /// @notice Buy tokens with WETH. Retries with halved amounts if swap reverts.
    /// @return amountSpent actual WETH spent
    function doBuy(address tokenAddr, uint256 targetWeth) internal returns (uint256 amountSpent) {
        uint256 amount = targetWeth;
        for (uint256 i; i < 12; ++i) {
            if (amount == 0) return 0;
            vm.deal(trader, amount);
            vm.prank(trader);
            weth.deposit{value: amount}();
            vm.prank(trader);
            try swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(weth),
                    tokenOut: tokenAddr,
                    fee: POOL_FEE,
                    recipient: trader,
                    deadline: block.timestamp + 1000,
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            ) {
                return amount;
            } catch {
                // Refund unused WETH
                vm.prank(trader);
                uint256 bal = weth.balanceOf(trader);
                if (bal > 0) {
                    weth.withdraw(bal);
                }
                amount /= 2;
            }
        }
        return 0;
    }

    /// @notice Sell tokens for exact WETH output. Retries with halved target.
    /// @return amountReceived actual WETH received
    function doSell(address tokenAddr, uint256 targetWeth) internal returns (uint256 amountReceived) {
        uint256 target = targetWeth;
        uint256 tokenBal = IERC20(tokenAddr).balanceOf(trader);
        if (tokenBal == 0) return 0;

        for (uint256 i; i < 12; ++i) {
            if (target == 0) return 0;
            vm.prank(trader);
            try swapRouter.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: tokenAddr,
                    tokenOut: address(weth),
                    fee: POOL_FEE,
                    recipient: trader,
                    deadline: block.timestamp + 1000,
                    amountOut: target,
                    amountInMaximum: tokenBal,
                    sqrtPriceLimitX96: 0
                })
            ) {
                return target;
            } catch {
                target /= 2;
            }
        }
        return 0;
    }

    // ──────────────────────────────────────────────
    //  Harvest helper with event logging
    // ──────────────────────────────────────────────

    function _harvestAndLog(address token, HarvestStats storage stats) internal {
        vm.recordLogs();
        ipWorld.harvest(token);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 harvestDistributedTopic =
            keccak256("HarvestDistributed(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256)");

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == harvestDistributedTopic) {
                (
                    uint256 tokenCollected,
                    uint256 tokenToIpTreasury,
                    uint256 tokenToUgc,
                    uint256 wethCollected,
                    uint256 wethToIpOwner,
                    uint256 wethToBuyback,
                    uint256 wethToUgc
                ) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256, uint256, uint256));

                stats.totalWethCollected += wethCollected;
                stats.totalTokensCollected += tokenCollected;
                stats.totalWethToBuyback += wethToBuyback;
                stats.totalWethToIpOwner += wethToIpOwner;
                stats.totalTokenToIpTreasury += tokenToIpTreasury;
                stats.totalTokenToUgc += tokenToUgc;
                stats.totalWethToUgc += wethToUgc;
                stats.harvestCount++;

                if (wethCollected > 0 || tokenCollected > 0) {
                    console2.log("    harvest: weth=", wethCollected / 1e18, "token=", tokenCollected / 1e18);
                    console2.log("      buyback=", wethToBuyback / 1e18, "ipOwner=", wethToIpOwner / 1e18);
                }
                break;
            }
        }
    }

    // ──────────────────────────────────────────────
    //  Main simulation test
    // ──────────────────────────────────────────────

    function test_ForkSimulation() public {
        console2.log("\n=== Starting Fork Simulation ===\n");

        // ── Create token ──
        vm.deal(address(operator), Constants.CREATION_FEE);
        vm.prank(address(operator));
        (, address tokenAddr) = ipWorld.createIpToken{value: Constants.CREATION_FEE}(
            alice, "MEME", "Test Token", address(0), startTickList, allocationList, false
        );
        IERC20Metadata token = IERC20Metadata(tokenAddr);
        console2.log("Token:", tokenAddr);

        // ── Initial metrics ──
        uint256 startFdvWeth = getMarketCapWeth(token);
        uint256 startFdvUsd = getMarketCapUsd(token);
        console2.log("\n--- Initial Metrics ---");
        console2.log("Start FDV (WETH):", startFdvWeth / 1e18);
        console2.log("Start FDV (USD):", startFdvUsd / 1e18);

        // ── Acquisition costs (quote only) ──
        uint256 cost80Weth = _quoteCost(token, 80);
        uint256 cost85Weth = _quoteCost(token, 85);
        uint256 cost90Weth = _quoteCost(token, 90);
        console2.log("Cost 80% (WETH):", cost80Weth / 1e18);
        console2.log("Cost 80% (USD):", FullMath.mulDiv(cost80Weth, IP_PRICE_USD, 1e18) / 1e18);
        console2.log("Cost 85% (WETH):", cost85Weth / 1e18);
        console2.log("Cost 85% (USD):", FullMath.mulDiv(cost85Weth, IP_PRICE_USD, 1e18) / 1e18);
        console2.log("Cost 90% (WETH):", cost90Weth / 1e18);
        console2.log("Cost 90% (USD):", FullMath.mulDiv(cost90Weth, IP_PRICE_USD, 1e18) / 1e18);

        // ── Setup trader approvals ──
        vm.startPrank(trader);
        weth.approve(address(swapRouter), type(uint256).max);
        IERC20(tokenAddr).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // ── Milestones ──
        uint256[6] memory targets = [uint256(1_000_000), 5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000];
        MilestoneData[6] memory ms;
        for (uint256 i; i < 6; ++i) {
            ms[i].targetUsd = targets[i];
        }
        uint256 nextMs;

        // ── Daily loop ──
        console2.log("\n--- Daily Simulation ---\n");
        uint256 day;
        uint256 cumBuyVol;
        uint256 cumSellVol;

        while (nextMs < 6 && day < 3650) {
            ++day;
            vm.warp(block.timestamp + 1 days);

            // Current FDV
            uint256 fdvUsd = getMarketCapUsd(token); // in 1e18 format (USD)
            uint256 fdvM_1e18 = fdvUsd / 1e6;

            // Volume multiplier: max(5 * fdv_m^0.4, 0.1) in 1e18
            uint256 mult = volumeMultiplier(fdvM_1e18);

            // Daily volume split into 20 rounds
            uint256 roundBuyWeth = FullMath.mulDiv(mult * 1_010_000, 1e18, IP_PRICE_USD * 20);
            uint256 roundSellWeth = FullMath.mulDiv(mult * 990_000, 1e18, IP_PRICE_USD * 20);

            // Debug: daily start info
            {
                address _pool = IIPToken(tokenAddr).liquidityPool();
                console2.log("Day:", day, "FDV $:", fdvUsd / 1e18);
                console2.log("  mult(e15):", mult / 1e15, "roundBuy:", roundBuyWeth / 1e18);
                console2.log("  roundSell:", roundSellWeth / 1e18, "poolWETH:", weth.balanceOf(_pool) / 1e18);
            }

            // Execute 20 rounds of buy -> sell, checking milestones each round
            for (uint256 r; r < 20 && nextMs < 6; ++r) {
                uint256 bought = doBuy(tokenAddr, roundBuyWeth);
                cumBuyVol += bought;
                _harvestAndLog(tokenAddr, harvestStats);
                uint256 sold = doSell(tokenAddr, roundSellWeth);
                cumSellVol += sold;
                _harvestAndLog(tokenAddr, harvestStats);

                uint256 poolAfter = weth.balanceOf(IIPToken(tokenAddr).liquidityPool());

                uint256 roundFdvUsd = getMarketCapUsd(token) / 1e18;
                console2.log("  r:", r, "FDV$:", roundFdvUsd);
                console2.log("    poolW:", poolAfter / 1e18);

                // Check milestones after each round
                while (nextMs < 6 && roundFdvUsd >= ms[nextMs].targetUsd) {
                    ms[nextMs].day = day;
                    ms[nextMs].wethInPool = poolAfter;
                    ms[nextMs].reached = true;
                    ms[nextMs].harvestSnapshot = harvestStats;
                    ms[nextMs].cumBuyVolume = cumBuyVol;
                    ms[nextMs].cumSellVolume = cumSellVol;
                    console2.log("  ** Milestone $M:", ms[nextMs].targetUsd / 1_000_000);
                    ++nextMs;
                }
            }

            // Progress log every 50 days
            if (day % 50 == 0) {
                uint256 logFdv = getMarketCapUsd(token) / 1e18;
                console2.log("Day:", day, " FDV $:", logFdv);
            }
        }

        // ── Summary ──
        console2.log("\n\n========== Simulation Results ==========");
        console2.log("Config: [-136000, -112000, -56000] / [76%, 20%, 1%]");
        console2.log("Start FDV (USD):", startFdvUsd / 1e18, " | (WETH):", startFdvWeth / 1e18);
        console2.log(
            "Cost 80% (USD):", FullMath.mulDiv(cost80Weth, IP_PRICE_USD, 1e18) / 1e18, " | (WETH):", cost80Weth / 1e18
        );
        console2.log(
            "Cost 85% (USD):", FullMath.mulDiv(cost85Weth, IP_PRICE_USD, 1e18) / 1e18, " | (WETH):", cost85Weth / 1e18
        );
        console2.log(
            "Cost 90% (USD):", FullMath.mulDiv(cost90Weth, IP_PRICE_USD, 1e18) / 1e18, " | (WETH):", cost90Weth / 1e18
        );

        // ── Per-milestone cumulative report ──
        console2.log("\n--- Per-Milestone Cumulative ---");
        for (uint256 i; i < 6; ++i) {
            if (ms[i].reached) {
                uint256 tvlUsd = FullMath.mulDiv(ms[i].wethInPool * 2, IP_PRICE_USD, 1e18);
                // tvlUsd is in 1e18, targetUsd is raw. Normalize: (tvlUsd/1e18) * 10000 / targetUsd
                uint256 tvlFdvBps = ms[i].targetUsd > 0 ? (tvlUsd / 1e18 * 10000) / ms[i].targetUsd : 0;
                HarvestStats memory h = ms[i].harvestSnapshot;
                uint256 wethCollectedUsd = FullMath.mulDiv(h.totalWethCollected, IP_PRICE_USD, 1e18);
                uint256 buyVolUsd = FullMath.mulDiv(ms[i].cumBuyVolume, IP_PRICE_USD, 1e18);
                uint256 sellVolUsd = FullMath.mulDiv(ms[i].cumSellVolume, IP_PRICE_USD, 1e18);
                uint256 totalVolUsd = buyVolUsd + sellVolUsd;
                console2.log("=== FDV $M:", ms[i].targetUsd / 1_000_000, "| Day:", ms[i].day);
                console2.log("  Pool WETH:", ms[i].wethInPool / 1e18, "| TVL $:", tvlUsd / 1e18);
                console2.log("  TVL/FDV bps:", tvlFdvBps);
                console2.log("  Buy Vol:", ms[i].cumBuyVolume / 1e18, "| Sell Vol:", ms[i].cumSellVolume / 1e18);
                console2.log("  Total Vol ($):", totalVolUsd / 1e18);
                console2.log("  [Harvest Cumulative] count:", h.harvestCount);
                console2.log("    WETH collected:", h.totalWethCollected / 1e18, "($)", wethCollectedUsd / 1e18);
                console2.log("    Tokens collected:", h.totalTokensCollected / 1e18);
                console2.log("    WETH buyback:", h.totalWethToBuyback / 1e18);
                console2.log("    WETH ipOwner:", h.totalWethToIpOwner / 1e18);
                console2.log("    WETH ugc:", h.totalWethToUgc / 1e18);
                console2.log("    Token treasury:", h.totalTokenToIpTreasury / 1e18);
                console2.log("    Token ugc:", h.totalTokenToUgc / 1e18);
            } else {
                console2.log("=== FDV $M NOT reached:", ms[i].targetUsd / 1_000_000, "===");
            }
        }

        // ── Per-milestone incremental report ──
        console2.log("\n--- Per-Milestone Incremental (Delta) ---");
        HarvestStats memory prev;
        uint256 prevWethInPool;
        uint256 prevDay;
        uint256 prevBuyVol;
        uint256 prevSellVol;
        for (uint256 i; i < 6; ++i) {
            if (ms[i].reached) {
                HarvestStats memory h = ms[i].harvestSnapshot;
                uint256 dHarvests = h.harvestCount - prev.harvestCount;
                uint256 dWethCollected = h.totalWethCollected - prev.totalWethCollected;
                uint256 dTokensCollected = h.totalTokensCollected - prev.totalTokensCollected;
                uint256 dWethBuyback = h.totalWethToBuyback - prev.totalWethToBuyback;
                uint256 dWethIpOwner = h.totalWethToIpOwner - prev.totalWethToIpOwner;
                uint256 dWethUgc = h.totalWethToUgc - prev.totalWethToUgc;
                uint256 dTokenTreasury = h.totalTokenToIpTreasury - prev.totalTokenToIpTreasury;
                uint256 dTokenUgc = h.totalTokenToUgc - prev.totalTokenToUgc;
                uint256 dPoolWeth = ms[i].wethInPool / 1e18 - prevWethInPool;
                uint256 dDays = ms[i].day - prevDay;
                uint256 dBuyVol = ms[i].cumBuyVolume - prevBuyVol;
                uint256 dSellVol = ms[i].cumSellVolume - prevSellVol;
                uint256 dTotalVolUsd = FullMath.mulDiv(dBuyVol + dSellVol, IP_PRICE_USD, 1e18);

                console2.log("=== $M:", ms[i].targetUsd / 1_000_000, "| +days:", dDays);
                console2.log("  +Pool WETH:", dPoolWeth);
                console2.log("  +Buy Vol:", dBuyVol / 1e18, "| +Sell Vol:", dSellVol / 1e18);
                console2.log("  +Total Vol ($):", dTotalVolUsd / 1e18);
                console2.log("  +harvests:", dHarvests);
                console2.log("  +WETH collected:", dWethCollected / 1e18);
                console2.log("  +Tokens collected:", dTokensCollected / 1e18);
                console2.log("  +WETH buyback:", dWethBuyback / 1e18);
                console2.log("  +WETH ipOwner:", dWethIpOwner / 1e18);
                console2.log("  +WETH ugc:", dWethUgc / 1e18);
                console2.log("  +Token treasury:", dTokenTreasury / 1e18);
                console2.log("  +Token ugc:", dTokenUgc / 1e18);

                prev = h;
                prevWethInPool = ms[i].wethInPool / 1e18;
                prevDay = ms[i].day;
                prevBuyVol = ms[i].cumBuyVolume;
                prevSellVol = ms[i].cumSellVolume;
            }
        }

        // ── Grand total ──
        console2.log("\n========================================");
        console2.log("--- Grand Total ---");
        uint256 grandBuyUsd = FullMath.mulDiv(cumBuyVol, IP_PRICE_USD, 1e18);
        uint256 grandSellUsd = FullMath.mulDiv(cumSellVol, IP_PRICE_USD, 1e18);
        console2.log("Total Buy Vol:", cumBuyVol / 1e18, "($)", grandBuyUsd / 1e18);
        console2.log("Total Sell Vol:", cumSellVol / 1e18, "($)", grandSellUsd / 1e18);
        console2.log("Total Vol ($):", (grandBuyUsd + grandSellUsd) / 1e18);
        console2.log("Net Buy (WETH):", (cumBuyVol - cumSellVol) / 1e18);
        console2.log("Total Harvests:", harvestStats.harvestCount);
        console2.log("Total WETH Collected:", harvestStats.totalWethCollected / 1e18);
        uint256 totalWethUsd = FullMath.mulDiv(harvestStats.totalWethCollected, IP_PRICE_USD, 1e18);
        console2.log("Total WETH Collected ($):", totalWethUsd / 1e18);
        console2.log("Total Tokens Collected:", harvestStats.totalTokensCollected / 1e18);
        console2.log("Total WETH to Buyback:", harvestStats.totalWethToBuyback / 1e18);
        console2.log("Total WETH to IP Owner:", harvestStats.totalWethToIpOwner / 1e18);
        console2.log("Total Tokens to IP Treasury:", harvestStats.totalTokenToIpTreasury / 1e18);
        console2.log("Total WETH to UGC Airdrop:", harvestStats.totalWethToUgc / 1e18);
        console2.log("Total Tokens to UGC Airdrop:", harvestStats.totalTokenToUgc / 1e18);
        console2.log("========================================");
    }

    function _quoteCost(IERC20Metadata token, uint256 pct) internal returns (uint256) {
        uint256 totalSupply = token.totalSupply();
        uint256 target = (totalSupply * pct) / 100;
        try quoterV2.quoteExactOutputSingle(
            address(weth), address(token), POOL_FEE, target, 0
        ) returns (uint256 amountIn) {
            return amountIn;
        } catch {
            return type(uint256).max;
        }
    }
}
