// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/* solhint-disable reason-string */
/* solhint-disable no-inline-assembly */

import "./BasePaymaster.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Paymaster
 * @notice ERC-4337 v0.7 Paymaster that sponsors gas for verified users.
 * Uses ECDSA signature verification - our server signs approval for each UserOp.
 * 
 * Flow:
 * 1. User builds PackedUserOperation with callData
 * 2. Frontend requests paymaster signature from Lambda
 * 3. Lambda verifies user intent, signs paymasterAndData
 * 4. PackedUserOperation submitted to EntryPoint
 * 5. This contract verifies server signature → sponsors gas
 * 
 * @dev Based on eth-infinitism VerifyingPaymaster pattern (v0.7).
 *      Uses packed gas fields (accountGasLimits, gasFees).
 */
contract Paymaster is BasePaymaster {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @notice Address authorized to sign paymaster approvals
    address public verifyingSigner;

    /// @notice Emitted when signer is updated
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @notice Constructor
    /// @param _entryPoint The EntryPoint v0.7 contract
    /// @param _verifyingSigner Address that signs paymaster approvals (server wallet)
    constructor(
        IEntryPointV07 _entryPoint,
        address _verifyingSigner
    ) BasePaymaster(_entryPoint) {
        require(_verifyingSigner != address(0), "Invalid signer");
        verifyingSigner = _verifyingSigner;
        emit SignerUpdated(address(0), _verifyingSigner);
    }

    /// @notice Update the verifying signer (owner only)
    function setVerifyingSigner(address _newSigner) external onlyOwner {
        require(_newSigner != address(0), "Invalid signer");
        emit SignerUpdated(verifyingSigner, _newSigner);
        verifyingSigner = _newSigner;
    }

    /**
     * @notice Validate a paymaster UserOp (v0.7)
     * @dev Called by EntryPoint during validation phase
     * 
     * paymasterAndData format (v0.7):
     * [0:20]   - paymaster address (this contract)
     * [20:36]  - paymasterVerificationGasLimit (uint128, 16 bytes)
     * [36:52]  - paymasterPostOpGasLimit (uint128, 16 bytes)
     * [52:58]  - validUntil (uint48, 6 bytes)
     * [58:64]  - validAfter (uint48, 6 bytes)
     * [64:129] - signature (65 bytes)
     * 
     * @param userOp The PackedUserOperation
     * @param userOpHash Hash of the UserOperation (without signature)
     * @param maxCost Maximum gas cost that paymaster may be charged
     * @return context Data to pass to postOp (empty for this impl)
     * @return validationData Packed validation data (aggregator, validUntil, validAfter)
     */
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
        _requireFromEntryPoint();

        // Ensure sufficient deposit
        require(getDeposit() >= maxCost, "Paymaster: insufficient deposit");

        // Parse paymasterAndData (v0.7 format)
        // Skip first 52 bytes: paymaster(20) + pmVerificationGas(16) + pmPostOpGas(16)
        require(userOp.paymasterAndData.length >= 129, "Paymaster: invalid data length");

        uint48 validUntil = uint48(bytes6(userOp.paymasterAndData[52:58]));
        uint48 validAfter = uint48(bytes6(userOp.paymasterAndData[58:64]));
        bytes memory signature = userOp.paymasterAndData[64:129];

        // Build hash that server signed
        bytes32 hash = getHash(userOp, validUntil, validAfter);

        // Verify signature
        address signer = hash.toEthSignedMessageHash().recover(signature);
        
        if (signer != verifyingSigner) {
            // Return signature failure (validationData = 1 means SIG_VALIDATION_FAILED)
            return ("", _packValidationData(true, validUntil, validAfter));
        }

        // Success - return validation data with time range
        return ("", _packValidationData(false, validUntil, validAfter));
    }

    /**
     * @notice Compute the hash to sign for a PackedUserOperation (v0.7)
     * @dev Unpacks the gas fields for hashing
     * @param userOp The PackedUserOperation
     * @param validUntil Expiration timestamp
     * @param validAfter Start timestamp
     * @return The hash to sign
     */
    function getHash(
        PackedUserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter
    ) public view returns (bytes32) {
        // Unpack accountGasLimits: verificationGasLimit (high 128) + callGasLimit (low 128)
        uint256 verificationGasLimit = uint128(bytes16(userOp.accountGasLimits));
        uint256 callGasLimit = uint128(uint256(userOp.accountGasLimits));

        // Unpack gasFees: maxPriorityFeePerGas (high 128) + maxFeePerGas (low 128)
        uint256 maxPriorityFeePerGas = uint128(bytes16(userOp.gasFees));
        uint256 maxFeePerGas = uint128(uint256(userOp.gasFees));

        // Hash the essential UserOp fields + time validity + chain context
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                callGasLimit,
                verificationGasLimit,
                userOp.preVerificationGas,
                maxFeePerGas,
                maxPriorityFeePerGas,
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
    }

    /**
     * @notice Pack validation data
     * @param sigFailed True if signature validation failed
     * @param validUntil Timestamp until which validation is valid
     * @param validAfter Timestamp after which validation is valid
     * @return Packed validation data
     */
    function _packValidationData(
        bool sigFailed,
        uint48 validUntil,
        uint48 validAfter
    ) internal pure returns (uint256) {
        // Format: [160 bits: aggregator/sigFailed][48 bits: validUntil][48 bits: validAfter]
        // sigFailed = 1 in first 160 bits means failure
        // validUntil = 0 means no expiration
        return
            (sigFailed ? 1 : 0) |
            (uint256(validUntil) << 160) |
            (uint256(validAfter) << (160 + 48));
    }

    /// @notice Allow receiving ETH for deposits
    receive() external payable {
        // Automatically deposit to EntryPoint
        if (msg.value > 0) {
            entryPoint.depositTo{value: msg.value}(address(this));
        }
    }
}
