// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {IIPAssetRegistry} from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {SPGNFTLib} from "@storyprotocol/periphery/lib/SPGNFTLib.sol";

import {IIPWorld} from "../src/interfaces/IIPWorld.sol";
import {IIPOwnerVault} from "../src/interfaces/IIPOwnerVault.sol";

import {IPWorld} from "../src/IPWorld.sol";
import {IPOwnerVault} from "../src/IPOwnerVault.sol";
import {IPTokenDeployer} from "../src/IPTokenDeployer.sol";
import {Operator} from "../src/Operator.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";
import {Constants} from "../utils/Constants.sol";

/// @title Base Test Contract
contract BaseTest is Test {
    uint24 internal constant POOL_FEE = 3000; // 0.3%
    int24 internal constant TICK_SPACING = 60;
    int24 internal constant MAX_TICK = TickMath.MAX_TICK - (TickMath.MAX_TICK % TICK_SPACING);

    IWETH9 internal weth = IWETH9(Constants.WETH);
    IQuoterV2 internal quoterV2 = IQuoterV2(Constants.QUOTER_V2);
    IUniswapV3Factory internal v3Factory = IUniswapV3Factory(Constants.V3_FACTORY);
    address internal v3Deployer = Constants.V3_DEPLOYER;
    ISwapRouter internal swapRouter = ISwapRouter(Constants.SWAP_ROUTER);
    IIPAssetRegistry internal ipAssetRegistry = IIPAssetRegistry(Constants.IP_ASSET_REGISTRY);
    IRegistrationWorkflows internal registrationWorkflows = IRegistrationWorkflows(Constants.REGISTRATION_WORKFLOWS);
    address internal licenseAttachmentWorkflows = Constants.LICENSE_ATTACHMENT_WORKFLOWS;
    address internal licensingModule = Constants.LICENSING_MODULE;
    address internal licenseTemplate = Constants.PILICENSE_TEMPLATE;
    address internal treasury = Constants.TREASURY;
    uint64 internal vestingDuration = Constants.VESTING_DURATION;

    WorkflowStructs.IPMetadata internal ipMetadataEmpty;
    ISPGNFT internal spgNft;

    IIPWorld internal ipWorld;
    IIPOwnerVault internal ownerVault;
    Operator internal operator;

    int24[] internal startTickList = [-144_000, -120_000];
    uint256[] internal allocationList = [720_000, 250_000];

    // Test EOA addresses
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal cal = makeAddr("cal");

    /// @notice Sets up base testing contract
    function setUp() public virtual {
        // story protocol mainnet
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);
        address owner = address(this);

        ipMetadataEmpty =
            WorkflowStructs.IPMetadata({ipMetadataURI: "", ipMetadataHash: "", nftMetadataURI: "", nftMetadataHash: ""});

        address expectedIpWorldAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        ownerVault = IIPOwnerVault(
            address(
                new ERC1967Proxy(
                    address(new IPOwnerVault(expectedIpWorldAddress, vestingDuration)),
                    abi.encodeWithSelector(IPOwnerVault.initialize.selector, address(this))
                )
            )
        );

        // Deploy IPTokenDeployer before IPWorld
        IPTokenDeployer tokenDeployer = new IPTokenDeployer(expectedIpWorldAddress);

        ipWorld = IIPWorld(
            address(
                new ERC1967Proxy(
                    address(
                        new IPWorld(
                            address(weth),
                            v3Deployer,
                            address(v3Factory),
                            address(tokenDeployer),
                            address(ownerVault),
                            treasury,
                            500_000,
                            300_000,
                            500_000,
                            500 ether
                        )
                    ),
                    abi.encodeWithSelector(IPWorld.initialize.selector, address(this))
                )
            )
        );

        assertEq(address(ipWorld), expectedIpWorldAddress, "IPWorld address mismatch");

        // Manually set BaseTest as owner since reinitializer(2) doesn't set owner
        // Use the correct OwnableUpgradeable storage slot
        bytes32 ownableStorageSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        vm.store(address(ipWorld), ownableStorageSlot, bytes32(uint256(uint160(address(this)))));

        spgNft = ISPGNFT(
            registrationWorkflows.createCollection(
                ISPGNFT.InitParams({
                    name: Constants.NFT_NAME,
                    symbol: Constants.NFT_SYMBOL,
                    baseURI: Constants.NFT_BASE_URI,
                    contractURI: Constants.NFT_CONTRACT_URI,
                    maxSupply: type(uint32).max,
                    mintFee: 0,
                    mintFeeToken: address(0),
                    mintFeeRecipient: address(ipWorld),
                    owner: address(this),
                    mintOpen: true,
                    isPublicMinting: false
                })
            )
        );

        operator = new Operator(
            address(weth),
            address(ipWorld),
            v3Deployer,
            address(spgNft),
            0x4027fc996DB0EaC23470e82c0Ce5D00fee42c26B,
            Constants.LICENSING_URL
        );

        spgNft.grantRole(SPGNFTLib.MINTER_ROLE, address(operator));
        spgNft.grantRole(SPGNFTLib.ADMIN_ROLE, address(ipWorld));

        // Now BaseTest is the owner, so we can call setOperator directly
        ipWorld.setOperator(address(operator), true);

        // for deposits
        vm.deal(address(alice), 100 ether);
    }

    function swap(IUniswapV3Pool pool, uint256 value) internal {
        address token = pool.token0();
        if (token == address(weth)) {
            token = pool.token1();
        }
        pool.swap(
            msg.sender,
            !(token < address(weth)),
            int256(value),
            token < address(weth) ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1,
            ""
        );
    }

    function storyHuntV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external virtual {
        uint256 transferAmount = uint256(amount0Delta > 0 ? amount0Delta : amount1Delta);

        vm.deal(address(this), transferAmount);
        weth.deposit{value: transferAmount}();
        weth.transfer(msg.sender, transferAmount);
    }
}
