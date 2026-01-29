// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC7401} from "./IERC7401.sol";

/**
 * @title IManowar
 * @notice Interface for Manowar workflows (ERC-7401 nestable NFTs)
 * @dev Extends ERC-7401 to compose multiple ERC-8004 agents into workflows
 */
interface IManowar is IERC7401 {
    /// @notice Emitted when a Manowar is minted
    event ManowarMinted(
        uint256 indexed manowarId,
        address indexed creator,
        string title,
        uint256 x402Price,
        uint256 units
    );

    /// @notice Emitted when an agent is added to a Manowar
    event AgentAdded(uint256 indexed manowarId, uint256 indexed agentId);

    /// @notice Emitted when an agent is removed from a Manowar
    event AgentRemoved(uint256 indexed manowarId, uint256 indexed agentId);

    /// @notice Emitted when a coordinator is set
    event CoordinatorSet(uint256 indexed manowarId, uint256 indexed coordinatorAgentId, string model);

    /// @notice Emitted when lease is enabled/disabled
    event LeaseStatusChanged(uint256 indexed manowarId, bool enabled, uint256 duration, uint8 percent);

    /// @notice Emitted when RFA is attached
    event RFAAttached(uint256 indexed manowarId, uint256 indexed rfaId);

    /// @notice Emitted when RFA is resolved
    event RFAResolved(uint256 indexed manowarId, uint256 indexed rfaId);

    error ManowarNotFound(uint256 manowarId);
    error NotManowarOwner(uint256 manowarId);
    error AgentNotInManowar(uint256 manowarId, uint256 agentId);
    error InvalidUnits();
    error InvalidX402Price();
    error InvalidLeasePercent();
    error ManowarHasActiveRFA(uint256 manowarId);
    error NoUnitsAvailable(uint256 manowarId);

    /**
     * @notice Manowar metadata structure
     * @param title Workflow title
     * @param description Workflow description
     * @param banner Banner image URI (IPFS)
     * @param manowarCardUri Full metadata URI (IPFS) - contains nested agentCards
     * @param totalPrice Sum of all agent license prices
     * @param units Supply cap
     * @param unitsMinted Units already minted
     * @param creator Original creator address
     * @param leaseEnabled Whether leasing is allowed
     * @param leaseDuration Lease duration in days
     * @param leasePercent Creator's share during lease (max 20%)
     * @param hasCoordinator Whether workflow has a coordinator
     * @param coordinatorModel Model ID for coordinator (if hasCoordinator)
     * @param hasActiveRfa Whether there's an active RFA
     * @param rfaId The active RFA ID
     */
    struct ManowarData {
        string title;
        string description;
        string banner;
        string manowarCardUri;
        uint256 totalPrice;
        uint256 units;
        uint256 unitsMinted;
        address creator;
        bool leaseEnabled;
        uint256 leaseDuration;
        uint8 leasePercent;
        bool hasCoordinator;
        string coordinatorModel;
        bool hasActiveRfa;
        uint256 rfaId;
    }

    /**
     * @notice Parameters for minting a Manowar
     */
    struct MintParams {
        string title;
        string description;
        string banner;
        string manowarCardUri;
        uint256 units;
        bool leaseEnabled;
        uint256 leaseDuration;
        uint8 leasePercent;
        bool hasCoordinator;
        string coordinatorModel;
    }

    /**
     * @notice Mint a new Manowar workflow
     * @param params Minting parameters
     * @param agentIds Initial agents to nest
     * @return manowarId The newly minted Manowar ID
     */
    function mintManowar(
        MintParams calldata params,
        uint256[] calldata agentIds
    ) external returns (uint256 manowarId);

    /**
     * @notice Get Manowar data
     * @param manowarId The Manowar ID
     * @return data The ManowarData struct
     */
    function getManowarData(uint256 manowarId) external view returns (ManowarData memory data);

    /**
     * @notice Add an agent to a Manowar
     * @param manowarId The Manowar ID
     * @param agentId The agent to add
     */
    function addAgent(uint256 manowarId, uint256 agentId) external;

    /**
     * @notice Remove an agent from a Manowar
     * @param manowarId The Manowar ID
     * @param agentId The agent to remove
     */
    function removeAgent(uint256 manowarId, uint256 agentId) external;

    /**
     * @notice Get all agents in a Manowar
     * @param manowarId The Manowar ID
     * @return agentIds Array of agent IDs
     */
    function getAgents(uint256 manowarId) external view returns (uint256[] memory agentIds);

    /**
     * @notice Get agent count for a Manowar
     * @param manowarId The Manowar ID
     * @return count Number of nested agents
     */
    function getAgentCount(uint256 manowarId) external view returns (uint256 count);

    /**
     * @notice Set or update coordinator
     * @param manowarId The Manowar ID
     * @param hasCoordinator Whether to enable coordinator
     * @param model The model ID for coordinator
     */
    function setCoordinator(uint256 manowarId, bool hasCoordinator, string calldata model) external;

    /**
     * @notice Update lease settings
     * @param manowarId The Manowar ID
     * @param enabled Enable/disable leasing
     * @param duration Lease duration in days
     * @param percent Creator's share (max 20%)
     */
    function updateLeaseSettings(
        uint256 manowarId,
        bool enabled,
        uint256 duration,
        uint8 percent
    ) external;

    /**
     * @notice Attach an RFA to a Manowar
     * @param manowarId The Manowar ID
     * @param rfaId The RFA ID
     */
    function attachRFA(uint256 manowarId, uint256 rfaId) external;

    /**
     * @notice Mark RFA as resolved
     * @param manowarId The Manowar ID
     */
    function resolveRFA(uint256 manowarId) external;

    /**
     * @notice Check if Manowar is complete (no active RFA)
     * @param manowarId The Manowar ID
     * @return isComplete True if no pending RFAs
     */
    function isComplete(uint256 manowarId) external view returns (bool isComplete);

    /**
     * @notice Check if Manowar has available units
     * @param manowarId The Manowar ID
     * @return available True if units available (or unlimited)
     */
    function hasAvailableUnits(uint256 manowarId) external view returns (bool available);

    /**
     * @notice Consume/mint one unit
     * @param manowarId The Manowar ID
     * @param buyer The address buying the unit
     * @return unitNumber The unit number consumed
     */
    function consumeUnit(uint256 manowarId, address buyer) external returns (uint256 unitNumber);

    /**
     * @notice Calculate total price including all agents
     * @param manowarId The Manowar ID
     * @return total Total price in USDC
     */
    function calculateTotalPrice(uint256 manowarId) external view returns (uint256 total);

    /**
     * @notice Get all Manowars by creator
     * @param creator The creator address
     * @return manowarIds Array of Manowar IDs
     */
    function getManowarsByCreator(address creator) external view returns (uint256[] memory manowarIds);

    /**
     * @notice Get total Manowar count
     * @return total Total Manowars minted
     */
    function totalManowars() external view returns (uint256 total);

    /**
     * @notice Get complete Manowars (for marketplace)
     * @return manowarIds Array of complete Manowar IDs
     */
    function getCompleteManowars() external view returns (uint256[] memory manowarIds);

    /**
     * @notice Get Manowars with active RFAs
     * @return manowarIds Array of Manowar IDs with RFAs
     */
    function getManowarsWithRFA() external view returns (uint256[] memory manowarIds);

    /**
     * @notice Get the AgentFactory address
     * @return factory The AgentFactory contract
     */
    function getAgentFactory() external view returns (address factory);

    /**
     * @notice Maximum lease percentage
     */
    function MAX_LEASE_PERCENT() external pure returns (uint8);
}

