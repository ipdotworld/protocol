// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IP Token Deployer Interface
/// @notice Interface for deploying IP tokens on behalf of IPWorld
/// @dev This contract is responsible for deploying IPToken instances and transferring
///      the minted tokens to IPWorld, reducing IPWorld's contract size
interface IIPTokenDeployer {
    /// @notice Emitted when a new IP token is deployed
    /// @param token Address of the deployed IP token
    /// @param tokenCreator Address of the token creator
    /// @param name Token name
    /// @param symbol Token symbol
    event IPTokenDeployed(address indexed token, address indexed tokenCreator, string name, string symbol);

    /// @notice Deploys a new IP token and transfers all tokens to the caller
    /// @dev Only IPWorld can call this function. Mints total supply to deployer,
    ///      then transfers all tokens to msg.sender (IPWorld)
    /// @param tokenCreator Address of the original token creator/developer
    /// @param v3Deployer Address of the Uniswap V3 deployer for pool address computation
    /// @param weth Address of the Wrapped Ether contract for the trading pair
    /// @param bidWallAmount Fixed amount of ETH reserved for bid wall operations
    /// @param name ERC20 token name
    /// @param symbol ERC20 token symbol
    /// @return token Address of the deployed IP token
    function deployToken(
        address tokenCreator,
        address v3Deployer,
        address weth,
        uint256 bidWallAmount,
        string calldata name,
        string calldata symbol
    ) external returns (address token);

    /// @notice Returns the address of IPWorld contract
    /// @return Address of the IPWorld contract that can deploy tokens
    function ipWorld() external view returns (address);
}
