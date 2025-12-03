// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC8004Identity} from "./IERC8004.sol";

/**
 * @title IAgentFactory
 * @notice Interface for the Manowar Agent Factory (ERC-8004 Identity Registry + extensions)
 * @dev Extends ERC-8004 Identity with Manowar-specific fields: units, price, cloneable, dnaHash
 */
interface IAgentFactory is IERC8004Identity {
    /// @notice Agent data structure with Manowar extensions
    struct AgentData {
        bytes32 dnaHash;        // keccak256(skills, chain, model)
        uint256 units;          // Supply cap (0 = infinite)
        uint256 unitsMinted;    // Number of units already minted
        uint256 price;          // Integration price in USDC (6 decimals)
        address creator;        // Original creator address
        bool cloneable;         // Can this agent be cloned
        bool isClone;           // Is this a cloned agent
        uint256 parentAgentId;  // Reference to original agent (if clone)
        string agentCardUri;    // IPFS URI to A2A-compatible Agent Card
    }

    /// @notice Emitted when a new agent is minted
    event AgentMinted(
        uint256 indexed agentId,
        address indexed creator,
        bytes32 dnaHash,
        uint256 units,
        uint256 price,
        bool cloneable
    );

    /// @notice Emitted when an agent unit is consumed/assigned
    event AgentUnitConsumed(uint256 indexed agentId, uint256 unitNumber, address indexed assignedTo);

    /// @notice Emitted when agent price is updated
    event AgentPriceUpdated(uint256 indexed agentId, uint256 oldPrice, uint256 newPrice);

    error AgentNotFound(uint256 agentId);
    error NotAgentCreator(uint256 agentId, address caller);
    error AgentNotCloneable(uint256 agentId);
    error NoUnitsAvailable(uint256 agentId);
    error InvalidDnaHash();
    error InvalidPrice();
    error CloneCannotBeCloned(uint256 agentId);

    /**
     * @notice Mint a new agent with full Manowar metadata
     * @param dnaHash Unique hash from keccak256(skills, chain, model)
     * @param units Supply cap (0 = infinite)
     * @param price Integration price in USDC (6 decimals)
     * @param cloneable Whether this agent can be cloned
     * @param agentCardUri IPFS URI to the Agent Card JSON
     * @return agentId The newly minted agent's ID
     */
    function mintAgent(
        bytes32 dnaHash,
        uint256 units,
        uint256 price,
        bool cloneable,
        string calldata agentCardUri
    ) external returns (uint256 agentId);

    /**
     * @notice Get full agent data
     * @param agentId The agent's unique identifier
     * @return data The AgentData struct
     */
    function getAgentData(uint256 agentId) external view returns (AgentData memory data);

    /**
     * @notice Get the DNA hash for an agent
     * @param agentId The agent's unique identifier
     * @return dnaHash The agent's unique DNA hash
     */
    function getDnaHash(uint256 agentId) external view returns (bytes32 dnaHash);

    /**
     * @notice Check if an agent has available units
     * @param agentId The agent's unique identifier
     * @return available True if units are available (or unlimited)
     */
    function hasAvailableUnits(uint256 agentId) external view returns (bool available);

    /**
     * @notice Consume/assign one unit of an agent
     * @dev Called when agent is nested into a Manowar
     * @param agentId The agent's unique identifier
     * @param assignTo The address (Manowar) to assign the unit to
     * @return unitNumber The unit number that was consumed
     */
    function consumeUnit(uint256 agentId, address assignTo) external returns (uint256 unitNumber);

    /**
     * @notice Update agent price (creator only)
     * @param agentId The agent's unique identifier
     * @param newPrice New price in USDC (6 decimals)
     */
    function updatePrice(uint256 agentId, uint256 newPrice) external;

    /**
     * @notice Check if agent is a clone
     * @param agentId The agent's unique identifier
     * @return isClone True if the agent is a clone
     */
    function isAgentClone(uint256 agentId) external view returns (bool isClone);

    /**
     * @notice Get the parent agent ID for a clone
     * @param agentId The clone's unique identifier
     * @return parentId The original agent's ID (0 if not a clone)
     */
    function getParentAgent(uint256 agentId) external view returns (uint256 parentId);

    /**
     * @notice Get total supply of agents
     * @return total Total number of agents minted
     */
    function totalAgents() external view returns (uint256 total);
}

