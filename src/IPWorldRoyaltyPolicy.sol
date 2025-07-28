// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IGraphAwareRoyaltyPolicy} from "./interfaces/storyprotocol/IGraphAwareRoyaltyPolicy.sol";

/// @title IPWorldRoyaltyPolicy
/// @notice Minimal external royalty policy for Story Protocol, always returns 3% royalty, does nothing on hooks.
/// @dev Upgradeable via UUPS, no storage, all logic offchain, for PIL commercialUse=true compliance.
contract IPWorldRoyaltyPolicy is IGraphAwareRoyaltyPolicy, Initializable, UUPSUpgradeable {
    /// @notice UUPS initializer
    function initialize() public initializer {}

    /// @notice No-op for license minting hook
    function onLicenseMinting(address, uint32, bytes calldata) external override {}

    /// @notice No-op for linking to parents hook
    function onLinkToParents(address, address[] calldata, address[] calldata, uint32[] calldata, bytes calldata)
        external
        pure
        override
        returns (uint32)
    {
        return 3000;
    }

    /// @notice Always returns 3% royalty for any ipId/ancestor
    function getPolicyRoyalty(address, address) external pure override returns (uint32) {
        return 3000;
    }

    /// @notice Always returns 0 (no onchain transfer tracking)
    function getTransferredTokens(address, address, address) external pure override returns (uint256) {
        return 0;
    }

    /// @notice No-op for transfer to vault, always returns 0
    function transferToVault(address, address, address) external pure override returns (uint256) {
        return 0;
    }

    /// @notice Always returns 3% royalty stack
    function getPolicyRoyaltyStack(address) external pure override returns (uint32) {
        return 3000;
    }

    /// @notice Always returns false (no group support)
    function isSupportGroup() external pure override returns (bool) {
        return false;
    }

    /// @notice Always returns 0 (no RTS required to link)
    function getPolicyRtsRequiredToLink(address, uint32) external pure override returns (uint32) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return interfaceId == type(IGraphAwareRoyaltyPolicy).interfaceId || interfaceId == bytes4(0x01ffc9a7)
            || interfaceId == bytes4(0xf2197fae);
    }

    /// @dev UUPS upgradeability authorization (dummy: unrestricted)
    function _authorizeUpgrade(address) internal override {}
}
