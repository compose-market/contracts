// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClone} from "./interfaces/Iclone.sol";
import {IAgentFactory} from "./interfaces/Iagentfactory.sol";

/**
 * @title Clone
 * @notice Contract for cloning existing agents with mutable parameters
 * @dev Only agents with cloneable=true can be cloned. Clones cannot be cloned again.
 * 
 * Mutable fields when cloning:
 * - chainId: New chain ID
 * - price: New integration price
 * - model: New model identifier
 * - units: New supply cap
 * 
 * Immutable fields (inherited from original):
 * - skills: Same capabilities
 * - name/description base: Referenced from original
 */
contract Clone is IClone {
    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Reference to AgentFactory
    IAgentFactory public immutable agentFactory;

    /// @notice Mapping from original agent ID to array of clone IDs
    mapping(uint256 => uint256[]) private _clones;

    /// @notice Total clones created
    uint256 private _totalClones;

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _agentFactory) {
        require(_agentFactory != address(0), "Zero address");
        agentFactory = IAgentFactory(_agentFactory);
    }

    // =============================================================================
    // IClone Implementation
    // =============================================================================

    /// @inheritdoc IClone
    function cloneAgent(
        uint256 originalAgentId,
        CloneParams calldata params,
        string calldata newAgentCardUri
    ) external returns (uint256 clonedAgentId) {
        // Verify original agent exists and is cloneable
        IAgentFactory.AgentData memory originalData = agentFactory.getAgentData(originalAgentId);
        
        if (!originalData.cloneable) {
            revert AgentNotCloneable(originalAgentId);
        }
        
        if (originalData.isClone) {
            revert CloneCannotBeCloned(originalAgentId);
        }

        // Generate new DNA hash from modified parameters
        bytes32 newDnaHash = keccak256(abi.encodePacked(
            originalData.dnaHash, // Include original DNA as base
            params.chainId,
            params.model,
            msg.sender,
            block.timestamp
        ));

        // Mint the clone via AgentFactory
        // Note: AgentFactory.mintClone must be called by an authorized consumer
        clonedAgentId = _mintCloneViaFactory(
            newDnaHash,
            params.licenses,
            params.licensePrice,
            originalAgentId,
            newAgentCardUri
        );

        // Track the clone
        _clones[originalAgentId].push(clonedAgentId);
        _totalClones++;

        emit AgentCloned(originalAgentId, clonedAgentId, msg.sender, newDnaHash);
    }

    /// @inheritdoc IClone
    function canClone(uint256 agentId) external view returns (bool) {
        try agentFactory.getAgentData(agentId) returns (IAgentFactory.AgentData memory data) {
            return data.cloneable && !data.isClone;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IClone
    function getClonesOf(uint256 originalAgentId) external view returns (uint256[] memory cloneIds) {
        return _clones[originalAgentId];
    }

    /// @inheritdoc IClone
    function getCloneCount(uint256 originalAgentId) external view returns (uint256 count) {
        return _clones[originalAgentId].length;
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    /**
     * @notice Mint a clone via the AgentFactory
     * @dev This contract must be authorized as a consumer in AgentFactory
     */
    function _mintCloneViaFactory(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        uint256 parentAgentId,
        string calldata agentCardUri
    ) internal returns (uint256 agentId) {
        // Call AgentFactory's mintClone function
        // This requires Clone contract to be authorized in AgentFactory
        (bool success, bytes memory data) = address(agentFactory).call(
            abi.encodeWithSignature(
                "mintClone(bytes32,uint256,uint256,uint256,address,string)",
                dnaHash,
                licenses,
                licensePrice,
                parentAgentId,
                msg.sender,
                agentCardUri
            )
        );
        
        require(success, "Clone mint failed");
        agentId = abi.decode(data, (uint256));
    }

    // =============================================================================
    // View Functions
    // =============================================================================

    /// @notice Get total number of clones created
    function totalClones() external view returns (uint256) {
        return _totalClones;
    }

    /// @notice Get the AgentFactory address
    function getAgentFactory() external view returns (address) {
        return address(agentFactory);
    }
}
