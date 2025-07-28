// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILicensingModule} from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";

/// @title ILicensingModuleWithNFT
/// @notice Interface that extends ILicensingModule to include LICENSE_NFT getter
interface ILicensingModuleWithNFT is ILicensingModule {
    /// @notice Returns the License NFT contract address
    function LICENSE_NFT() external view returns (address);
}
