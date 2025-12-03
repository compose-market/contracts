// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDistributor} from "./interfaces/Iroyalties.sol";

/**
 * @title Distributor
 * @notice Fee distribution contract for the Manowar ecosystem
 * @dev Handles splitting payments between multiple recipients based on shares
 * 
 * Used for:
 * - Warp royalty splits (10% creator, 10% treasury, 80% warper)
 * - Lease fee splits (creator % + leaser %)
 * - General multi-recipient distributions
 */
contract Distributor is IDistributor {
    // =============================================================================
    // Constants
    // =============================================================================

    uint256 public constant BASIS_POINTS = 10000; // 100% = 10000

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Treasury wallet address
    address public immutable treasury;

    /// @notice Distribution counter for unique IDs
    uint256 private _distributionCounter;

    /// @notice Admin address
    address private _admin;

    // =============================================================================
    // Events
    // =============================================================================

    event NativeDistributed(bytes32 indexed distributionId, uint256 totalAmount);
    event TokenDistributed(bytes32 indexed distributionId, address indexed token, uint256 totalAmount);

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _treasury) {
        require(_treasury != address(0), "Zero treasury");
        treasury = _treasury;
        _admin = msg.sender;
    }

    // =============================================================================
    // IDistributor Implementation
    // =============================================================================

    /// @inheritdoc IDistributor
    function distribute(
        Recipient[] calldata recipients,
        uint256 totalAmount,
        address token
    ) external payable returns (bytes32 distributionId) {
        if (totalAmount == 0) revert ZeroAmount();
        if (!_validateRecipients(recipients)) revert InvalidRecipients();

        distributionId = keccak256(abi.encodePacked(
            msg.sender,
            block.timestamp,
            ++_distributionCounter
        ));

        uint256[] memory amounts = _calculateAmounts(recipients, totalAmount);
        address[] memory recipientAddresses = new address[](recipients.length);

        if (token == address(0)) {
            // Native token distribution
            require(msg.value >= totalAmount, "Insufficient ETH");
            
            for (uint256 i = 0; i < recipients.length; i++) {
                recipientAddresses[i] = recipients[i].recipient;
                if (amounts[i] > 0) {
                    (bool success, ) = recipients[i].recipient.call{value: amounts[i]}("");
                    if (!success) revert TransferFailed(recipients[i].recipient);
                }
            }
            
            // Refund excess
            if (msg.value > totalAmount) {
                (bool refundSuccess, ) = msg.sender.call{value: msg.value - totalAmount}("");
                require(refundSuccess, "Refund failed");
            }
            
            emit NativeDistributed(distributionId, totalAmount);
        } else {
            // ERC20 token distribution
            IERC20 erc20 = IERC20(token);
            
            for (uint256 i = 0; i < recipients.length; i++) {
                recipientAddresses[i] = recipients[i].recipient;
                if (amounts[i] > 0) {
                    bool success = erc20.transferFrom(msg.sender, recipients[i].recipient, amounts[i]);
                    if (!success) revert TransferFailed(recipients[i].recipient);
                }
            }
            
            emit TokenDistributed(distributionId, token, totalAmount);
        }

        emit FeesDistributed(distributionId, totalAmount, recipientAddresses, amounts);
    }

    /// @inheritdoc IDistributor
    function calculateDistribution(
        Recipient[] calldata recipients,
        uint256 totalAmount
    ) external pure returns (uint256[] memory amounts) {
        return _calculateAmounts(recipients, totalAmount);
    }

    /// @inheritdoc IDistributor
    function validateRecipients(Recipient[] calldata recipients) external pure returns (bool) {
        return _validateRecipients(recipients);
    }

    /// @inheritdoc IDistributor
    function getTreasury() external view returns (address) {
        return treasury;
    }

    // =============================================================================
    // Warp-Specific Distribution
    // =============================================================================

    /**
     * @notice Distribute warp royalties (10% creator, 10% treasury, 80% warper)
     * @param originalCreator Original creator address (can be address(0))
     * @param warper Warper address
     * @param totalAmount Total amount to distribute
     * @param token Token address (address(0) for native)
     */
    function distributeWarpRoyalties(
        address originalCreator,
        address warper,
        uint256 totalAmount,
        address token
    ) external payable returns (bytes32 distributionId) {
        if (totalAmount == 0) revert ZeroAmount();

        Recipient[] memory recipients;
        
        if (originalCreator == address(0)) {
            // Creator unknown: 20% treasury, 80% warper
            recipients = new Recipient[](2);
            recipients[0] = Recipient(treasury, 2000);  // 20%
            recipients[1] = Recipient(warper, 8000);    // 80%
        } else {
            // Creator known: 10% creator, 10% treasury, 80% warper
            recipients = new Recipient[](3);
            recipients[0] = Recipient(originalCreator, 1000); // 10%
            recipients[1] = Recipient(treasury, 1000);        // 10%
            recipients[2] = Recipient(warper, 8000);          // 80%
        }

        return this.distribute{value: msg.value}(recipients, totalAmount, token);
    }

    /**
     * @notice Distribute lease fees
     * @param creator Manowar creator address
     * @param leaser Leaser address
     * @param creatorPercent Creator's share (max 20, in whole percent)
     * @param totalAmount Total amount to distribute
     * @param token Token address
     */
    function distributeLeaseFeeds(
        address creator,
        address leaser,
        uint8 creatorPercent,
        uint256 totalAmount,
        address token
    ) external payable returns (bytes32 distributionId) {
        if (totalAmount == 0) revert ZeroAmount();
        require(creatorPercent <= 20, "Max 20%");

        uint256 creatorShare = uint256(creatorPercent) * 100; // Convert to basis points
        uint256 leaserShare = BASIS_POINTS - creatorShare;

        Recipient[] memory recipients = new Recipient[](2);
        recipients[0] = Recipient(creator, creatorShare);
        recipients[1] = Recipient(leaser, leaserShare);

        return this.distribute{value: msg.value}(recipients, totalAmount, token);
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    function _calculateAmounts(
        Recipient[] calldata recipients,
        uint256 totalAmount
    ) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](recipients.length);
        uint256 distributed = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (i == recipients.length - 1) {
                // Last recipient gets remainder to avoid rounding issues
                amounts[i] = totalAmount - distributed;
            } else {
                amounts[i] = (totalAmount * recipients[i].share) / BASIS_POINTS;
                distributed += amounts[i];
            }
        }
    }

    function _validateRecipients(Recipient[] calldata recipients) internal pure returns (bool) {
        if (recipients.length == 0) return false;
        
        uint256 totalShares = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].recipient == address(0)) return false;
            totalShares += recipients[i].share;
        }
        
        return totalShares == BASIS_POINTS;
    }

    // =============================================================================
    // Admin Functions
    // =============================================================================

    function transferAdmin(address newAdmin) external {
        require(msg.sender == _admin, "Not admin");
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }

    // =============================================================================
    // Receive Function
    // =============================================================================

    receive() external payable {}
}

// =============================================================================
// Minimal IERC20 Interface
// =============================================================================

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

