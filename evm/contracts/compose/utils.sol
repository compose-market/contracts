// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Utils
 * @notice Additional utilities and helpers for the Manowar ecosystem
 * @dev Contains helper functions for price calculations and x402 integration
 */
contract Utils {
    // =============================================================================
    // Constants
    // =============================================================================

    /// @notice USDC decimals
    uint8 public constant USDC_DECIMALS = 6;

    /// @notice Base price per inference token (0.000001 USDC = 1 wei with 6 decimals)
    uint256 public constant BASE_PRICE_PER_TOKEN = 1;

    /// @notice Maximum tokens per call (100k)
    uint256 public constant MAX_TOKENS_PER_CALL = 100000;

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice AgentManager reference
    address public agentManager;

    /// @notice AgentFactory reference
    address public agentFactory;

    /// @notice Workflow contract reference
    address public workflowContract;

    /// @notice Admin address
    address private _admin;

    // =============================================================================
    // Events
    // =============================================================================

    event PriceCalculated(
        uint256 indexed workflowId,
        uint256 baseModelPrice,
        uint256 agentPrice,
        uint256 x402Price,
        uint256 totalPrice
    );

    event UsageRecorded(
        uint256 indexed workflowId,
        address indexed user,
        uint256 tokensUsed,
        uint256 amountPaid
    );

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _agentManager, address _agentFactory, address _workflow) {
        agentManager = _agentManager;
        agentFactory = _agentFactory;
        workflowContract = _workflow;
        _admin = msg.sender;
    }

    // =============================================================================
    // Price Calculation
    // =============================================================================

    /**
     * @notice Calculate total price for using a Workflow
     * @param workflowId The Workflow ID
     * @param modelPriceMultiplier Model price multiplier (from backend/api/x402)
     * @param estimatedTokens Estimated tokens for the inference
     * @return totalPrice Total price in USDC (6 decimals)
     * @return breakdown Price breakdown [baseModelCost, agentsCost, x402Cost]
     */
    function calculateUsagePrice(
        uint256 workflowId,
        uint256 modelPriceMultiplier,
        uint256 estimatedTokens
    ) external view returns (uint256 totalPrice, uint256[3] memory breakdown) {
        // Get Workflow data
        (uint256 totalAgentPrice, uint256 x402Price) = _getWorkflowPricing(workflowId);
        
        // Calculate base model cost
        // BASE_PRICE_PER_TOKEN * modelPriceMultiplier * tokens
        // modelPriceMultiplier is scaled by 100 (e.g., 100 = 1.0x, 663 = 6.63x)
        uint256 baseModelCost = (BASE_PRICE_PER_TOKEN * modelPriceMultiplier * estimatedTokens) / 100;
        
        // Total = base model + agents + x402
        totalPrice = baseModelCost + totalAgentPrice + x402Price;
        
        breakdown[0] = baseModelCost;
        breakdown[1] = totalAgentPrice;
        breakdown[2] = x402Price;
    }

    /**
     * @notice Calculate maximum price (for x402 pre-authorization)
     * @param workflowId The Workflow ID
     * @param modelPriceMultiplier Model price multiplier
     * @return maxPrice Maximum possible price
     */
    function calculateMaxPrice(
        uint256 workflowId,
        uint256 modelPriceMultiplier
    ) external view returns (uint256 maxPrice) {
        (uint256 totalAgentPrice, uint256 x402Price) = _getWorkflowPricing(workflowId);
        
        uint256 maxBaseModelCost = (BASE_PRICE_PER_TOKEN * modelPriceMultiplier * MAX_TOKENS_PER_CALL) / 100;
        
        maxPrice = maxBaseModelCost + totalAgentPrice + x402Price;
    }

    /**
     * @notice Record usage and emit event (for off-chain tracking)
     * @param workflowId The Workflow ID
     * @param user The user address
     * @param tokensUsed Tokens actually used
     * @param amountPaid Amount paid in USDC
     */
    function recordUsage(
        uint256 workflowId,
        address user,
        uint256 tokensUsed,
        uint256 amountPaid
    ) external {
        require(msg.sender == _admin || msg.sender == agentManager, "Not authorized");
        emit UsageRecorded(workflowId, user, tokensUsed, amountPaid);
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    function _getWorkflowPricing(uint256 workflowId) internal view returns (uint256 totalAgentPrice, uint256 x402Price) {
        // Call Workflow contract
        (bool success, bytes memory data) = workflowContract.staticcall(
            abi.encodeWithSignature("getWorkflowData(uint256)", workflowId)
        );
        
        require(success, "Failed to get Workflow data");
        
        // WorkflowData struct has totalPrice at index 3 and x402Price at index 4
        (
            , // title
            , // description
            , // banner
            uint256 _totalPrice,
            uint256 _x402Price,
            , , , , , , , , , // other fields
        ) = abi.decode(data, (
            string, string, string, uint256, uint256, uint256, uint256,
            address, bool, uint256, uint8, uint256, string, bool, uint256
        ));
        
        return (_totalPrice, _x402Price);
    }

    // =============================================================================
    // Admin Functions
    // =============================================================================

    function setContracts(
        address _agentManager,
        address _agentFactory,
        address _workflow
    ) external {
        require(msg.sender == _admin, "Not admin");
        agentManager = _agentManager;
        agentFactory = _agentFactory;
        workflowContract = _workflow;
    }

    function transferAdmin(address newAdmin) external {
        require(msg.sender == _admin, "Not admin");
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }
}

