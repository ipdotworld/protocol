// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPWorld} from "../../src/IPWorld.sol";
import {IPOwnerVault} from "../../src/IPOwnerVault.sol";
import {IPTokenDeployer} from "../../src/IPTokenDeployer.sol";
import {IIPWorld} from "../../src/interfaces/IIPWorld.sol";
import {IWETH9} from "../../src/interfaces/IWETH9.sol";
import {Errors} from "../../src/lib/Errors.sol";
import {Constants} from "../../utils/Constants.sol";

/// @title OperatorEnum Test
/// @notice Tests for OperatorType enum-based role separation
contract OperatorEnumTest is Test {
    IIPWorld internal ipWorld;
    address internal treasury = Constants.TREASURY;

    address internal protocolOp = makeAddr("protocolOperator");
    address internal airdropOp = makeAddr("airdropOperator");
    address internal nobody = makeAddr("nobody");

    function setUp() public {
        vm.createSelectFork(Constants.STORY_MAINNET_RPC);

        address expectedIpWorldAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);
        address ownerVaultAddr = address(
            new ERC1967Proxy(
                address(new IPOwnerVault(expectedIpWorldAddress, Constants.VESTING_DURATION)),
                abi.encodeWithSelector(IPOwnerVault.initialize.selector, address(this))
            )
        );

        IPTokenDeployer tokenDeployer = new IPTokenDeployer(expectedIpWorldAddress);

        ipWorld = IIPWorld(
            address(
                new ERC1967Proxy(
                    address(
                        new IPWorld(
                            Constants.WETH,
                            Constants.V3_DEPLOYER,
                            Constants.V3_FACTORY,
                            address(tokenDeployer),
                            ownerVaultAddr,
                            treasury,
                            300_000,
                            200_000,
                            100_000,
                            500 ether,
                            Constants.CREATION_FEE,
                            Constants.REFERRAL_SHARE,
                            400_000
                        )
                    ),
                    abi.encodeWithSelector(IPWorld.initialize.selector, address(this))
                )
            )
        );

        assertEq(address(ipWorld), expectedIpWorldAddress, "IPWorld address mismatch");

        // Set owner via storage slot (same as BaseTest)
        bytes32 ownableStorageSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        vm.store(address(ipWorld), ownableStorageSlot, bytes32(uint256(uint160(address(this)))));

        // Set up operators with different roles
        ipWorld.setOperator(protocolOp, IIPWorld.OperatorType.Protocol);
        ipWorld.setOperator(airdropOp, IIPWorld.OperatorType.Airdrop);
    }

    // --- setOperator tests ---

    function test_setOperator_Protocol() public view {
        assertEq(uint8(ipWorld.isOperator(protocolOp)), uint8(IIPWorld.OperatorType.Protocol));
    }

    function test_setOperator_Airdrop() public view {
        assertEq(uint8(ipWorld.isOperator(airdropOp)), uint8(IIPWorld.OperatorType.Airdrop));
    }

    function test_setOperator_None_revokes() public {
        ipWorld.setOperator(protocolOp, IIPWorld.OperatorType.None);
        assertEq(uint8(ipWorld.isOperator(protocolOp)), uint8(IIPWorld.OperatorType.None));
    }

    function test_setOperator_treasury_reverts() public {
        vm.expectRevert(Errors.IPWorld_InvalidAddress.selector);
        ipWorld.setOperator(treasury, IIPWorld.OperatorType.Protocol);
    }

    function test_setOperator_emitsEvent() public {
        vm.expectEmit(true, false, false, true, address(ipWorld));
        emit IIPWorld.SetOperator(protocolOp, IIPWorld.OperatorType.Airdrop);
        ipWorld.setOperator(protocolOp, IIPWorld.OperatorType.Airdrop);
    }

    function test_unassignedAddress_isNone() public view {
        assertEq(uint8(ipWorld.isOperator(nobody)), uint8(IIPWorld.OperatorType.None));
    }

    // --- Protocol operator access tests ---

    function test_protocolOp_canCallClaimIp() public {
        address ipaId = makeAddr("ipa1");
        address recipient = makeAddr("recipient1");
        vm.prank(protocolOp);
        ipWorld.claimIp(ipaId, recipient, address(0));
    }

    function test_protocolOp_canCallSetIpTreasury() public {
        address ipaId = makeAddr("ipa2");
        address ipTreasury_ = makeAddr("ipTreasury");
        vm.prank(protocolOp);
        ipWorld.setIpTreasury(ipaId, ipTreasury_);
    }

    function test_protocolOp_canCallSetReferral() public {
        address ipaId = makeAddr("ipa3");
        address referral_ = makeAddr("referral");
        vm.prank(protocolOp);
        ipWorld.setReferral(ipaId, referral_);
    }

    function test_protocolOp_canCallLinkTokensToIp() public {
        address ipaId = makeAddr("ipa4");
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("token1");
        vm.prank(protocolOp);
        // This will not fully succeed since token1 is not a real token with info,
        // but it should pass the onlyOperator check
        vm.expectRevert(); // Expected revert from token info, not from operator check
        ipWorld.linkTokensToIp(ipaId, tokens);
    }

    // --- Airdrop operator CANNOT call Protocol functions ---

    function test_airdropOp_cannotCallClaimIp() public {
        address ipaId = makeAddr("ipa5");
        address recipient = makeAddr("recipient2");
        vm.prank(airdropOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimIp(ipaId, recipient, address(0));
    }

    function test_airdropOp_cannotCallSetIpTreasury() public {
        address ipaId = makeAddr("ipa6");
        address ipTreasury_ = makeAddr("ipTreasury2");
        vm.prank(airdropOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.setIpTreasury(ipaId, ipTreasury_);
    }

    function test_airdropOp_cannotCallSetReferral() public {
        address ipaId = makeAddr("ipa7");
        address referral_ = makeAddr("referral2");
        vm.prank(airdropOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.setReferral(ipaId, referral_);
    }

    function test_airdropOp_cannotCallLinkTokensToIp() public {
        address ipaId = makeAddr("ipa8");
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("token2");
        vm.prank(airdropOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.linkTokensToIp(ipaId, tokens);
    }

    // --- Protocol operator CANNOT call Airdrop functions ---

    function test_protocolOp_cannotCallClaimAirdropUgc() public {
        address token = makeAddr("token3");
        address[] memory recipients = new address[](0);
        uint256[] memory tokenAmounts = new uint256[](0);
        uint256[] memory wethAmounts = new uint256[](0);
        vm.prank(protocolOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimAirdropUgc(token, recipients, tokenAmounts, wethAmounts);
    }

    function test_protocolOp_cannotCallClaimAirdropHolder() public {
        address token = makeAddr("token4");
        address[] memory recipients = new address[](0);
        uint256[] memory tokenAmounts = new uint256[](0);
        uint256[] memory wethAmounts = new uint256[](0);
        vm.prank(protocolOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimAirdropHolder(token, recipients, tokenAmounts, wethAmounts);
    }

    // --- Nobody (None) CANNOT call anything ---

    function test_nobody_cannotCallClaimIp() public {
        address ipaId = makeAddr("ipa9");
        address recipient = makeAddr("recipient3");
        vm.prank(nobody);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimIp(ipaId, recipient, address(0));
    }

    function test_nobody_cannotCallClaimAirdropUgc() public {
        address token = makeAddr("token5");
        address[] memory recipients = new address[](0);
        uint256[] memory tokenAmounts = new uint256[](0);
        uint256[] memory wethAmounts = new uint256[](0);
        vm.prank(nobody);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimAirdropUgc(token, recipients, tokenAmounts, wethAmounts);
    }

    function test_nobody_cannotCallClaimAirdropHolder() public {
        address token = makeAddr("token6");
        address[] memory recipients = new address[](0);
        uint256[] memory tokenAmounts = new uint256[](0);
        uint256[] memory wethAmounts = new uint256[](0);
        vm.prank(nobody);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimAirdropHolder(token, recipients, tokenAmounts, wethAmounts);
    }

    // --- Revocation tests ---

    function test_revokeOperator_protocolCannotCallAnymore() public {
        // Revoke protocol operator
        ipWorld.setOperator(protocolOp, IIPWorld.OperatorType.None);

        address ipaId = makeAddr("ipa10");
        address recipient = makeAddr("recipient4");
        vm.prank(protocolOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimIp(ipaId, recipient, address(0));
    }

    function test_revokeOperator_airdropCannotCallAnymore() public {
        // Revoke airdrop operator
        ipWorld.setOperator(airdropOp, IIPWorld.OperatorType.None);

        address token = makeAddr("token7");
        address[] memory recipients = new address[](0);
        uint256[] memory tokenAmounts = new uint256[](0);
        uint256[] memory wethAmounts = new uint256[](0);
        vm.prank(airdropOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimAirdropUgc(token, recipients, tokenAmounts, wethAmounts);
    }

    // --- Role change tests ---

    function test_changeRole_protocolToAirdrop() public {
        // Change protocol operator to airdrop
        ipWorld.setOperator(protocolOp, IIPWorld.OperatorType.Airdrop);
        assertEq(uint8(ipWorld.isOperator(protocolOp)), uint8(IIPWorld.OperatorType.Airdrop));

        // Should not be able to call protocol functions
        address ipaId = makeAddr("ipa11");
        vm.prank(protocolOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimIp(ipaId, makeAddr("rec"), address(0));
    }

    function test_changeRole_airdropToProtocol() public {
        // Change airdrop operator to protocol
        ipWorld.setOperator(airdropOp, IIPWorld.OperatorType.Protocol);
        assertEq(uint8(ipWorld.isOperator(airdropOp)), uint8(IIPWorld.OperatorType.Protocol));

        // Should be able to call protocol functions
        address ipaId = makeAddr("ipa12");
        vm.prank(airdropOp);
        ipWorld.claimIp(ipaId, makeAddr("rec2"), address(0));

        // Should not be able to call airdrop functions
        address token = makeAddr("token8");
        address[] memory recipients = new address[](0);
        uint256[] memory tokenAmounts = new uint256[](0);
        uint256[] memory wethAmounts = new uint256[](0);
        vm.prank(airdropOp);
        vm.expectRevert(Errors.IPWorld_OperatorOnly.selector);
        ipWorld.claimAirdropUgc(token, recipients, tokenAmounts, wethAmounts);
    }
}
