// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAgentManager
 * @notice Interface for the AgentManager proxy contract
 * @dev Routes calls to Delegation contract and manages owned contracts
 */
interface IAgentManager {
    /// @notice Emitted when delegation contract is updated
    event DelegationUpdated(address indexed oldDelegation, address indexed newDelegation);

    /// @notice Emitted when a contract is registered
    event ContractRegistered(bytes32 indexed contractId, address indexed contractAddress);

    error NotAdmin();
    error ZeroAddress();
    error ContractNotRegistered(bytes32 contractId);
    error DelegationCallFailed();

    /**
     * @notice Set the delegation contract address
     * @param delegation New delegation contract address
     */
    function setDelegation(address delegation) external;

    /**
     * @notice Get the current delegation contract
     * @return delegation The delegation contract address
     */
    function getDelegation() external view returns (address delegation);

    /**
     * @notice Register a contract address
     * @param contractId The contract identifier
     * @param contractAddress The contract address
     */
    function registerContract(bytes32 contractId, address contractAddress) external;

    /**
     * @notice Get a registered contract address
     * @param contractId The contract identifier
     * @return contractAddress The contract address
     */
    function getContract(bytes32 contractId) external view returns (address contractAddress);

    /**
     * @notice Get the admin address
     * @return admin The admin address
     */
    function getAdmin() external view returns (address admin);

    /**
     * @notice Transfer admin rights
     * @param newAdmin The new admin address
     */
    function transferAdmin(address newAdmin) external;

    /**
     * @notice Execute a call via delegation
     * @param target Target contract to call
     * @param data Calldata to forward
     * @return result The call result
     */
    function execute(address target, bytes calldata data) external returns (bytes memory result);
}
