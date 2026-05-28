// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDelegation} from "./interfaces/Idelegation.sol";
import {IClone} from "./interfaces/Iclone.sol";
import {IWarp} from "./interfaces/Iwarp.sol";
import {ILease} from "./interfaces/Ilease.sol";

/**
 * @title Delegation
 * @notice Feature delegation contract for the Manowar ecosystem
 * @dev Routes Clone, Warp, and Lease operations to their respective modules
 * 
 * This contract is called by AgentManager via delegatecall to execute
 * feature-specific logic while maintaining upgradeability.
 */
contract Delegation is IDelegation {
    // =============================================================================
    // Constants
    // =============================================================================

    bytes32 public constant MODULE_CLONE = keccak256("MODULE_CLONE");
    bytes32 public constant MODULE_WARP = keccak256("MODULE_WARP");
    bytes32 public constant MODULE_LEASE = keccak256("MODULE_LEASE");

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice AgentManager address (set once)
    address private _manager;

    /// @notice Module addresses
    mapping(bytes32 => address) private _modules;

    /// @notice Initialization flag
    bool private _initialized;

    // =============================================================================
    // Modifiers
    // =============================================================================

    modifier onlyManager() {
        if (msg.sender != _manager) revert NotManager();
        _;
    }

    modifier moduleExists(bytes32 moduleId) {
        if (_modules[moduleId] == address(0)) revert ModuleNotSet(moduleId);
        _;
    }

    // =============================================================================
    // Initialization
    // =============================================================================

    /**
     * @notice Initialize the delegation contract
     * @param manager The AgentManager address
     */
    function initialize(address manager) external {
        require(!_initialized, "Already initialized");
        require(manager != address(0), "Zero address");
        
        _manager = manager;
        _initialized = true;
    }

    // =============================================================================
    // IDelegation Implementation
    // =============================================================================

    /// @inheritdoc IDelegation
    function initializeModules(
        address cloneModule,
        address warpModule,
        address leaseModule
    ) external onlyManager {
        require(cloneModule != address(0), "Zero clone");
        require(warpModule != address(0), "Zero warp");
        require(leaseModule != address(0), "Zero lease");

        _modules[MODULE_CLONE] = cloneModule;
        _modules[MODULE_WARP] = warpModule;
        _modules[MODULE_LEASE] = leaseModule;

        emit ModulesInitialized(cloneModule, warpModule, leaseModule);
    }

    /// @inheritdoc IDelegation
    function getModule(bytes32 moduleId) external view returns (address) {
        return _modules[moduleId];
    }

    /// @inheritdoc IDelegation
    function delegateClone(
        uint256 originalAgentId,
        uint256 chainId,
        uint256 licensePrice,
        string calldata model,
        uint256 licenses,
        string calldata agentCardUri
    ) external onlyManager moduleExists(MODULE_CLONE) returns (uint256 clonedAgentId) {
        IClone cloneContract = IClone(_modules[MODULE_CLONE]);
        
        IClone.CloneParams memory params = IClone.CloneParams({
            chainId: chainId,
            licensePrice: licensePrice,
            model: model,
            licenses: licenses
        });

        clonedAgentId = cloneContract.cloneAgent(originalAgentId, params, agentCardUri);
    }

    /// @inheritdoc IDelegation
    function delegateWarp(
        bytes32 originalAgentHash,
        address originalCreator,
        uint256 licenses,
        uint256 licensePrice,
        string calldata agentCardUri
    ) external onlyManager moduleExists(MODULE_WARP) returns (uint256 warpedAgentId) {
        IWarp warpContract = IWarp(_modules[MODULE_WARP]);
        
        warpedAgentId = warpContract.warpAgent(
            originalAgentHash,
            originalCreator,
            licenses,
            licensePrice,
            agentCardUri
        );
    }

    /// @inheritdoc IDelegation
    function delegateCreateLease(
        uint256 workflowId,
        uint256 duration
    ) external onlyManager moduleExists(MODULE_LEASE) returns (uint256 leaseId) {
        ILease leaseContract = ILease(_modules[MODULE_LEASE]);
        leaseId = leaseContract.createLease(workflowId, duration);
    }

    /// @inheritdoc IDelegation
    function delegateTerminateLease(uint256 leaseId) external onlyManager moduleExists(MODULE_LEASE) {
        ILease leaseContract = ILease(_modules[MODULE_LEASE]);
        leaseContract.terminateLease(leaseId);
    }

    /// @inheritdoc IDelegation
    function getManager() external view returns (address) {
        return _manager;
    }

    // =============================================================================
    // Additional Module Management
    // =============================================================================

    /**
     * @notice Update a specific module address
     * @param moduleId The module identifier
     * @param moduleAddress The new module address
     */
    function updateModule(bytes32 moduleId, address moduleAddress) external onlyManager {
        require(moduleAddress != address(0), "Zero address");
        _modules[moduleId] = moduleAddress;
    }

    /**
     * @notice Check if delegation is initialized
     */
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}
