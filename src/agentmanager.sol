// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAgentManager} from "./interfaces/Iagentmanager.sol";
import {IDelegation} from "./interfaces/Idelegation.sol";

/**
 * @title AgentManager
 * @notice Proxy contract for the Manowar ecosystem
 * @dev Routes calls to Delegation contract and manages owned contracts
 * 
 * Architecture:
 * - AgentManager (this) → Proxy that delegates feature logic
 * - Delegation → Routes to Clone, Warp, Lease modules
 * - Registered contracts: AgentFactory, Manowar, RFA, etc.
 */
contract AgentManager is IAgentManager {
    // =============================================================================
    // Constants
    // =============================================================================

    bytes32 public constant AGENT_FACTORY = keccak256("AGENT_FACTORY");
    bytes32 public constant MANOWAR = keccak256("MANOWAR");
    bytes32 public constant CLONE = keccak256("CLONE");
    bytes32 public constant WARP = keccak256("WARP");
    bytes32 public constant LEASE = keccak256("LEASE");
    bytes32 public constant RFA = keccak256("RFA");
    bytes32 public constant ROYALTIES = keccak256("ROYALTIES");
    bytes32 public constant DISTRIBUTOR = keccak256("DISTRIBUTOR");

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Admin address
    address private _admin;

    /// @notice Delegation contract address
    address private _delegation;

    /// @notice Registered contract addresses
    mapping(bytes32 => address) private _contracts;

    /// @notice Pause state
    bool private _paused;

    // =============================================================================
    // Events
    // =============================================================================

    event Paused(address account);
    event Unpaused(address account);

    // =============================================================================
    // Modifiers
    // =============================================================================

    modifier onlyAdmin() {
        if (msg.sender != _admin) revert NotAdmin();
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Paused");
        _;
    }

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor() {
        _admin = msg.sender;
    }

    // =============================================================================
    // IAgentManager Implementation
    // =============================================================================

    /// @inheritdoc IAgentManager
    function setDelegation(address delegation) external onlyAdmin {
        if (delegation == address(0)) revert ZeroAddress();
        
        address oldDelegation = _delegation;
        _delegation = delegation;
        
        emit DelegationUpdated(oldDelegation, delegation);
    }

    /// @inheritdoc IAgentManager
    function getDelegation() external view returns (address) {
        return _delegation;
    }

    /// @inheritdoc IAgentManager
    function registerContract(bytes32 contractId, address contractAddress) external onlyAdmin {
        if (contractAddress == address(0)) revert ZeroAddress();
        
        _contracts[contractId] = contractAddress;
        
        emit ContractRegistered(contractId, contractAddress);
    }

    /// @inheritdoc IAgentManager
    function getContract(bytes32 contractId) external view returns (address) {
        address contractAddr = _contracts[contractId];
        if (contractAddr == address(0)) revert ContractNotRegistered(contractId);
        return contractAddr;
    }

    /// @inheritdoc IAgentManager
    function getAdmin() external view returns (address) {
        return _admin;
    }

    /// @inheritdoc IAgentManager
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        _admin = newAdmin;
    }

    /// @inheritdoc IAgentManager
    function execute(address target, bytes calldata data) external onlyAdmin whenNotPaused returns (bytes memory result) {
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) revert DelegationCallFailed();
        return returnData;
    }

    // =============================================================================
    // Delegation Shortcuts
    // =============================================================================

    /**
     * @notice Clone an agent via delegation
     */
    function cloneAgent(
        uint256 originalAgentId,
        uint256 chainId,
        uint256 price,
        string calldata model,
        uint256 units,
        string calldata agentCardUri
    ) external whenNotPaused returns (uint256 clonedAgentId) {
        require(_delegation != address(0), "Delegation not set");
        
        clonedAgentId = IDelegation(_delegation).delegateClone(
            originalAgentId,
            chainId,
            price,
            model,
            units,
            agentCardUri
        );
    }

    /**
     * @notice Warp an external agent via delegation
     */
    function warpAgent(
        bytes32 originalAgentHash,
        address originalCreator,
        uint256 units,
        uint256 price,
        string calldata agentCardUri
    ) external whenNotPaused returns (uint256 warpedAgentId) {
        require(_delegation != address(0), "Delegation not set");
        
        warpedAgentId = IDelegation(_delegation).delegateWarp(
            originalAgentHash,
            originalCreator,
            units,
            price,
            agentCardUri
        );
    }

    /**
     * @notice Create a lease via delegation
     */
    function createLease(
        uint256 manowarId,
        uint256 duration
    ) external whenNotPaused returns (uint256 leaseId) {
        require(_delegation != address(0), "Delegation not set");
        
        leaseId = IDelegation(_delegation).delegateCreateLease(manowarId, duration);
    }

    /**
     * @notice Terminate a lease via delegation
     */
    function terminateLease(uint256 leaseId) external whenNotPaused {
        require(_delegation != address(0), "Delegation not set");
        
        IDelegation(_delegation).delegateTerminateLease(leaseId);
    }

    // =============================================================================
    // Batch Operations
    // =============================================================================

    /**
     * @notice Initialize all modules at once
     * @param delegation Delegation contract address
     * @param agentFactory AgentFactory contract address
     * @param manowar Manowar contract address
     * @param clone Clone contract address
     * @param warp Warp contract address
     * @param lease Lease contract address
     * @param rfa RFA contract address
     * @param royalties Royalties contract address
     * @param distributor Distributor contract address
     */
    function initializeEcosystem(
        address delegation,
        address agentFactory,
        address manowar,
        address clone,
        address warp,
        address lease,
        address rfa,
        address royalties,
        address distributor
    ) external onlyAdmin {
        // Set delegation
        _delegation = delegation;
        emit DelegationUpdated(address(0), delegation);

        // Register all contracts
        _contracts[AGENT_FACTORY] = agentFactory;
        _contracts[MANOWAR] = manowar;
        _contracts[CLONE] = clone;
        _contracts[WARP] = warp;
        _contracts[LEASE] = lease;
        _contracts[RFA] = rfa;
        _contracts[ROYALTIES] = royalties;
        _contracts[DISTRIBUTOR] = distributor;

        emit ContractRegistered(AGENT_FACTORY, agentFactory);
        emit ContractRegistered(MANOWAR, manowar);
        emit ContractRegistered(CLONE, clone);
        emit ContractRegistered(WARP, warp);
        emit ContractRegistered(LEASE, lease);
        emit ContractRegistered(RFA, rfa);
        emit ContractRegistered(ROYALTIES, royalties);
        emit ContractRegistered(DISTRIBUTOR, distributor);

        // Initialize delegation modules
        IDelegation(delegation).initializeModules(clone, warp, lease);
    }

    // =============================================================================
    // Pause Functions
    // =============================================================================

    function pause() external onlyAdmin {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function isPaused() external view returns (bool) {
        return _paused;
    }

    // =============================================================================
    // View Functions
    // =============================================================================

    /**
     * @notice Get AgentFactory address
     */
    function getAgentFactory() external view returns (address) {
        return _contracts[AGENT_FACTORY];
    }

    /**
     * @notice Get Manowar address
     */
    function getManowar() external view returns (address) {
        return _contracts[MANOWAR];
    }

    /**
     * @notice Get RFA address
     */
    function getRFA() external view returns (address) {
        return _contracts[RFA];
    }

    /**
     * @notice Get all contract addresses
     */
    function getAllContracts() external view returns (
        address agentFactory,
        address manowar,
        address clone,
        address warp,
        address lease,
        address rfa,
        address royalties,
        address distributor
    ) {
        return (
            _contracts[AGENT_FACTORY],
            _contracts[MANOWAR],
            _contracts[CLONE],
            _contracts[WARP],
            _contracts[LEASE],
            _contracts[RFA],
            _contracts[ROYALTIES],
            _contracts[DISTRIBUTOR]
        );
    }
}
