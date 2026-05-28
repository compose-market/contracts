// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRFA} from "./interfaces/Irfa.sol";

/**
 * @title RFA (Request-For-Agent)
 * @notice Contract for requesting missing agents with full USDC escrow
 * @dev Full escrow on creation, released to agent creator only after publisher acceptance
 * 
 * Flow:
 * 1. Publisher creates RFA → full offerAmount escrowed in USDC
 * 2. Agent creators submit their agents for the RFA
 * 3. Publisher reviews submissions and clicks "Accept Agent"
 * 4. Escrow released to accepted agent creator
 * 5. Workflow becomes visible in marketplace (RFA resolved)
 */
contract RFA is IRFA {
    error UnsupportedChain(uint256 chainId);

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice USDC token contract
    IERC20 public immutable usdc;

    /// @notice Workflow contract reference
    address public workflowContract;

    /// @notice AgentFactory reference for verifying agents
    address public agentFactory;

    /// @notice Total RFAs created
    uint256 private _totalRFAs;

    /// @notice Next RFA ID
    uint256 private _nextRFAId;

    /// @notice RFA data storage
    mapping(uint256 => RFARequest) private _rfas;

    /// @notice Submissions for each RFA: rfaId => Submission[]
    mapping(uint256 => Submission[]) private _submissions;

    /// @notice Track which agents have been submitted: rfaId => agentId => bool
    mapping(uint256 => mapping(uint256 => bool)) private _agentSubmitted;

    /// @notice Open RFA IDs
    uint256[] private _openRFAs;

    /// @notice Index in _openRFAs for removal
    mapping(uint256 => uint256) private _openRFAIndex;

    /// @notice RFAs by Workflow ID
    mapping(uint256 => uint256[]) private _rfasByWorkflow;

    /// @notice RFAs by publisher
    mapping(address => uint256[]) private _rfasByPublisher;

    /// @notice Total USDC escrowed
    uint256 private _totalEscrowed;

    /// @notice Admin address
    address private _admin;

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _workflowContract, address _agentFactory, address _adminAddress) {
        require(_workflowContract != address(0), "Zero Workflow address");
        require(_agentFactory != address(0), "Zero AgentFactory address");
        require(_adminAddress != address(0), "Zero admin");

        address usdcAddress = _getUSDCAddress(block.chainid);
        if (usdcAddress == address(0)) {
            revert UnsupportedChain(block.chainid);
        }
        
        usdc = IERC20(usdcAddress);
        workflowContract = _workflowContract;
        agentFactory = _agentFactory;
        _admin = _adminAddress;
        _nextRFAId = 1;
    }

    function _getUSDCAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 43113) return 0x5425890298aed601595a70AB815c96711a31Bc65; // Avalanche Fuji
        if (chainId == 43114) return 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E; // Avalanche C-Chain
        return address(0);
    }

    // =============================================================================
    // IRFA Implementation
    // =============================================================================

    /// @inheritdoc IRFA
    function createRFA(
        uint256 workflowId,
        string calldata title,
        string calldata description,
        bytes32[] calldata requiredSkills,
        uint256 offerAmount
    ) external returns (uint256 rfaId) {
        if (offerAmount == 0) revert InvalidOfferAmount();
        if (requiredSkills.length == 0) revert InvalidSkills();

        // Transfer USDC from publisher to this contract (escrow)
        bool success = usdc.transferFrom(msg.sender, address(this), offerAmount);
        if (!success) revert TransferFailed();

        rfaId = _nextRFAId++;
        _totalRFAs++;

        // Store RFA data
        _rfas[rfaId] = RFARequest({
            workflowId: workflowId,
            title: title,
            description: description,
            requiredSkills: requiredSkills,
            offerAmount: offerAmount,
            publisher: msg.sender,
            createdAt: block.timestamp,
            status: RFAStatus.Open,
            fulfilledByAgentId: 0,
            agentCreator: address(0)
        });

        // Track escrow
        _totalEscrowed += offerAmount;

        // Add to open list
        _openRFAIndex[rfaId] = _openRFAs.length;
        _openRFAs.push(rfaId);

        // Track by Workflow and publisher
        _rfasByWorkflow[workflowId].push(rfaId);
        _rfasByPublisher[msg.sender].push(rfaId);

        // Notify Workflow contract to attach RFA
        _attachRFAToWorkflow(workflowId, rfaId);

        emit RFACreated(rfaId, workflowId, msg.sender, offerAmount, title);
    }

    /// @inheritdoc IRFA
    function submitAgent(uint256 rfaId, uint256 agentId) external {
        RFARequest storage rfa = _rfas[rfaId];
        if (rfa.status != RFAStatus.Open) revert RFANotOpen(rfaId);
        if (_agentSubmitted[rfaId][agentId]) revert AgentAlreadySubmitted(rfaId, agentId);

        // Verify agent exists and caller is creator
        (bool exists, address creator) = _verifyAgent(agentId);
        require(exists, "Agent not found");
        require(creator == msg.sender, "Not agent creator");

        // Record submission
        _submissions[rfaId].push(Submission({
            agentId: agentId,
            creator: msg.sender,
            submittedAt: block.timestamp
        }));

        _agentSubmitted[rfaId][agentId] = true;

        emit AgentSubmitted(rfaId, agentId, msg.sender);
    }

    /// @inheritdoc IRFA
    function acceptAgent(uint256 rfaId, uint256 agentId) external {
        RFARequest storage rfa = _rfas[rfaId];
        
        if (rfa.status != RFAStatus.Open) revert RFANotOpen(rfaId);
        if (rfa.publisher != msg.sender) revert NotRFAPublisher(rfaId);
        if (!_agentSubmitted[rfaId][agentId]) revert SubmissionNotFound(rfaId, agentId);

        // Find the submission to get the agent creator
        address agentCreator;
        Submission[] storage submissions = _submissions[rfaId];
        for (uint256 i = 0; i < submissions.length; i++) {
            if (submissions[i].agentId == agentId) {
                agentCreator = submissions[i].creator;
                break;
            }
        }

        require(agentCreator != address(0), "Creator not found");

        // Update RFA status
        rfa.status = RFAStatus.Fulfilled;
        rfa.fulfilledByAgentId = agentId;
        rfa.agentCreator = agentCreator;

        // Remove from open list
        _removeFromOpenList(rfaId);

        // Update escrow tracking
        _totalEscrowed -= rfa.offerAmount;

        // Transfer escrowed USDC to agent creator
        bool success = usdc.transfer(agentCreator, rfa.offerAmount);
        if (!success) revert TransferFailed();

        // Notify Workflow contract to resolve RFA
        _resolveRFAOnWorkflow(rfa.workflowId);

        emit RFAFulfilled(rfaId, agentId, agentCreator, rfa.offerAmount);
    }

    /// @inheritdoc IRFA
    function cancelRFA(uint256 rfaId) external {
        RFARequest storage rfa = _rfas[rfaId];
        
        if (rfa.status != RFAStatus.Open) revert RFANotOpen(rfaId);
        if (rfa.publisher != msg.sender) revert NotRFAPublisher(rfaId);

        // Update status
        rfa.status = RFAStatus.Cancelled;

        // Remove from open list
        _removeFromOpenList(rfaId);

        // Update escrow tracking
        _totalEscrowed -= rfa.offerAmount;

        // Refund escrowed USDC to publisher
        bool success = usdc.transfer(msg.sender, rfa.offerAmount);
        if (!success) revert TransferFailed();

        // Notify Workflow contract to resolve RFA (removes RFA flag)
        _resolveRFAOnWorkflow(rfa.workflowId);

        emit RFACancelled(rfaId, msg.sender, rfa.offerAmount);
    }

    /// @inheritdoc IRFA
    function getRFAData(uint256 rfaId) external view returns (RFARequest memory) {
        if (_rfas[rfaId].publisher == address(0)) revert RFANotFound(rfaId);
        return _rfas[rfaId];
    }

    /// @inheritdoc IRFA
    function getSubmissions(uint256 rfaId) external view returns (Submission[] memory) {
        return _submissions[rfaId];
    }

    /// @inheritdoc IRFA
    function getRFAStatus(uint256 rfaId) external view returns (RFAStatus) {
        return _rfas[rfaId].status;
    }

    /// @inheritdoc IRFA
    function getOpenRFAs() external view returns (uint256[] memory) {
        return _openRFAs;
    }

    /// @inheritdoc IRFA
    function getRFAsForWorkflow(uint256 workflowId) external view returns (uint256[] memory) {
        return _rfasByWorkflow[workflowId];
    }

    /// @inheritdoc IRFA
    function getRFAsByPublisher(address publisher) external view returns (uint256[] memory) {
        return _rfasByPublisher[publisher];
    }

    /// @inheritdoc IRFA
    function totalEscrowed() external view returns (uint256) {
        return _totalEscrowed;
    }

    /// @inheritdoc IRFA
    function getUSDC() external view returns (address) {
        return address(usdc);
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    function _removeFromOpenList(uint256 rfaId) internal {
        uint256 idx = _openRFAIndex[rfaId];
        uint256 lastIdx = _openRFAs.length - 1;
        
        if (idx != lastIdx) {
            uint256 lastRfaId = _openRFAs[lastIdx];
            _openRFAs[idx] = lastRfaId;
            _openRFAIndex[lastRfaId] = idx;
        }
        
        _openRFAs.pop();
        delete _openRFAIndex[rfaId];
    }

    function _attachRFAToWorkflow(uint256 workflowId, uint256 rfaId) internal {
        // Call Workflow.attachRFA(workflowId, rfaId)
        (bool success,) = workflowContract.call(
            abi.encodeWithSignature("attachRFA(uint256,uint256)", workflowId, rfaId)
        );
        require(success, "Failed to attach RFA");
    }

    function _resolveRFAOnWorkflow(uint256 workflowId) internal {
        // Call Workflow.resolveRFA(workflowId)
        (bool success,) = workflowContract.call(
            abi.encodeWithSignature("resolveRFA(uint256)", workflowId)
        );
        require(success, "Failed to resolve RFA");
    }

    function _verifyAgent(uint256 agentId) internal view returns (bool exists, address creator) {
        // Call AgentFactory to verify agent
        (bool success, bytes memory data) = agentFactory.staticcall(
            abi.encodeWithSignature("agentExists(uint256)", agentId)
        );
        
        if (!success) return (false, address(0));
        exists = abi.decode(data, (bool));
        
        if (exists) {
            (success, data) = agentFactory.staticcall(
                abi.encodeWithSignature("getAgentCreator(uint256)", agentId)
            );
            if (success) {
                creator = abi.decode(data, (address));
            }
        }
    }

    // =============================================================================
    // Admin Functions
    // =============================================================================

    function setWorkflowContract(address _workflow) external {
        require(msg.sender == _admin, "Not admin");
        workflowContract = _workflow;
    }

    function setAgentFactory(address _factory) external {
        require(msg.sender == _admin, "Not admin");
        agentFactory = _factory;
    }

    function transferAdmin(address newAdmin) external {
        require(msg.sender == _admin, "Not admin");
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    // =============================================================================
    // View Functions
    // =============================================================================

    function totalRFAs() external view returns (uint256) {
        return _totalRFAs;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }
}

// =============================================================================
// Minimal IERC20 Interface
// =============================================================================

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}
