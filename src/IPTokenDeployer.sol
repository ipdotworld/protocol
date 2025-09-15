// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIPTokenDeployer} from "./interfaces/IIPTokenDeployer.sol";
import {IPToken} from "./IPToken.sol";
import {Errors} from "./lib/Errors.sol";

/// @title IPTokenDeployer
/// @notice Factory contract for deploying IPToken instances to reduce IPWorld contract size
/// @dev Only callable by IPWorld, handles token deployment and initial supply transfer
contract IPTokenDeployer is IIPTokenDeployer {
    /// @notice Address of the IPWorld contract
    address public immutable ipWorld;

    /// @notice Initializes the deployer with IPWorld address
    /// @param ipWorld_ Address of the IPWorld contract
    constructor(address ipWorld_) {
        if (ipWorld_ == address(0)) {
            revert Errors.IPWorld_InvalidAddress();
        }
        ipWorld = ipWorld_;
    }

    /// @notice Restricts calls to only be made by IPWorld
    modifier onlyIPWorld() {
        if (msg.sender != ipWorld) {
            revert Errors.IPWorld_OperatorOnly();
        }
        _;
    }

    /// @inheritdoc IIPTokenDeployer
    function deployToken(
        address tokenCreator,
        address v3Deployer,
        address weth,
        uint256 bidWallAmount,
        uint256 antiSnipeDuration,
        string calldata name,
        string calldata symbol
    ) external onlyIPWorld returns (address token) {
        // Deploy the token - it will mint all tokens to this contract
        token = address(new IPToken(tokenCreator, v3Deployer, weth, bidWallAmount, antiSnipeDuration, name, symbol));

        // Transfer all tokens to IPWorld
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(ipWorld, balance);

        emit IPTokenDeployed(token, tokenCreator, name, symbol);
    }
}
