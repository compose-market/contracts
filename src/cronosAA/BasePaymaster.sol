// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/* solhint-disable reason-string */

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PackedUserOperation
 * @notice ERC-4337 v0.7 UserOperation with packed gas fields
 */
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;      // verificationGasLimit (16 bytes) + callGasLimit (16 bytes)
    uint256 preVerificationGas;
    bytes32 gasFees;               // maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes)
    bytes paymasterAndData;
    bytes signature;
}

/**
 * @title IEntryPoint v0.7
 * @notice Minimal interface for v0.7 EntryPoint
 */
interface IEntryPointV07 {
    function depositTo(address account) external payable;
    function withdrawTo(address payable withdrawAddress, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function addStake(uint32 unstakeDelaySec) external payable;
    function unlockStake() external;
    function withdrawStake(address payable withdrawAddress) external;
}

/**
 * @title BasePaymaster
 * @notice Base implementation for ERC-4337 v0.7 Paymasters.
 * Handles deposit management and provides hooks for validation.
 */
abstract contract BasePaymaster is Ownable {
    IEntryPointV07 public immutable entryPoint;

    constructor(IEntryPointV07 _entryPoint) Ownable(msg.sender) {
        entryPoint = _entryPoint;
    }

    /// @notice Validate a UserOperation (called by EntryPoint)
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external virtual returns (bytes memory context, uint256 validationData);

    /// @notice Post-operation handler (v0.7 signature)
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external virtual {
        // Default: no-op
    }

    /// @notice Add stake to EntryPoint (for paymaster reputation)
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /// @notice Unlock stake (starts unstake delay)
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /// @notice Withdraw stake after delay
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    /// @notice Deposit to EntryPoint for gas payments
    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Withdraw from EntryPoint deposit
    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    ) external onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /// @notice Get current deposit balance
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /// @notice Validate sender is EntryPoint
    function _requireFromEntryPoint() internal view {
        require(msg.sender == address(entryPoint), "Sender not EntryPoint");
    }
}

/// @notice Post-operation mode enum (v0.7)
enum PostOpMode {
    opSucceeded,
    opReverted,
    postOpReverted
}
