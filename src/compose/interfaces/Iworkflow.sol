// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC7401} from "./IERC7401.sol";

/**
 * @title IWorkflow
 * @notice Interface for Workflows (ERC-7401 nestable NFTs)
 * @dev Extends ERC-7401 to compose multiple ERC-8004 agents into workflows
 */
interface IWorkflow is IERC7401 {
    /// @notice Emitted when a Workflow is minted
    event WorkflowMinted(
        uint256 indexed workflowId,
        address indexed creator,
        string title,
        uint256 x402Price,
        uint256 units
    );

    /// @notice Emitted when an agent is added to a Workflow
    event AgentAdded(uint256 indexed workflowId, uint256 indexed agentId);

    /// @notice Emitted when an agent is removed from a Workflow
    event AgentRemoved(uint256 indexed workflowId, uint256 indexed agentId);

    /// @notice Emitted when a coordinator is set
    event CoordinatorSet(uint256 indexed workflowId, uint256 indexed coordinatorAgentId, string model);

    /// @notice Emitted when lease is enabled/disabled
    event LeaseStatusChanged(uint256 indexed workflowId, bool enabled, uint256 duration, uint8 percent);

    /// @notice Emitted when RFA is attached
    event RFAAttached(uint256 indexed workflowId, uint256 indexed rfaId);

    /// @notice Emitted when RFA is resolved
    event RFAResolved(uint256 indexed workflowId, uint256 indexed rfaId);

    error WorkflowNotFound(uint256 workflowId);
    error NotWorkflowOwner(uint256 workflowId);
    error AgentNotInWorkflow(uint256 workflowId, uint256 agentId);
    error InvalidUnits();
    error InvalidX402Price();
    error InvalidLeasePercent();
    error WorkflowHasActiveRFA(uint256 workflowId);
    error NoUnitsAvailable(uint256 workflowId);

    /**
     * @notice Workflow metadata structure
     * @param title Workflow title
     * @param description Workflow description
     * @param banner Banner image URI (IPFS)
     * @param workflowCardUri Full metadata URI (IPFS) - contains nested agentCards
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
    struct WorkflowData {
        string title;
        string description;
        string banner;
        string workflowCardUri;
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
     * @notice Parameters for minting a Workflow
     */
    struct MintParams {
        string title;
        string description;
        string banner;
        string workflowCardUri;
        uint256 units;
        bool leaseEnabled;
        uint256 leaseDuration;
        uint8 leasePercent;
        bool hasCoordinator;
        string coordinatorModel;
    }

    /**
     * @notice Mint a new Workflow
     * @param params Minting parameters
     * @param agentIds Initial agents to nest
     * @return workflowId The newly minted Workflow ID
     */
    function mintWorkflow(
        MintParams calldata params,
        uint256[] calldata agentIds
    ) external returns (uint256 workflowId);

    /**
     * @notice Mint a Workflow using ERC-3009 gasless authorization
     * @dev Combines USDC transfer and minting in single transaction
     * @param params Minting parameters
     * @param agentIds Initial agents to nest
     * @param payer Address paying for the agents (source of USDC)
     * @param validAfter Unix timestamp after which authorization is valid
     * @param validBefore Unix timestamp before which authorization is valid
     * @param authNonce Unique nonce for the authorization
     * @param v ECDSA signature v
     * @param r ECDSA signature r
     * @param s ECDSA signature s
     * @return workflowId The newly minted Workflow ID
     */
    function mintWorkflowWithAuth(
        MintParams calldata params,
        uint256[] calldata agentIds,
        address payer,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 authNonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 workflowId);

    /**
     * @notice Get Workflow data
     * @param workflowId The Workflow ID
     * @return data The WorkflowData struct
     */
    function getWorkflowData(uint256 workflowId) external view returns (WorkflowData memory data);

    /**
     * @notice Add an agent to a Workflow
     * @param workflowId The Workflow ID
     * @param agentId The agent to add
     */
    function addAgent(uint256 workflowId, uint256 agentId) external;

    /**
     * @notice Remove an agent from a Workflow
     * @param workflowId The Workflow ID
     * @param agentId The agent to remove
     */
    function removeAgent(uint256 workflowId, uint256 agentId) external;

    /**
     * @notice Get all agents in a Workflow
     * @param workflowId The Workflow ID
     * @return agentIds Array of agent IDs
     */
    function getAgents(uint256 workflowId) external view returns (uint256[] memory agentIds);

    /**
     * @notice Get agent count for a Workflow
     * @param workflowId The Workflow ID
     * @return count Number of nested agents
     */
    function getAgentCount(uint256 workflowId) external view returns (uint256 count);

    /**
     * @notice Set or update coordinator
     * @param workflowId The Workflow ID
     * @param hasCoordinator Whether to enable coordinator
     * @param model The model ID for coordinator
     */
    function setCoordinator(uint256 workflowId, bool hasCoordinator, string calldata model) external;

    /**
     * @notice Update lease settings
     * @param workflowId The Workflow ID
     * @param enabled Enable/disable leasing
     * @param duration Lease duration in days
     * @param percent Creator's share (max 20%)
     */
    function updateLeaseSettings(
        uint256 workflowId,
        bool enabled,
        uint256 duration,
        uint8 percent
    ) external;

    /**
     * @notice Attach an RFA to a Workflow
     * @param workflowId The Workflow ID
     * @param rfaId The RFA ID
     */
    function attachRFA(uint256 workflowId, uint256 rfaId) external;

    /**
     * @notice Mark RFA as resolved
     * @param workflowId The Workflow ID
     */
    function resolveRFA(uint256 workflowId) external;

    /**
     * @notice Check if Workflow is complete (no active RFA)
     * @param workflowId The Workflow ID
     * @return isComplete True if no pending RFAs
     */
    function isComplete(uint256 workflowId) external view returns (bool isComplete);

    /**
     * @notice Check if Workflow has available units
     * @param workflowId The Workflow ID
     * @return available True if units available (or unlimited)
     */
    function hasAvailableUnits(uint256 workflowId) external view returns (bool available);

    /**
     * @notice Consume/mint one unit
     * @param workflowId The Workflow ID
     * @param buyer The address buying the unit
     * @return unitNumber The unit number consumed
     */
    function consumeUnit(uint256 workflowId, address buyer) external returns (uint256 unitNumber);

    /**
     * @notice Calculate total price including all agents
     * @param workflowId The Workflow ID
     * @return total Total price in USDC
     */
    function calculateTotalPrice(uint256 workflowId) external view returns (uint256 total);

    /**
     * @notice Get all Workflows by creator
     * @param creator The creator address
     * @return workflowIds Array of Workflow IDs
     */
    function getWorkflowsByCreator(address creator) external view returns (uint256[] memory workflowIds);

    /**
     * @notice Get total Workflow count
     * @return total Total Workflows minted
     */
    function totalWorkflows() external view returns (uint256 total);

    /**
     * @notice Get complete Workflows (for marketplace)
     * @return workflowIds Array of complete Workflow IDs
     */
    function getCompleteWorkflows() external view returns (uint256[] memory workflowIds);

    /**
     * @notice Get Workflows with active RFAs
     * @return workflowIds Array of Workflow IDs with RFAs
     */
    function getWorkflowsWithRFA() external view returns (uint256[] memory workflowIds);

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

