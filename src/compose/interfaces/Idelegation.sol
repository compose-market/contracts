// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDelegation
 * @notice Interface for the Delegation contract
 * @dev Implements delegated logic for Clone, Warp, and Lease operations
 */
interface IDelegation {
    /// @notice Emitted when feature modules are initialized
    event ModulesInitialized(address clone, address warp, address lease);

    error NotManager();
    error ModuleNotSet(bytes32 moduleId);
    error ModuleCallFailed(bytes32 moduleId);

    /**
     * @notice Initialize feature module addresses
     * @param cloneModule Clone contract address
     * @param warpModule Warp contract address
     * @param leaseModule Lease contract address
     */
    function initializeModules(
        address cloneModule,
        address warpModule,
        address leaseModule
    ) external;

    /**
     * @notice Get a module address
     * @param moduleId The module identifier
     * @return module The module contract address
     */
    function getModule(bytes32 moduleId) external view returns (address module);

    /**
     * @notice Execute clone operation via delegation
     * @param originalAgentId The agent to clone
     * @param chainId New chain ID
     * @param licensePrice New license price
     * @param model New model
     * @param licenses New license supply cap
     * @param agentCardUri New agent card URI
     * @return clonedAgentId The new cloned agent ID
     */
    function delegateClone(
        uint256 originalAgentId,
        uint256 chainId,
        uint256 licensePrice,
        string calldata model,
        uint256 licenses,
        string calldata agentCardUri
    ) external returns (uint256 clonedAgentId);

    /**
     * @notice Execute warp operation via delegation
     * @param originalAgentHash Hash of external agent
     * @param originalCreator Original creator address
     * @param licenses Supply cap
     * @param licensePrice License price
     * @param agentCardUri Agent card URI
     * @return warpedAgentId The new warped agent ID
     */
    function delegateWarp(
        bytes32 originalAgentHash,
        address originalCreator,
        uint256 licenses,
        uint256 licensePrice,
        string calldata agentCardUri
    ) external returns (uint256 warpedAgentId);

    /**
     * @notice Execute lease creation via delegation
     * @param workflowId The Workflow to lease
     * @param duration Lease duration in days
     * @return leaseId The new lease ID
     */
    function delegateCreateLease(
        uint256 workflowId,
        uint256 duration
    ) external returns (uint256 leaseId);

    /**
     * @notice Execute lease termination via delegation
     * @param leaseId The lease to terminate
     */
    function delegateTerminateLease(uint256 leaseId) external;

    /**
     * @notice Get the manager contract address
     * @return manager The AgentManager address
     */
    function getManager() external view returns (address manager);
}
