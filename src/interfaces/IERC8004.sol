// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IERC8004Identity
 * @notice ERC-8004 Identity Registry interface for AI agents
 * @dev Extends ERC-721 to provide unique AgentIDs with linked Agent Cards
 */
interface IERC8004Identity {
    /// @notice Emitted when a new agent is registered
    event AgentRegistered(
        uint256 indexed agentId,
        address indexed creator,
        bytes32 dnaHash,
        string agentCardUri
    );

    /// @notice Emitted when an agent's card URI is updated
    event AgentCardUpdated(uint256 indexed agentId, string newUri);

    /// @notice Emitted when agent metadata is modified
    event AgentMetadataUpdated(uint256 indexed agentId);

    /// @notice Register a new agent with the given metadata URI
    /// @param agentCardUri IPFS URI pointing to the A2A-compatible Agent Card JSON
    /// @return agentId The unique identifier for the newly registered agent
    function registerAgent(string calldata agentCardUri) external returns (uint256 agentId);

    /// @notice Get the Agent Card URI for a given agent
    /// @param agentId The agent's unique identifier
    /// @return uri The IPFS URI of the Agent Card
    function getAgentCardUri(uint256 agentId) external view returns (string memory uri);

    /// @notice Update the Agent Card URI (creator only)
    /// @param agentId The agent's unique identifier
    /// @param newUri The new IPFS URI
    function updateAgentCardUri(uint256 agentId, string calldata newUri) external;

    /// @notice Check if an agent exists
    /// @param agentId The agent's unique identifier
    /// @return exists True if the agent is registered
    function agentExists(uint256 agentId) external view returns (bool exists);

    /// @notice Get the creator/owner of an agent
    /// @param agentId The agent's unique identifier
    /// @return creator The address that registered the agent
    function getAgentCreator(uint256 agentId) external view returns (address creator);
}

/**
 * @title IERC8004Reputation
 * @notice ERC-8004 Reputation Registry interface
 * @dev Tracks feedback and performance metrics for agents
 */
interface IERC8004Reputation {
    /// @notice Emitted when feedback is recorded for an agent
    event FeedbackRecorded(
        uint256 indexed agentId,
        address indexed reviewer,
        uint8 rating,
        bytes32 feedbackHash
    );

    /// @notice Record feedback for an agent
    /// @param agentId The agent's unique identifier
    /// @param rating Rating from 1-5
    /// @param feedbackHash Hash of off-chain feedback data
    function recordFeedback(uint256 agentId, uint8 rating, bytes32 feedbackHash) external;

    /// @notice Get the average rating for an agent
    /// @param agentId The agent's unique identifier
    /// @return rating Average rating (scaled by 100 for precision)
    /// @return totalReviews Number of reviews received
    function getReputation(uint256 agentId) external view returns (uint256 rating, uint256 totalReviews);
}

/**
 * @title IERC8004Validation
 * @notice ERC-8004 Validation Registry interface
 * @dev Allows third-party verification of agent outputs
 */
interface IERC8004Validation {
    /// @notice Emitted when a validation is recorded
    event ValidationRecorded(
        uint256 indexed agentId,
        address indexed validator,
        bytes32 taskHash,
        bool isValid
    );

    /// @notice Record a validation result for an agent's task
    /// @param agentId The agent's unique identifier
    /// @param taskHash Hash identifying the task
    /// @param isValid Whether the output was validated as correct
    function recordValidation(uint256 agentId, bytes32 taskHash, bool isValid) external;

    /// @notice Get validation stats for an agent
    /// @param agentId The agent's unique identifier
    /// @return validCount Number of valid outputs
    /// @return totalCount Total validations performed
    function getValidationStats(uint256 agentId) external view returns (uint256 validCount, uint256 totalCount);
}

