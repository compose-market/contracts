// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IWarp} from "./interfaces/Iwarp.sol";
import {IAgentFactory} from "./interfaces/Iagentfactory.sol";

/**
 * @title Warp
 * @notice Contract for porting external agents into the Manowar ecosystem
 * @dev Handles royalty distribution: 10% original creator, 10% treasury, 80% warper
 * 
 * If original creator is unknown (address(0)):
 * - Treasury receives 20% (holds creator's 10% for up to 1 year)
 * - Warper receives 80%
 * - Treasury can transfer unclaimed royalties to verified creator within 1 year
 */
contract Warp is IWarp {
    // =============================================================================
    // Constants
    // =============================================================================

    uint8 public constant CREATOR_PERCENT = 10;
    uint8 public constant TREASURY_PERCENT = 10;
    uint8 public constant WARPER_PERCENT = 80;
    uint256 public constant ROYALTY_CLAIM_PERIOD = 365 days;

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Reference to AgentFactory
    IAgentFactory public immutable agentFactory;

    /// @notice Treasury wallet address
    address public immutable treasury;

    /// @notice Warped agent data
    mapping(uint256 => WarpedAgentData) private _warpedAgents;

    /// @notice Check if agent ID is a warped agent
    mapping(uint256 => bool) private _isWarped;

    /// @notice External agent hash to warped agent ID
    mapping(bytes32 => uint256) private _externalToWarped;

    /// @notice Total warped agents
    uint256 private _totalWarped;

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _agentFactory, address _treasury) {
        require(_agentFactory != address(0), "Zero factory address");
        require(_treasury != address(0), "Zero treasury address");
        
        agentFactory = IAgentFactory(_agentFactory);
        treasury = _treasury;
    }

    // =============================================================================
    // IWarp Implementation
    // =============================================================================

    /// @inheritdoc IWarp
    function warpAgent(
        bytes32 originalAgentHash,
        address originalCreator,
        uint256 licenses,
        uint256 licensePrice,
        string calldata agentCardUri
    ) external returns (uint256 warpedAgentId) {
        if (originalAgentHash == bytes32(0)) revert InvalidExternalAgent();
        
        // Check if already warped
        if (_externalToWarped[originalAgentHash] != 0) revert InvalidExternalAgent();

        // Generate DNA hash for the warped agent
        bytes32 dnaHash = keccak256(abi.encodePacked(
            "WARPED",
            originalAgentHash,
            msg.sender,
            block.timestamp
        ));

        // Mint the warped agent via AgentFactory
        warpedAgentId = _mintWarpedViaFactory(
            dnaHash,
            licenses,
            licensePrice,
            agentCardUri
        );

        // Store warped agent data
        _warpedAgents[warpedAgentId] = WarpedAgentData({
            originalCreator: originalCreator,
            warper: msg.sender,
            originalAgentHash: originalAgentHash,
            royaltyExpiryDate: block.timestamp + ROYALTY_CLAIM_PERIOD,
            royaltiesClaimed: false,
            accumulatedRoyalties: 0
        });

        _isWarped[warpedAgentId] = true;
        _externalToWarped[originalAgentHash] = warpedAgentId;
        _totalWarped++;

        emit AgentWarped(warpedAgentId, msg.sender, originalCreator, originalAgentHash);
    }

    /// @inheritdoc IWarp
    function getWarpedData(uint256 warpedAgentId) external view returns (WarpedAgentData memory data) {
        if (!_isWarped[warpedAgentId]) revert InvalidExternalAgent();
        return _warpedAgents[warpedAgentId];
    }

    /// @inheritdoc IWarp
    function isWarped(uint256 agentId) external view returns (bool) {
        return _isWarped[agentId];
    }

    /// @inheritdoc IWarp
    function calculateRoyaltySplit(
        uint256 warpedAgentId,
        uint256 totalAmount
    ) external view returns (uint256 creatorShare, uint256 treasuryShare, uint256 warperShare) {
        if (!_isWarped[warpedAgentId]) revert InvalidExternalAgent();
        
        WarpedAgentData storage data = _warpedAgents[warpedAgentId];
        
        // Warper always gets 80%
        warperShare = (totalAmount * WARPER_PERCENT) / 100;
        
        if (data.originalCreator == address(0)) {
            // Creator unknown: treasury gets 20%
            treasuryShare = totalAmount - warperShare;
            creatorShare = 0;
        } else {
            // Creator known: creator 10%, treasury 10%
            creatorShare = (totalAmount * CREATOR_PERCENT) / 100;
            treasuryShare = totalAmount - warperShare - creatorShare;
        }
    }

    /// @inheritdoc IWarp
    function distributeRoyalty(uint256 warpedAgentId, uint256 amount) external {
        if (!_isWarped[warpedAgentId]) revert InvalidExternalAgent();
        
        WarpedAgentData storage data = _warpedAgents[warpedAgentId];
        
        // If creator is unknown and within claim period, accumulate for potential claim
        if (data.originalCreator == address(0) && block.timestamp < data.royaltyExpiryDate) {
            uint256 creatorPortion = (amount * CREATOR_PERCENT) / 100;
            data.accumulatedRoyalties += creatorPortion;
        }
        
        // Note: Actual token transfers are handled by the Distributor contract
        // This function tracks the royalty amounts for potential future claims
    }

    /// @inheritdoc IWarp
    function transferUnclaimedRoyalties(uint256 warpedAgentId, address verifiedCreator) external {
        if (msg.sender != treasury) revert NotTreasury();
        if (verifiedCreator == address(0)) revert ZeroAddress();
        if (!_isWarped[warpedAgentId]) revert InvalidExternalAgent();
        
        WarpedAgentData storage data = _warpedAgents[warpedAgentId];
        
        if (block.timestamp > data.royaltyExpiryDate) {
            revert RoyaltyExpired(warpedAgentId);
        }
        
        if (data.royaltiesClaimed) {
            revert RoyaltiesAlreadyClaimed(warpedAgentId);
        }
        
        // Update creator and mark as claimed
        data.originalCreator = verifiedCreator;
        data.royaltiesClaimed = true;
        
        emit RoyaltiesTransferred(warpedAgentId, verifiedCreator, data.accumulatedRoyalties);
        
        // Note: Actual token transfer of accumulated royalties would be handled
        // by the treasury or a separate claiming mechanism
    }

    /// @inheritdoc IWarp
    function getTreasury() external view returns (address) {
        return treasury;
    }

    /// @inheritdoc IWarp
    function getRoyaltyPercentages() external pure returns (
        uint8 creatorPercent,
        uint8 treasuryPercent,
        uint8 warperPercent
    ) {
        return (CREATOR_PERCENT, TREASURY_PERCENT, WARPER_PERCENT);
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    /**
     * @notice Mint a warped agent via the AgentFactory
     * @dev This contract must be authorized as a consumer in AgentFactory
     */
    function _mintWarpedViaFactory(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        string calldata agentCardUri
    ) internal returns (uint256 agentId) {
        (bool success, bytes memory data) = address(agentFactory).call(
            abi.encodeWithSignature(
                "mintWarped(bytes32,uint256,uint256,address,string)",
                dnaHash,
                licenses,
                licensePrice,
                msg.sender,
                agentCardUri
            )
        );
        
        require(success, "Warp mint failed");
        agentId = abi.decode(data, (uint256));
    }

    // =============================================================================
    // View Functions
    // =============================================================================

    /// @notice Get total number of warped agents
    function totalWarped() external view returns (uint256) {
        return _totalWarped;
    }

    /// @notice Get warped agent ID from external agent hash
    function getWarpedAgentId(bytes32 externalHash) external view returns (uint256) {
        return _externalToWarped[externalHash];
    }

    /// @notice Check if an external agent has been warped
    function isExternalWarped(bytes32 externalHash) external view returns (bool) {
        return _externalToWarped[externalHash] != 0;
    }

    /// @notice Get the AgentFactory address
    function getAgentFactory() external view returns (address) {
        return address(agentFactory);
    }
}

