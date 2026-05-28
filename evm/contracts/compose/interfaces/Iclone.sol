// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IClone
 * @notice Interface for cloning agents
 * @dev Allows creating new agents from existing cloneable agents with mutable fields
 */
interface IClone {
    /// @notice Emitted when an agent is cloned
    event AgentCloned(
        uint256 indexed originalAgentId,
        uint256 indexed clonedAgentId,
        address indexed cloner,
        bytes32 newDnaHash
    );

    error AgentNotCloneable(uint256 agentId);
    error CloneCannotBeCloned(uint256 agentId);
    error AgentNotFound(uint256 agentId);
    error InvalidCloneParameters();

    /**
     * @notice Clone parameters for mutable fields
     * @param chainId New chain ID for the clone
     * @param licensePrice New license price in USDC (6 decimals)
     * @param model New model identifier
     * @param licenses New license supply cap
     */
    struct CloneParams {
        uint256 chainId;
        uint256 licensePrice;
        string model;
        uint256 licenses;
    }

    /**
     * @notice Clone an existing agent with modified parameters
     * @dev Only works on agents with cloneable=true. Clones cannot be cloned.
     * @param originalAgentId The agent to clone
     * @param params The mutable parameters for the clone
     * @param newAgentCardUri IPFS URI for the cloned agent's card
     * @return clonedAgentId The newly created clone's ID
     */
    function cloneAgent(
        uint256 originalAgentId,
        CloneParams calldata params,
        string calldata newAgentCardUri
    ) external returns (uint256 clonedAgentId);

    /**
     * @notice Check if an agent can be cloned
     * @param agentId The agent's unique identifier
     * @return canClone True if the agent is cloneable and not itself a clone
     */
    function canClone(uint256 agentId) external view returns (bool canClone);

    /**
     * @notice Get all clones of an original agent
     * @param originalAgentId The original agent's ID
     * @return cloneIds Array of clone agent IDs
     */
    function getClonesOf(uint256 originalAgentId) external view returns (uint256[] memory cloneIds);

    /**
     * @notice Get clone count for an original agent
     * @param originalAgentId The original agent's ID
     * @return count Number of times this agent has been cloned
     */
    function getCloneCount(uint256 originalAgentId) external view returns (uint256 count);
}

