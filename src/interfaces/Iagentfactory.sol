// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC8004Identity} from "./IERC8004.sol";

/**
 * @title IAgentFactory
 * @notice Interface for the Manowar Agent Factory (ERC-8004 Identity Registry + extensions)
 * @dev Extends ERC-8004 Identity with Manowar-specific fields: licenses, licensePrice, cloneable, dnaHash
 * 
 * Licensing Model:
 * - Agents have a `licensePrice` that users pay to include the agent in a Manowar workflow
 * - Agents have `licenses` (supply cap) limiting how many times they can be licensed
 * - When licensed into a Manowar, bi-directional tracking records the relationship
 * - Agent creators retain ownership and receive payment when their agents are licensed
 */
interface IAgentFactory is IERC8004Identity {
    /// @notice Agent data structure with Manowar extensions
    struct AgentData {
        bytes32 dnaHash;           // keccak256(skills, chain, model) - unique agent identity
        uint256 licenses;          // Supply cap for licensing (0 = infinite)
        uint256 licensesMinted;    // Number of licenses already issued
        uint256 licensePrice;      // Price to license this agent into a Manowar (USDC, 6 decimals)
        address creator;           // Original creator address (receives licensing fees)
        bool cloneable;            // Can this agent be cloned
        bool isClone;              // Is this a cloned agent
        uint256 parentAgentId;     // Reference to original agent (if clone)
        string agentCardUri;       // IPFS URI to A2A-compatible Agent Card
    }

    /// @notice License record for bi-directional tracking
    struct LicenseRecord {
        address manowarContract;   // The Manowar contract that licensed this agent
        uint256 manowarId;         // The Manowar token ID
        uint256 licensedAt;        // Timestamp when licensed
    }

    /// @notice Emitted when a new agent is minted
    event AgentMinted(
        uint256 indexed agentId,
        address indexed creator,
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        bool cloneable
    );

    /// @notice Emitted when an agent is licensed into a Manowar
    event AgentLicensed(
        uint256 indexed agentId,
        address indexed manowarContract,
        uint256 indexed manowarId,
        uint256 licenseNumber
    );

    /// @notice Emitted when a license is revoked (agent removed from Manowar)
    event AgentLicenseRevoked(
        uint256 indexed agentId,
        address indexed manowarContract,
        uint256 manowarId
    );

    /// @notice Emitted when agent license price is updated
    event AgentPriceUpdated(uint256 indexed agentId, uint256 oldPrice, uint256 newPrice);

    error AgentNotFound(uint256 agentId);
    error NotAgentCreator(uint256 agentId, address caller);
    error AgentNotCloneable(uint256 agentId);
    error NoLicensesAvailable(uint256 agentId);
    error AlreadyLicensed(uint256 agentId, address manowarContract, uint256 manowarId);
    error NotLicensed(uint256 agentId, address manowarContract, uint256 manowarId);
    error InvalidDnaHash();
    error InvalidPrice();
    error CloneCannotBeCloned(uint256 agentId);

    /**
     * @notice Mint a new agent with full Manowar metadata
     * @param dnaHash Unique hash from keccak256(skills, chain, model)
     * @param licenses Supply cap for licensing (0 = infinite)
     * @param licensePrice Price to license this agent in USDC (6 decimals)
     * @param cloneable Whether this agent can be cloned
     * @param agentCardUri IPFS URI to the Agent Card JSON
     * @return agentId The newly minted agent's ID
     */
    function mintAgent(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
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
     * @notice Check if an agent has available licenses
     * @param agentId The agent's unique identifier
     * @return available True if licenses are available (or unlimited)
     */
    function hasAvailableLicenses(uint256 agentId) external view returns (bool available);

    /**
     * @notice Consume a license for an agent (called by Manowar when nesting)
     * @dev Records bi-directional tracking between agent and Manowar
     * @param agentId The agent's unique identifier
     * @param manowarContract The Manowar contract address
     * @param manowarId The Manowar token ID
     * @return licenseNumber The license number that was consumed
     */
    function consumeLicense(
        uint256 agentId,
        address manowarContract,
        uint256 manowarId
    ) external returns (uint256 licenseNumber);

    /**
     * @notice Revoke a license (called when agent is removed from Manowar)
     * @param agentId The agent's unique identifier
     * @param manowarContract The Manowar contract address
     * @param manowarId The Manowar token ID
     */
    function revokeLicense(
        uint256 agentId,
        address manowarContract,
        uint256 manowarId
    ) external;

    /**
     * @notice Check if an agent is licensed to a specific Manowar
     * @param agentId The agent's unique identifier
     * @param manowarContract The Manowar contract address
     * @param manowarId The Manowar token ID
     * @return licensed True if the agent is licensed to that Manowar
     */
    function isLicensedTo(
        uint256 agentId,
        address manowarContract,
        uint256 manowarId
    ) external view returns (bool licensed);

    /**
     * @notice Get all license records for an agent
     * @param agentId The agent's unique identifier
     * @return records Array of LicenseRecord structs
     */
    function getLicenseRecords(uint256 agentId) external view returns (LicenseRecord[] memory records);

    /**
     * @notice Update agent license price (creator only)
     * @param agentId The agent's unique identifier
     * @param newPrice New license price in USDC (6 decimals)
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

    /**
     * @notice Check if agent exists
     * @param agentId The agent's unique identifier
     * @return exists True if the agent exists
     */
    function agentExists(uint256 agentId) external view returns (bool exists);
}
