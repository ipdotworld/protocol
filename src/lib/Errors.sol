// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Errors Library
library Errors {
    ////////////////////////////////////////////////////////////////////////////
    //                               IPToken                                  //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Only liquidity pool can call this function
    error IPToken_OnlyLiquidityPool();

    /// @notice Transfer amount exceeds anti-snipe limit
    error IPToken_ExceedsAntiSnipeLimit();

    ////////////////////////////////////////////////////////////////////////////
    //                            IPWorld                                    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Caller is not the operator
    error IPWorld_OperatorOnly();

    /// @notice Wrong token
    error IPWorld_WrongToken();

    /// @notice tick is invalid
    error IPWorld_InvalidTick();

    /// @notice invalid address
    error IPWorld_InvalidAddress();

    /// @notice invalid share
    error IPWorld_InvalidShare();

    /// @notice invalid argument
    error IPWorld_InvalidArgument();

    /// @notice Only liquidity pool can call this function
    error IPWorld_OnlyLiquidityPool();

    /// @notice No pending recipient for this IP asset
    error IPWorld_NoPendingRecipient();

    /// @notice Caller is not the pending recipient
    error IPWorld_NotPendingRecipient();
    /// @notice Thrown when the caller is not the current recipient
    error IPWorld_NotCurrentRecipient();

    ////////////////////////////////////////////////////////////////////////////
    //                              IPOwnerVault                              //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Caller is not the IP World contract
    error IPOwnerVault_OnlyIpWorld();

    /// @notice Vesting duration is zero
    error IPOwnerVault_VestingDurationZero();

    /// @notice Invalid address
    error IPOwnerVault_InvalidAddress();

    /// @notice IP asset is not claimed
    error IPOwnerVault_IPAssetNotClaimed();

    /// @notice Vesting amount is zero
    error IPOwnerVault_VestingAmountZero();

    ////////////////////////////////////////////////////////////////////////////
    //                            Operator                                   //
    ////////////////////////////////////////////////////////////////////////////

    error Operator_InvalidAddress();

    /// @notice Only liquidity pool can call this function
    error Operator_OnlyLiquidityPool();

    /// @notice ERC2612 expired signature
    error Operator_ERC2612ExpiredSignature(uint256 deadline);

    /// @notice ERC2612 invalid signer
    error Operator_ERC2612InvalidSigner(address signer, address owner);
}
