// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IIPOwnerVault} from "./interfaces/IIPOwnerVault.sol";
import {IIPWorld} from "./interfaces/IIPWorld.sol";
import {Errors} from "./lib/Errors.sol";

/// @title IPOwnerVault
/// @notice Manages vesting and distribution of LP fees for IP owners
/// @dev Handles 3% token allocation and memecoin LP fees with 3-month vesting schedule. Upgradeable via UUPS.
contract IPOwnerVault is IIPOwnerVault, Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    IIPWorld public immutable ipWorld;

    /// @notice Amount of time each IP owner token allocation vests for
    uint64 public immutable vestingDuration;

    /// @notice Legacy address for contract migration compatibility
    address private legacy;

    /// @notice Amount of $IP awaiting for release
    mapping(address token => uint256 amount) public owdAmount;

    /// @notice IP world token vesting data
    mapping(address token => VestingData) private _vesting;

    /// @notice Initializes the IP Owner Vault with vesting parameters
    /// @param ipWorld_ Address of the IP World contract (only this contract can create vesting schedules)
    /// @param vestingDuration_ Duration in seconds for token vesting (must be > 0)
    constructor(address ipWorld_, uint64 vestingDuration_) {
        if (ipWorld_ == address(0)) {
            revert Errors.IPOwnerVault_InvalidAddress();
        }
        if (vestingDuration_ == 0) {
            revert Errors.IPOwnerVault_VestingDurationZero();
        }
        ipWorld = IIPWorld(ipWorld_);
        vestingDuration = vestingDuration_;
        _disableInitializers();
    }

    /// @notice Initializes the IPOwnerVault contract
    /// @param initialOwner Initial contract owner
    function initialize(address initialOwner) public initializer {
        _transferOwnership(initialOwner);
    }

    modifier onlyIpWorld() {
        if (msg.sender != address(ipWorld)) {
            revert Errors.IPOwnerVault_OnlyIpWorld();
        }
        _;
    }

    ///
    /// Getters
    ///

    /// @notice Tracks vesting data for a token
    function vesting(address token) external view returns (VestingData memory) {
        return _vesting[token];
    }

    ///
    /// Vesting triggers
    ///

    function createVestingOnTokenDeploy(address token) external onlyIpWorld {
        uint256 amountToVest = IERC20(token).balanceOf(address(this));
        _createVesting(token, amountToVest);
    }

    function distributeOwdAmount(address token) external payable {
        if (msg.value == 0) return;
        owdAmount[token] += msg.value;
        emit EthDeposited(token, msg.value);
    }

    function claim(address token) external {
        address recipient = ipWorld.getTokenIpRecipient(token);
        if (recipient == address(0)) {
            revert Errors.IPOwnerVault_IPAssetNotClaimed();
        }

        _release(token, recipient);
    }

    ///
    /// Vesting logic
    ///

    function remaining(address token) external view returns (uint256) {
        return _vesting[token].remaining;
    }

    function released(address token) public view returns (uint256) {
        return _vesting[token].released;
    }

    function releasable(address token) public view returns (uint256) {
        return _vestingSchedule(token, uint64(block.timestamp)) - released(token);
    }

    function vestedAmount(address token, uint64 timestamp) external view returns (uint256) {
        return _vestingSchedule(token, timestamp);
    }

    function _createVesting(address token, uint256 amount) private {
        if (amount == 0) revert Errors.IPOwnerVault_VestingAmountZero();
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = startTime + vestingDuration;

        _vesting[token] = VestingData({isSet: true, start: startTime, end: endTime, remaining: amount, released: 0});

        emit VestingScheduleCreated(token, amount, startTime, endTime);
    }

    function _release(address token, address recipient) private {
        uint256 amount = releasable(token);
        uint256 remainingAmount = _vesting[token].remaining;
        _vesting[token].remaining = remainingAmount - amount;
        _vesting[token].released += amount;
        emit ReleasedVested(token, amount);
        IERC20(token).safeTransfer(recipient, IERC20(token).balanceOf(address(this)) + amount - remainingAmount);

        uint256 owdAmountToRelease = owdAmount[token];
        if (owdAmountToRelease > 0) {
            owdAmount[token] = 0;
            (bool success,) = recipient.call{value: owdAmountToRelease}("");
            if (!success) revert();
        }

        // Emit combined event if either tokens or ETH were claimed
        if (amount > 0 || owdAmountToRelease > 0) {
            emit VestedTokensAndEthClaimed(token, recipient, amount, owdAmountToRelease);
        }
    }

    /// @dev Linear vesting, no cliff
    function _vestingSchedule(address token, uint64 timestamp) internal view returns (uint256) {
        uint256 totalAllocation = _vesting[token].remaining + _vesting[token].released;
        if (timestamp < _vesting[token].start) {
            return 0;
        } else if (timestamp >= _vesting[token].end) {
            return totalAllocation;
        } else {
            uint256 duration = _vesting[token].end - _vesting[token].start;
            return (totalAllocation * (timestamp - _vesting[token].start)) / duration;
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}
}
