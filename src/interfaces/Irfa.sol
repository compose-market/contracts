// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRFA
 * @notice Interface for Request-For-Agent escrow system
 * @dev Full USDC escrow on creation, released to agent creator on acceptance
 */
interface IRFA {
    /// @notice Emitted when an RFA is created
    event RFACreated(
        uint256 indexed rfaId,
        uint256 indexed manowarId,
        address indexed publisher,
        uint256 offerAmount,
        string title
    );

    /// @notice Emitted when an agent is submitted for an RFA
    event AgentSubmitted(
        uint256 indexed rfaId,
        uint256 indexed agentId,
        address indexed agentCreator
    );

    /// @notice Emitted when an RFA is fulfilled (agent accepted)
    event RFAFulfilled(
        uint256 indexed rfaId,
        uint256 indexed agentId,
        address indexed agentCreator,
        uint256 payoutAmount
    );

    /// @notice Emitted when an RFA is cancelled
    event RFACancelled(uint256 indexed rfaId, address indexed publisher, uint256 refundAmount);

    error RFANotFound(uint256 rfaId);
    error RFANotOpen(uint256 rfaId);
    error NotRFAPublisher(uint256 rfaId);
    error InvalidOfferAmount();
    error InvalidSkills();
    error AgentAlreadySubmitted(uint256 rfaId, uint256 agentId);
    error NoSubmissionsForRFA(uint256 rfaId);
    error SubmissionNotFound(uint256 rfaId, uint256 agentId);
    error InsufficientBalance();
    error TransferFailed();

    /// @notice RFA status enum
    enum RFAStatus {
        None,
        Open,
        Fulfilled,
        Cancelled
    }

    /**
     * @notice RFA request data structure
     * @param manowarId The Manowar this RFA is for
     * @param title Request title
     * @param description Detailed description
     * @param requiredSkills Array of required skill IDs
     * @param offerAmount USDC amount escrowed
     * @param publisher Address that created the RFA
     * @param createdAt Creation timestamp
     * @param status Current RFA status
     * @param fulfilledByAgentId The accepted agent ID (if fulfilled)
     * @param agentCreator The accepted agent's creator (if fulfilled)
     */
    struct RFARequest {
        uint256 manowarId;
        string title;
        string description;
        bytes32[] requiredSkills;
        uint256 offerAmount;
        address publisher;
        uint256 createdAt;
        RFAStatus status;
        uint256 fulfilledByAgentId;
        address agentCreator;
    }

    /**
     * @notice Agent submission for an RFA
     * @param agentId The submitted agent's ID
     * @param creator The agent creator's address
     * @param submittedAt Submission timestamp
     */
    struct Submission {
        uint256 agentId;
        address creator;
        uint256 submittedAt;
    }

    /**
     * @notice Create a new RFA with USDC escrow
     * @param manowarId The Manowar this RFA is for
     * @param title Request title
     * @param description Detailed description
     * @param requiredSkills Array of required skill IDs (bytes32)
     * @param offerAmount USDC amount to escrow
     * @return rfaId The newly created RFA ID
     */
    function createRFA(
        uint256 manowarId,
        string calldata title,
        string calldata description,
        bytes32[] calldata requiredSkills,
        uint256 offerAmount
    ) external returns (uint256 rfaId);

    /**
     * @notice Submit an agent for an RFA
     * @param rfaId The RFA ID
     * @param agentId The agent to submit
     */
    function submitAgent(uint256 rfaId, uint256 agentId) external;

    /**
     * @notice Accept a submitted agent (publisher only)
     * @dev Releases escrowed USDC to the agent creator
     * @param rfaId The RFA ID
     * @param agentId The agent to accept
     */
    function acceptAgent(uint256 rfaId, uint256 agentId) external;

    /**
     * @notice Cancel an RFA and refund escrow (publisher only)
     * @dev Can only cancel if no agent has been accepted yet
     * @param rfaId The RFA ID to cancel
     */
    function cancelRFA(uint256 rfaId) external;

    /**
     * @notice Get RFA data
     * @param rfaId The RFA ID
     * @return data The RFARequest struct
     */
    function getRFAData(uint256 rfaId) external view returns (RFARequest memory data);

    /**
     * @notice Get all submissions for an RFA
     * @param rfaId The RFA ID
     * @return submissions Array of Submission structs
     */
    function getSubmissions(uint256 rfaId) external view returns (Submission[] memory submissions);

    /**
     * @notice Get RFA status
     * @param rfaId The RFA ID
     * @return status The current status
     */
    function getRFAStatus(uint256 rfaId) external view returns (RFAStatus status);

    /**
     * @notice Get all open RFAs
     * @return rfaIds Array of open RFA IDs
     */
    function getOpenRFAs() external view returns (uint256[] memory rfaIds);

    /**
     * @notice Get RFAs for a specific Manowar
     * @param manowarId The Manowar ID
     * @return rfaIds Array of RFA IDs
     */
    function getRFAsForManowar(uint256 manowarId) external view returns (uint256[] memory rfaIds);

    /**
     * @notice Get RFAs published by an address
     * @param publisher The publisher address
     * @return rfaIds Array of RFA IDs
     */
    function getRFAsByPublisher(address publisher) external view returns (uint256[] memory rfaIds);

    /**
     * @notice Get total escrowed amount in contract
     * @return amount Total USDC escrowed
     */
    function totalEscrowed() external view returns (uint256 amount);

    /**
     * @notice Get the USDC token address
     * @return usdc The USDC contract address
     */
    function getUSDC() external view returns (address usdc);
}

