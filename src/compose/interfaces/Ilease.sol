// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ILease
 * @notice Interface for leasing Workflows
 * @dev Handles fee splitting between creator and leaser during lease period
 */
interface ILease {
    /// @notice Emitted when a lease is created
    event LeaseCreated(
        uint256 indexed leaseId,
        uint256 indexed workflowId,
        address indexed leaser,
        uint256 duration,
        uint8 creatorPercent
    );

    /// @notice Emitted when a lease is terminated
    event LeaseTerminated(uint256 indexed leaseId, uint256 indexed workflowId);

    /// @notice Emitted when lease fees are distributed
    event LeaseFeesDistributed(
        uint256 indexed leaseId,
        uint256 totalAmount,
        uint256 creatorShare,
        uint256 leaserShare
    );

    error LeaseNotFound(uint256 leaseId);
    error LeaseNotActive(uint256 leaseId);
    error LeaseExpired(uint256 leaseId);
    error InvalidLeaseDuration();
    error InvalidLeasePercent();
    error WorkflowNotLeasable(uint256 workflowId);
    error NotWorkflowOwner(uint256 workflowId);
    error NotLeaser(uint256 leaseId);
    error LeaseAlreadyExists(uint256 workflowId);

    /// @notice Lease status enum
    enum LeaseStatus {
        None,
        Active,
        Expired,
        Terminated
    }

    /**
     * @notice Lease data structure
     * @param workflowId The Workflow ID
     * @param leaser Address of the leaser
     * @param creator Address of the Workflow creator
     * @param startTime Lease start timestamp
     * @param endTime Lease end timestamp
     * @param creatorPercent Creator's share of usage fees (max 20%)
     * @param status Current lease status
     */
    struct LeaseData {
        uint256 workflowId;
        address leaser;
        address creator;
        uint256 startTime;
        uint256 endTime;
        uint8 creatorPercent;
        LeaseStatus status;
    }

    /**
     * @notice Create a new lease for a Workflow
     * @param workflowId The Workflow to lease
     * @param duration Lease duration in days
     * @return leaseId The newly created lease ID
     */
    function createLease(uint256 workflowId, uint256 duration) external returns (uint256 leaseId);

    /**
     * @notice Terminate a lease early
     * @param leaseId The lease to terminate
     */
    function terminateLease(uint256 leaseId) external;

    /**
     * @notice Get lease data
     * @param leaseId The lease ID
     * @return data The LeaseData struct
     */
    function getLeaseData(uint256 leaseId) external view returns (LeaseData memory data);

    /**
     * @notice Get active lease for a Workflow
     * @param workflowId The Workflow ID
     * @return leaseId The active lease ID (0 if none)
     */
    function getActiveLeaseFor(uint256 workflowId) external view returns (uint256 leaseId);

    /**
     * @notice Check if a Workflow is currently leased
     * @param workflowId The Workflow ID
     * @return isLeased True if there's an active lease
     */
    function isLeased(uint256 workflowId) external view returns (bool isLeased);

    /**
     * @notice Calculate fee split for a lease
     * @param leaseId The lease ID
     * @param totalAmount Total payment amount
     * @return creatorShare Amount for the creator
     * @return leaserShare Amount for the leaser
     */
    function calculateFeeSplit(
        uint256 leaseId,
        uint256 totalAmount
    ) external view returns (uint256 creatorShare, uint256 leaserShare);

    /**
     * @notice Distribute usage fees according to lease terms
     * @param leaseId The lease ID
     * @param amount Total payment amount
     */
    function distributeFees(uint256 leaseId, uint256 amount) external;

    /**
     * @notice Get current lease status
     * @param leaseId The lease ID
     * @return status The lease status
     */
    function getLeaseStatus(uint256 leaseId) external view returns (LeaseStatus status);

    /**
     * @notice Get all leases for a leaser
     * @param leaser The leaser address
     * @return leaseIds Array of lease IDs
     */
    function getLeasesFor(address leaser) external view returns (uint256[] memory leaseIds);

    /**
     * @notice Maximum lease percentage (20%)
     */
    function MAX_LEASE_PERCENT() external pure returns (uint8);
}

